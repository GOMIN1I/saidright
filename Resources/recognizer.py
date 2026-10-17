"""Saidright local recogniser worker (MLX Whisper or NVIDIA Parakeet TDT via parakeet-mlx).

JSON lines on stdin/stdout. Every request has an "id"; every reply echoes it and has a
"type" (progress | transcript | ready | error | pong). Nothing else is written to stdout.
Transcripts and audio are never written to stderr or any log.
"""
import argparse
import contextlib
import hashlib
import json
import os
import sys
import threading
import time
from pathlib import Path

PROTOCOL = sys.stdout
REPO = 'mlx-community/whisper-large-v3-turbo'
REVISION = 'a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb'
SAMPLE_RATE = 16000

# Phrases Whisper is known to produce on silence or noise. Only dropped when they are the
# whole output of a segment with little voiced audio, never from real speech.
HALLUCINATIONS = {
    'продолжение следует', 'субтитры сделал dimatorzok', 'субтитры создавал dimatorzok',
    'редактор субтитров а.семкин корректор а.егорова', 'спасибо за просмотр',
    'thank you for watching', 'thanks for watching', 'please subscribe',
    'untertitel im auftrag des zdf', 'untertitelung des zdf, 2020', '字幕由amara.org社区提供',
}


def emit(**payload):
    PROTOCOL.write(json.dumps(payload, ensure_ascii=False) + '\n')
    PROTOCOL.flush()


def log(message):
    """Diagnostics only: no audio, no transcript text."""
    sys.stderr.write(f'[recognizer] {message}\n')
    sys.stderr.flush()


