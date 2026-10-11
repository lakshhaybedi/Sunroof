# Releasing Sunroof

## Build it yourself (no Apple account needed)

```bash
brew install xcodegen
xcodegen
xcodebuild -project Sunroof.xcodeproj -scheme Sunroof -configuration Release -derivedDataPath build build
scripts/make-dmg.sh build/Build/Products/Release/Sunroof.app dist
```

Local builds are signed ad-hoc and can't auto-update. macOS blocks the first launch of an unsigned download: open it once, then System Settings › Privacy & Security › **Open Anyway** (macOS 15+ no longer offers right-click → Open). For a build you made yourself there's no quarantine and it opens normally.

`scripts/perf.sh` measures memory, CPU, wake-ups and threads against the performance budget (it uses temporary folders and restores your settings).

## One-time setup for signed, notarized, auto-updating releases

1. **Apple Developer Program** membership (paid).
2. **Developer ID Application certificate** — Xcode › Settings › Accounts › Manage Certificates › + › *Developer ID Application*. Export it from Keychain Access as a `.p12` with a password, then:
   - `DEVELOPER_ID_P12` = `base64 -i cert.p12 | pbcopy`
   - `DEVELOPER_ID_P12_PASSWORD` = the export password
3. **App Store Connect API key** (for notarization) — App Store Connect › Users and Access › Integrations › App Store Connect API › + (role *Developer*). Download the `.p8` once.
   - `ASC_KEY_ID`, `ASC_ISSUER_ID` (shown on that page)
   - `ASC_KEY_P8` = the full contents of the `.p8` file
4. **Sparkle update key** — download the Sparkle release matching `Package.resolved`, then run `./bin/generate_keys`. It stores the private key in your login keychain and prints the public key.
   - Put the **public** key in `project.yml` → `SPARKLE_PUBLIC_KEY`, commit.
   - `./bin/generate_keys -x private-key.txt` → `SPARKLE_ED_PRIVATE_KEY` = its contents. Delete the file afterwards.
5. Add the secrets above in GitHub › the repo › Settings › Secrets and variables › Actions.
6. **GitHub Pages** — after the first release creates the `gh-pages` branch: Settings › Pages › Deploy from branch › `gh-pages` / root. The app reads `https://lakshhaybedi.github.io/Sunroof/appcast.xml`.

## Each release

1. Bump `MARKETING_VERSION` in `project.yml` (the build number follows it automatically — Sparkle compares it).
2. Add a `## X.Y.Z` section at the top of `CHANGELOG.md`.
3. Commit, then `git tag vX.Y.Z && git push origin main vX.Y.Z`.

The **Release** workflow tests, builds a Universal app, signs it with your Developer ID (hardened runtime), notarizes and staples the `.dmg`, publishes a GitHub Release with the changelog section, and adds the update to the appcast. Any step whose secrets are missing is skipped with a warning; without signing secrets you get an unsigned `.dmg`. Updates are only added to the appcast for signed **and** notarized builds.
