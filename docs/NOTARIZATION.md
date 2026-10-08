# Notarization

**Status: blocked.** Notarization needs the Apple Developer Program ($99/year).
Until then, releases are signed with the local "AloeNotch Signing" certificate,
and first-time downloaders approve the app under System Settings → Privacy &
Security → Open Anyway.

Everything below is ready. When the account exists, it should be one
afternoon's work.

## What's already in place

- `scripts/make-dmg.sh` signs the nested media-adapter dylib
  (`Resources/MediaRemoteAdapterLib.dat`) before the app, inside out.
  `--deep` never reached it because it isn't in a standard code location, and
  the notary service rejects any Mach-O that isn't Developer ID signed.
- With a Developer ID identity, it adds a secure timestamp (`--timestamp`) to
  every signature, and signs the DMG itself.
- It refuses `NOTARY_PROFILE` with any identity other than a Developer ID, so a
  doomed upload fails in a second instead of after the round trip.
- `scripts/notarize.sh` checks every Mach-O in the DMG locally before it uploads
  anything: Developer ID authority, timestamp, and hardened runtime. It then
  submits, prints the notary log if the result isn't `Accepted`, staples, and
  confirms with `stapler validate` and `spctl`.
- The hardened runtime is already on, and the entitlements file already
  carries what it needs: calendars, location, audio input, and
  disable-library-validation for the adapter.

## One-time setup, after enrolling

1. In Xcode → Settings → Accounts, sign in. Then go to Manage Certificates →
   **+** → **Developer ID Application**. It lands in the login keychain.
   Back it up (export with the private key) next to the "AloeNotch Signing"
   backup.
2. Create an app-specific password at account.apple.com → Sign-In and
   Security.
3. Store the notary credentials in the keychain once:

   ```bash
   xcrun notarytool store-credentials aloenotch --apple-id <apple id> --team-id <TEAMID> --password <app-specific password>
   ```

## Each release

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=aloenotch ./scripts/release.sh 0.14.0
```

`release.sh` passes both through to `make-dmg.sh`, which calls
`notarize.sh`. Then follow the usual `--ship` step.

## ⚠ Permissions reset once

Switching from "AloeNotch Signing" to a Developer ID certificate changes the
app's designated requirement. Calendar, Location, Accessibility, and Screen &
System Audio grants will be asked for **once more** on the first notarized
update. Say so in that release's changelog and What's New. It happens once;
every later Developer ID release keeps the grants.

## After notarization

- The README's and the site's "Open Anyway" instructions can go.
- The Homebrew cask becomes possible (see `docs/HOMEBREW.md`).