class Worker:
    def __init__(self, model_dir: Path, cache_dir: Path, repo: str = REPO, revision: str = REVISION, engine: str = 'whisper'):
        self.engine = engine
        self.repo = repo
        self.revision = revision
        self.model_dir = model_dir
        self.cache_dir = cache_dir
        self.model = None
        self.np = None

    # ---------------------------------------------------------------- model
    def model_present(self):
        names = ('model.safetensors',) if self.engine == 'parakeet' else ('weights.npz', 'weights.safetensors')
        return (self.model_dir / 'config.json').exists() and any((self.model_dir / name).exists() for name in names)

    def load(self):
        if self.model is not None:
            return False
        if not self.model_present():
            raise WorkerError('model_missing', 'Model files are not installed.')
        import mlx.core as mx
        if self.engine == 'parakeet':
            from mlx.utils import tree_flatten, tree_unflatten
            from parakeet_mlx.utils import from_config
            with open(self.model_dir / 'config.json') as handle:
                model = from_config(json.load(handle))
            model.load_weights(str(self.model_dir / 'model.safetensors'))
            model.update(tree_unflatten([(k, v.astype(mx.bfloat16)) for k, v in tree_flatten(model.parameters())]))
            self.model = model
            self.run_parakeet(self.np.zeros(SAMPLE_RATE, dtype=self.np.float32))  # compile kernels
            return True
        from mlx_whisper.transcribe import ModelHolder
        self.model = ModelHolder.get_model(str(self.model_dir), mx.float16)
        self.cache_encoder(type(self.model.encoder))
        # Warm-up: one short silent decode compiles kernels so the first real request is fast.
        import mlx_whisper
        mlx_whisper.transcribe(self.np.zeros(SAMPLE_RATE, dtype=self.np.float32), path_or_hf_repo=str(self.model_dir), language='en', verbose=None, temperature=0.0)
        return True

    def cache_encoder(self, encoder_class):
        """Remembers the encoder output for the last few 30-second windows.

        Language ID, decoding, the temperature fallback, the word-timestamp pass and the
        recovery check each run the audio encoder on the same window; it is the most expensive
        step. The key is the exact window content, so a hit returns exactly what a new pass
        would compute."""
        if getattr(encoder_class, '_saidright_cached', False):
            return
        original = encoder_class.__call__
        np = self.np
        entries = []

        def cached(module, mel):
            data = np.asarray(mel)
            key = (id(module), data.shape, str(data.dtype), hashlib.blake2b(data.tobytes(), digest_size=16).digest())
            for stored_key, features in entries:
                if stored_key == key:
                    return features
            features = original(module, mel)
            entries.append((key, features))
            del entries[:-3]
            return features

        encoder_class.__call__ = cached
        encoder_class._saidright_cached = True

    def window_mel(self, segment):
        """The first 30-second window exactly as mlx_whisper.transcribe builds it, so language
        ID and decoding of the same audio share one encoder pass."""
        import mlx.core as mx
        from mlx_whisper.audio import N_FRAMES, N_SAMPLES, log_mel_spectrogram, pad_or_trim
        mel = log_mel_spectrogram(segment, n_mels=self.model.dims.n_mels, padding=N_SAMPLES)
        content = min(N_FRAMES, mel.shape[-2] - N_FRAMES)
        return pad_or_trim(mel[:content], N_FRAMES, axis=-2).astype(mx.float16)

    def prepare(self, rid):
        started = time.monotonic()
        if not self.model_present():
            self.download(rid)
        emit(id=rid, type='progress', stage='loading', fraction=None)
        self.load()
        emit(id=rid, type='ready', seconds=round(time.monotonic() - started, 3))

    def download(self, rid):
        os.environ['HF_HUB_DISABLE_PROGRESS_BARS'] = '1'
        from huggingface_hub import HfApi, snapshot_download
        patterns = ('config.json', 'model.safetensors') if self.engine == 'parakeet' else ('config.json', 'weights.safetensors', 'weights.npz')
        info = HfApi().model_info(self.repo, revision=self.revision, files_metadata=True, token=False)
        files = [s for s in info.siblings if s.rfilename in patterns]
        total = sum((s.size or 0) for s in files) or 1
        self.model_dir.mkdir(parents=True, exist_ok=True)
        done = threading.Event()
        failure = []

        def run():
            try:
                snapshot_download(self.repo, revision=self.revision, local_dir=str(self.model_dir), allow_patterns=list(patterns), token=False)
            except Exception as exc:  # reported below
                failure.append(exc)
            finally:
                done.set()

        threading.Thread(target=run, daemon=True).start()
        while not done.wait(0.5):
            size = sum(p.stat().st_size for p in self.model_dir.rglob('*') if p.is_file())
            emit(id=rid, type='progress', stage='downloading', fraction=min(0.99, size / total))
        if failure:
            raise WorkerError('download_failed', type(failure[0]).__name__)
        emit(id=rid, type='progress', stage='verifying', fraction=None)
        for sibling in files:
            expected = getattr(getattr(sibling, 'lfs', None), 'sha256', None)
            if not expected:
                continue
            digest = hashlib.sha256()
            with open(self.model_dir / sibling.rfilename, 'rb') as handle:
                for chunk in iter(lambda: handle.read(8 << 20), b''):
                    digest.update(chunk)
            if digest.hexdigest() != expected:
                (self.model_dir / sibling.rfilename).unlink(missing_ok=True)
                raise WorkerError('integrity', f'Checksum mismatch for {sibling.rfilename}')

    # ------------------------------------------------------------ segmenting
    def speech_regions(self, audio):
        """Energy VAD with an adaptive noise floor and hysteresis.

        Returns (start, end) sample ranges with padding, merged so that each region is long
        enough for reliable language identification and short enough for one Whisper window.
        """
        np = self.np
        hop = 480  # 30 ms
        count = len(audio) // hop
        if count == 0:
            return []
        frames = audio[: count * hop].reshape(count, hop)
        db = 20 * np.log10(np.sqrt(np.mean(frames * frames, axis=1)) + 1e-7)
        # Thresholds follow the recording's own noise floor. The absolute minimums only stop
        # digital silence and a very low hiss from counting; they are low enough for a quiet
        # microphone or a soft voice (speech around -60 dBFS was dropped before).
        floor = max(float(np.percentile(db, 15)), -90.0)
        enter = max(floor + 10.0, -70.0)
        stay = max(floor + 6.0, -74.0)
        self.voice_threshold = enter
        voiced = np.zeros(count, dtype=bool)
        active = False
        for i, level in enumerate(db):
            active = level > (stay if active else enter)
            voiced[i] = active
        # Remove isolated blips shorter than 90 ms.
        regions, start = [], None
        for i, v in enumerate(list(voiced) + [False]):
            if v and start is None:
                start = i
            elif not v and start is not None:
                if i - start >= 3:
                    regions.append([start, i])
                start = None
        if not regions:
            return []
        # Join regions separated by short pauses (< 450 ms).
        joined = [regions[0]]
        for a, b in regions[1:]:
            if a - joined[-1][1] < 15:
                joined[-1][1] = b
            else:
                joined.append([a, b])
        # Merge regions shorter than 1.2 s into a neighbour: language ID needs context.
        merged = []
        for region in joined:
            if merged and (region[1] - region[0] < 40 or merged[-1][1] - merged[-1][0] < 40) and region[1] - merged[-1][0] < 900:
                merged[-1][1] = region[1]
            else:
                merged.append(region)
        pad = 8  # 240 ms
        out = []
        for a, b in merged:
            a, b = max(0, a - pad), min(count, b + pad)
            # Split anything longer than 28 s at its quietest frame.
            while b - a > 930:
                window = db[a + 700 : a + 930]
                cut = a + 700 + int(np.argmin(window))
                out.append((a * hop, cut * hop))
                a = cut
            out.append((a * hop, min(len(audio), b * hop)))
        return out

    # ------------------------------------------------------------ recognition
    def detect(self, segment, allowed):
        _, probs = self.model.detect_language(self.window_mel(segment))
        if isinstance(probs, list):
            probs = probs[0]
        best = max(probs, key=probs.get)
        if not allowed or best in allowed:
            return best
        candidates = {code: probs.get(code, 0.0) for code in allowed}
        restricted = max(candidates, key=candidates.get)
        # The expected set prevents short Russian phrases from being read as Ukrainian or
        # Bulgarian. But when the speaker clearly uses another language, forcing an expected
        # one makes Whisper translate, which is never acceptable: keep the spoken language.
        if probs[best] >= 0.6 and candidates[restricted] < 0.15:
            log('language outside the expected set')
            return best
        return restricted

    def region_languages(self, req):
        """Language ID only (no decoding): the restricted language and its probability for
        each voiced region. Used to evaluate language-gated routing between engines."""
        import soundfile as sf
        self.load()
        started = time.monotonic()
        audio, rate = sf.read(req['path'], dtype='float32', always_2d=False)
        if audio.ndim == 2:
            audio = audio.mean(axis=1)
        if rate != SAMPLE_RATE:
            raise WorkerError('format', 'Expected 16 kHz audio.')
        allowed = [code for code in req.get('languages') or [] if code]
        found = []
        for a, b in self.speech_regions(audio):
            _, probs = self.model.detect_language(self.window_mel(audio[a:b]))
            probs = probs[0] if isinstance(probs, list) else probs
            pool = {code: probs.get(code, 0.0) for code in allowed} if allowed else probs
            best = max(pool, key=pool.get)
            found.append({'language': best, 'probability': round(float(pool[best]) / max(1e-9, float(sum(pool.values()))), 3), 'seconds': round((b - a) / SAMPLE_RATE, 2)})
        emit(id=req['id'], type='languages', regions=found, seconds=round(time.monotonic() - started, 3))

    def run_whisper_covering(self, audio, language, prompt, allowed):
        """Whisper decodes a whole region in one language and silently drops speech in another
        (e.g. an English sentence right after a Russian one, without a pause). With several
        expected languages, word timestamps show which voiced audio produced no words; those
        spans are decoded again in their own language and put back in time order."""
        if len(allowed) < 2:
            return self.run_whisper(audio, language, prompt)
        np = self.np
        # Segment timestamps cost nothing extra and catch most misses. Only when the text is
        # clearly too short for the amount of voice (fewer than ~9 characters per voiced
        # second; normal speech gives 12–16) are the costlier word timestamps used.
        pieces = self.run_whisper(audio, language, prompt, words='segments')
        voiced_seconds = self.voiced_seconds(audio)
        chars = sum(len(text) for _, _, text in pieces)
        if voiced_seconds > 1.5 and chars < 9 * voiced_seconds:
            pieces = self.run_whisper(audio, language, prompt, words='words')
        covered = np.zeros(len(audio) // 480 + 1, dtype=bool)
        for start, end, _ in pieces:
            covered[max(0, int((start - 0.15) * SAMPLE_RATE / 480)): int((end + 0.15) * SAMPLE_RATE / 480) + 1] = True
        hop = 480
        count = len(audio) // hop
        frames = audio[: count * hop].reshape(count, hop) if count else np.zeros((0, hop), dtype=np.float32)
        db = 20 * np.log10(np.sqrt(np.mean(frames * frames, axis=1)) + 1e-7) if count else np.zeros(0)
        threshold = getattr(self, 'voice_threshold', -55.0)
        gaps, start = [], None
        for i in range(count + 1):
            missing = i < count and db[i] > threshold and not covered[i]
            if missing and start is None:
                start = i
            # Allow short dips inside a missed phrase.
            elif not missing and start is not None and (i >= count or not any(db[j] > threshold and not covered[j] for j in range(i, min(count, i + 10)))):
                if i - start >= 20:  # at least 0.6 s of uncovered voice
                    gaps.append((start, i))
                start = None
        others = [code for code in allowed if code != language] or allowed
        # A missed phrase is as loud as the recognised speech; breaths and room noise after
        # the last word are much quieter and must not be "recovered" (Whisper invents
        # subtitle credits on them).
        spoken_levels = db[covered[:count] & (db > threshold)] if count else db
        speech_level = float(np.median(spoken_levels)) if len(spoken_levels) else threshold + 20
        for a, b in gaps:
            if float(np.median(db[a:b])) < speech_level - 12:
                continue
            a0, b0 = max(0, (a - 6) * hop), min(len(audio), (b + 6) * hop)
            segment = audio[a0:b0]
            code = self.detect(segment, others) if len(others) > 1 else others[0]
            for start, end, text in self.run_whisper(segment, code, None, words='strict'):
                if self.looks_hallucinated(text):
                    continue
                pieces.append((start + a0 / SAMPLE_RATE, end + a0 / SAMPLE_RATE, text))
                log('recovered speech in another language')
        pieces.sort(key=lambda item: item[0])
        return ' '.join(text for _, _, text in pieces if text).strip()

    @staticmethod
    def looks_hallucinated(text):
        t = text.lower().strip(' .!?…')
        return t in HALLUCINATIONS or any(mark in t for mark in ('субтитр', 'dimatorzok', 'продолжение следует', 'amara.org', 'thanks for watching', 'untertitel'))

    def voiced_seconds(self, audio):
        np = self.np
        hop = 480
        count = len(audio) // hop
        if not count:
            return 0.0
        frames = audio[: count * hop].reshape(count, hop)
        db = 20 * np.log10(np.sqrt(np.mean(frames * frames, axis=1)) + 1e-7)
        return float(np.sum(db > getattr(self, 'voice_threshold', -55.0))) * hop / SAMPLE_RATE

    def run_whisper(self, audio, language, prompt, words=None):
        """words: None = plain text; 'segments' or 'words' = (start, end, text) per segment."""
        import mlx_whisper
        result = mlx_whisper.transcribe(
            audio,
            path_or_hf_repo=str(self.model_dir),
            language=language,
            task='transcribe',
            temperature=(0.0, 0.2, 0.4),
            compression_ratio_threshold=2.4,
            logprob_threshold=-1.0,
            no_speech_threshold=0.6,
            condition_on_previous_text=False,
            initial_prompt=prompt or None,
            word_timestamps=words == 'words',

            verbose=None,
        )
        kept = []
        for seg in result.get('segments', []):
            if seg.get('no_speech_prob', 0) > 0.6 and seg.get('avg_logprob', 0) < -1.0:
                continue
            # Recovered fragments must be confident: they are short and have no context.
            if words == 'strict' and (seg.get('no_speech_prob', 0) > 0.35 or seg.get('avg_logprob', 0) < -0.7):
                continue
            text = seg['text'].strip()
            if words:
                spoken = seg.get('words') or [] if words == 'words' else []
                start = spoken[0]['start'] if spoken else seg['start']
                end = spoken[-1]['end'] if spoken else seg['end']
                kept.append((float(start), float(end), text))
            else:
                kept.append(text)
        if words:
            return [item for item in kept if item[2]]
        return ' '.join(t for t in kept if t).strip()

    def run_parakeet(self, audio):
        import mlx.core as mx
        from parakeet_mlx.audio import get_logmel
        # Float32 input: the STFT view in get_logmel assumes it (bf16 audio breaks the shapes).
        mel = get_logmel(mx.array(audio, dtype=mx.float32), self.model.preprocessor_config)
        return self.model.generate(mel)[0].text.strip()

    @staticmethod
    def languages_in(text, allowed):
        """Parakeet does not report a language; infer it from the script of the words."""
        cyr = sum(1 for ch in text if '\u0400' <= ch <= '\u04ff')
        lat = sum(1 for ch in text if ch.isascii() and ch.isalpha())
        found = []
        cyrillic = [c for c in allowed if c in ('ru', 'uk', 'bg')] or ['ru']
        latin = [c for c in allowed if c not in ('ru', 'uk', 'bg', 'zh', 'ja', 'ko')] or ['en']
        if cyr:
            found.append(cyrillic[0])
        if lat and lat >= 3:
            found.append(latin[0])
        return found

    def transcribe_parakeet(self, req, audio, cold, started):
        rid = req['id']
        regions = self.speech_regions(audio)
        if not regions:
            emit(id=rid, type='transcript', text='', languages=[], seconds=round(time.monotonic() - started, 3), cold=cold, segments=0)
            return
        # One pass over the voiced span keeps sentence context; pauses inside are short enough.
        a, b = regions[0][0], regions[-1][1]
        text = self.run_parakeet(audio[a:b])
        if text and text.lower().strip(' .!?…') in HALLUCINATIONS and (b - a) / SAMPLE_RATE < 4:
            text = ''
        languages = [code for code in req.get('languages') or [] if code]
        emit(id=rid, type='transcript', text=text, languages=self.languages_in(text, languages) if text else [], seconds=round(time.monotonic() - started, 3), cold=cold, segments=1)

    def transcribe(self, req):
        rid = req['id']
        np = self.np
        import soundfile as sf
        cold = self.load()
        started = time.monotonic()
        audio, rate = sf.read(req['path'], dtype='float32', always_2d=False)
        if audio.ndim == 2:
            audio = audio.mean(axis=1)
        if rate != SAMPLE_RATE:
            raise WorkerError('format', 'Expected 16 kHz audio.')
        if self.engine == 'parakeet':
            self.transcribe_parakeet(req, audio, cold, started)
            return
        languages = [code for code in req.get('languages') or [] if code]
        prompt = req.get('prompt')
        regions = self.speech_regions(audio)
        if not regions:
            emit(id=rid, type='transcript', text='', languages=[], seconds=round(time.monotonic() - started, 3), cold=cold, segments=0)
            return

        if len(languages) == 1:
            plan = [(languages[0], [audio[a:b] for a, b in regions])]
        else:
            # Identify each region's language (restricted to the expected set), then join
            # consecutive regions of the same language so Whisper sees full context.
            plan = []
            for a, b in regions:
                code = self.detect(audio[a:b], languages)
                if plan and plan[-1][0] == code:
                    plan[-1][1].append(audio[a:b])
                else:
                    plan.append((code, [audio[a:b]]))

        texts, used = [], []
        gap = np.zeros(int(0.3 * SAMPLE_RATE), dtype=np.float32)
        for code, pieces in plan:
            joined = pieces[0]
            for piece in pieces[1:]:
                joined = np.concatenate([joined, gap, piece])
            text = self.run_whisper_covering(joined, code, prompt, languages)
            voiced_seconds = len(joined) / SAMPLE_RATE
            if text and text.lower().strip(' .!?…') in HALLUCINATIONS and voiced_seconds < 4:
                text = ''
            if text:
                texts.append(text)
                if code not in used:
                    used.append(code)
        emit(id=rid, type='transcript', text=' '.join(texts).strip(), languages=used, seconds=round(time.monotonic() - started, 3), cold=cold, segments=len(plan))


class WorkerError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model-dir', required=True)
    parser.add_argument('--cache-dir', required=True)
    parser.add_argument('--repo', default=REPO)
    parser.add_argument('--revision', default=REVISION)
    parser.add_argument('--engine', choices=('whisper', 'parakeet'), default='whisper')
    args = parser.parse_args()
    os.environ['HF_HOME'] = args.cache_dir
    os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
    os.environ['HF_HUB_DISABLE_XET'] = '1'
    os.environ['TOKENIZERS_PARALLELISM'] = 'false'
    worker = Worker(Path(args.model_dir), Path(args.cache_dir), args.repo, args.revision, args.engine)
    # Libraries sometimes print to stdout; keep the protocol channel clean.
    with contextlib.redirect_stdout(sys.stderr):
        import numpy
        worker.np = numpy
        log('started')
        for line in sys.stdin:
            rid = '?'
            try:
                req = json.loads(line)
                rid = str(req.get('id', '?'))
                command = req.get('command')
                if command == 'ping':
                    emit(id=rid, type='pong', model_loaded=worker.model is not None)
                elif command == 'prepare':
                    worker.prepare(rid)
                elif command == 'transcribe':
                    worker.transcribe(req)
                elif command == 'languages' and worker.engine == 'whisper':
                    worker.region_languages(req)
                else:
                    raise WorkerError('protocol', 'Unknown command')
            except WorkerError as exc:
                log(f'error {exc.code}')
                emit(id=rid, type='error', code=exc.code, message=exc.message[:300])
            except MemoryError:
                log('error memory')
                emit(id=rid, type='error', code='memory', message='Not enough memory to run the model.')
            except Exception as exc:  # bounded, no user content
                log(f'error {type(exc).__name__}')
                emit(id=rid, type='error', code='internal', message=type(exc).__name__)


if __name__ == '__main__':
    main()
