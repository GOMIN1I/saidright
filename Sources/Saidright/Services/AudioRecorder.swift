import AVFoundation
import CoreAudio
import Foundation

struct InputDevice: Identifiable, Hashable {
    var id: String { uid }
    var uid: String
    var name: String
    var deviceID: AudioDeviceID
    var isDefault: Bool
}

enum RecorderError: Error {
    case microphoneDenied
    case noInputDevice
    case engineFailed(String)
    case deviceUnavailable
}

/// Captures microphone audio with AVAudioEngine, converts it to 16 kHz mono and writes a WAV.
/// Also measures level and how much of the recording contains sound above the noise floor,
/// so silent recordings can be reported honestly instead of sent to the recogniser.
final class AudioRecorder: @unchecked Sendable {
    struct Result {
        var url: URL
        var duration: TimeInterval
        /// Seconds with energy clearly above the noise floor (rough speech estimate).
        var voicedSeconds: TimeInterval
        var peakDB: Float
        var interrupted: Bool
    }

    /// Called on the main thread ~30 times per second while recording (0…1).
    var onLevel: ((Float) -> Void)?
    /// Called on the main thread when the input device disappears or changes format.
    var onInterruption: (() -> Void)?

    private let engine = AVAudioEngine()
    private let writeQueue = DispatchQueue(label: "saidright.audio.write")
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var url: URL?
    private var startedAt: Date?
    private var framesWritten: AVAudioFramePosition = 0
    private var voicedFrames: AVAudioFramePosition = 0
    private var floorDB: Float = -60
    private var peakDB: Float = -160
    private var lastLevelEmit = Date.distantPast
    private var interrupted = false
    private var configObserver: NSObjectProtocol?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    /// Test hook: when set (environment SAIDRIGHT_TEST_AUDIO), this file is "recorded" instead of the microphone.
    private let testAudio = ProcessInfo.processInfo.environment["SAIDRIGHT_TEST_AUDIO"].map(URL.init(fileURLWithPath:))

    var isRecording: Bool { url != nil }
    var usesTestAudio: Bool { testAudio != nil }

    func start(deviceUID: String?) throws -> URL {
        let destination = Paths.recordings.appendingPathComponent(UUID().uuidString + ".wav")
        resetCounters()
        if let testAudio {
            try FileManager.default.copyItem(at: testAudio, to: destination)
            url = destination
            startedAt = Date()
            playTestLevels(testAudio)
            return destination
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw RecorderError.microphoneDenied }

        let input = engine.inputNode
        if let uid = deviceUID, let device = Self.devices().first(where: { $0.uid == uid }) {
            var id = device.deviceID
            let status = AudioUnitSetProperty(input.audioUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr { Log.error("select input device failed \(status)") }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInputDevice }
        guard let converter = AVAudioConverter(from: format, to: target) else { throw RecorderError.engineFailed("converter") }
        self.converter = converter
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        file = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.process(buffer, inputRate: format.sampleRate)
        }
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.interrupted = true
            self.onInterruption?()
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            file = nil
            try? FileManager.default.removeItem(at: destination)
            throw RecorderError.engineFailed(String(describing: type(of: error)))
        }
        url = destination
        startedAt = Date()
        return destination
    }

    private var testLevelTimer: Timer?

    /// Feeds the level meter from the test file in real time so the UI behaves as with a microphone.
    private func playTestLevels(_ file: URL) {
        guard let audio = try? AVAudioFile(forReading: file),
              let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)),
              (try? audio.read(into: buffer)) != nil, buffer.floatChannelData != nil else { return }
        let rate = audio.processingFormat.sampleRate
        let count = Int(buffer.frameLength)
        let start = Date()
        testLevelTimer?.invalidate()
        testLevelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            let index = Int(Date().timeIntervalSince(start) * rate)
            let end = min(count, index + Int(rate / 30))
            guard index < count, end > index, let samples = buffer.floatChannelData?[0] else { timer.invalidate(); return }
            var sum: Float = 0
            for i in index..<end { sum += samples[i] * samples[i] }
            let db = 20 * log10(max(sqrt(sum / Float(end - index)), 1e-7))
            self?.onLevel?(max(0, min(1, (db + 55) / 45)))
        }
    }

    /// Stops and finalises the file. Safe to call more than once.
    func stop() -> Result? {
        guard let url else { return nil }
        if testAudio != nil {
            testLevelTimer?.invalidate()
            self.url = nil
            let file = try? AVAudioFile(forReading: url)
            let duration = file.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
            return Result(url: url, duration: duration, voicedSeconds: duration, peakDB: -10, interrupted: false)
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        // Drain pending writes before closing the file.
        let (frames, voiced, peak) = writeQueue.sync { () -> (AVAudioFramePosition, AVAudioFramePosition, Float) in
            self.file = nil
            return (self.framesWritten, self.voicedFrames, self.peakDB)
        }
        self.url = nil
        return Result(url: url, duration: Double(frames) / 16_000, voicedSeconds: Double(voiced) / 16_000, peakDB: peak, interrupted: interrupted)
    }

    /// Stops and deletes the recording (cancel, discarded hold, chord).
    func discard() {
        if let result = stop() { try? FileManager.default.removeItem(at: result.url) }
    }

    private func resetCounters() {
        framesWritten = 0
        voicedFrames = 0
        floorDB = -60
        peakDB = -160
        interrupted = false
    }

    private func process(_ buffer: AVAudioPCMBuffer, inputRate: Double) {
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / inputRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let samples = out.floatChannelData?[0] else { return }
        let count = Int(out.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 1e-7))
        writeQueue.async { [weak self] in
            guard let self, let file = self.file else { return }
            do { try file.write(from: out) } catch { Log.error("audio write failed") }
            self.framesWritten += AVAudioFramePosition(count)
            // Slowly adapting noise floor; fast downward, slow upward.
            self.floorDB = db < self.floorDB ? db : self.floorDB + 0.02 * (db - self.floorDB)
            // Same relative rule as the recogniser's VAD, so a quiet voice is not called silence.
            if db > max(self.floorDB + 10, -70) { self.voicedFrames += AVAudioFramePosition(count) }
            self.peakDB = max(self.peakDB, db)
        }
        let now = Date()
        if now.timeIntervalSince(lastLevelEmit) > 1.0 / 30 {
            lastLevelEmit = now
            let level = max(0, min(1, (db + 55) / 45))
            DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
        }
    }

    // MARK: Devices

    static func devices() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        let defaultID = defaultInputID()
        return ids.compactMap { id in
            guard inputChannels(id) > 0, let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            return InputDevice(uid: uid, name: name, deviceID: id, isDefault: id == defaultID)
        }
    }

    private static func defaultInputID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Notifies when devices are added, removed or the default input changes.
    static func observeDeviceChanges(_ handler: @escaping @Sendable () -> Void) {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { _, _ in handler() }
        }
    }
}
