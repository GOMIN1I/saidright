# From source to a release

## Local development build

```
swift test
python3 scripts/check-localization.py
scripts/build-app.sh            # build/Saywell.app, signed with an Apple Development identity if present
```

Ad hoc signing works but macOS then forgets Microphone, Input Monitoring and Accessibility after every rebuild because grants are bound to the code hash. With a stable identity the designated requirement (team + bundle id) stays the same, and grants survive rebuilds.

## Free public release (no paid accounts)

1. Push the repository to GitHub (public). In Settings → Pages choose **GitHub Actions** as the source; `.github/workflows/pages.yml` publishes `site/` to `https://<user>.github.io/<repo>/`.
2. Set `REPO` at the top of the script in `site/index.html` to `<user>/<repo>` so the download buttons point to `releases/latest/download/Saywell.dmg`.
3. Tag and push: `git tag v0.5.0 && git push origin v0.5.0`. `.github/workflows/release.yml` builds an **ad hoc signed** app on GitHub's macOS runner, makes `Saywell.dmg` + `.sha256`, and creates a pre-release with `docs/release-notes/<version>.md`. Try it, then run Actions → *Promote* (`promote`) so it becomes the latest release that the page links to; `rollback` reverses that (details in [GITHUB.md](GITHUB.md)).
4. Or build locally without the personal certificate: `SAYWELL_SIGN_IDENTITY=- SAYWELL_BUILD_DIR=build/public scripts/build-app.sh && SAYWELL_APP=build/public/Saywell.app SAYWELL_DMG=dist/Saywell.dmg scripts/make-dmg.sh`, then `gh release create v0.5.0 dist/Saywell.dmg --prerelease --notes-file docs/release-notes/0.5.0.md`.

Users then open the app once via System Settings → Privacy & Security → Open Anyway (explained on the page and in the README). Ad hoc signed apps keep permissions until the next version replaces the binary.

## Notarized release (requires a paid Apple Developer membership)

1. **Developer ID**: a paid Apple Developer Program membership and a “Developer ID Application” certificate. An “Apple Development” certificate is for local testing only.
2. Build: `SAYWELL_SIGN_IDENTITY="Developer ID Application: … (TEAMID)" scripts/build-app.sh` (hardened runtime is already enabled; the only entitlement is audio input).
3. Package: `SAYWELL_DMG_LABEL="" scripts/make-dmg.sh` creates `dist/Saywell-<version>.dmg`. Without the variable the file is named `…-dev-preview-unnotarized.dmg` so a local build cannot be mistaken for a release.
4. Notarize: `xcrun notarytool submit dist/Saywell-<version>.dmg --keychain-profile <profile> --wait`, then `xcrun stapler staple dist/Saywell-<version>.dmg`.
5. Verify on a clean macOS account: `spctl -a -vv build/Saywell.app`, first-run onboarding, runtime install, permissions.
6. GitHub Release notes must state: version, macOS 14+ and **Apple silicon only**, DMG size, that the recogniser (~2.3 GB) is downloaded inside the app, that cloud editing is optional and billed by the provider, and known limitations from `docs/TESTING.md`.

Never instruct users to disable Gatekeeper or SIP. If notarization is not available, label the build “unsigned developer preview” and explain right-click → Open.

## Bundle identifier

The bundle id is `io.github.gomin1i.saywell`. It was set once with `scripts/set-bundle-id.sh <github-user>`, which writes `io.github.<user>.saywell` into `Resources/Info.plist`, the only place it is defined (`build-app.sh` reads it from there). Changing it later resets macOS permissions, so do it once. After a change: grant Microphone, Input Monitoring and Accessibility again, and allow Keychain access when macOS asks (the saved key stays; its service name does not depend on the bundle id). Data under `~/Library/Application Support/Saywell` is unaffected.

## Updates

No updater is included. Options: Sparkle 2 (EdDSA-signed appcast hosted with releases) or a “new version available” check against the GitHub Releases API. Both need owner decisions on hosting and signing keys.
