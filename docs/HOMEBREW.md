# Homebrew

**Status: blocked on notarization** (see `docs/NOTARIZATION.md`).

Homebrew 5.0.0 (November 2025) deprecated casks that fail Gatekeeper.
It also deprecated the `--no-quarantine` escape hatch. The official
`homebrew/cask` repository disables such casks from September 2026.
AloeNotch is currently signed with a local certificate, not a Developer ID,
so it would be rejected from `homebrew/cask`. A personal tap would still
install it, but every user would hit the same "Open Anyway" step as the DMG,
with no flag to skip it. That's a worse first run than downloading from
the site, so there is no point shipping a cask until releases are notarized.

Sources:
- [Homebrew 5.0.0 release notes](https://brew.sh/2025/11/12/homebrew-5.0.0)
- [What Homebrew 5.0.0 means for your Mac fleet (Workbrew)](https://workbrew.com/blog/what-homebrew-5-0-0-means-for-your-mac-fleet)
- Other unsigned apps hit by the same policy:
  [TomatoBar #102](https://github.com/ivoronin/TomatoBar/issues/102),
  [CopyQ #3498](https://goodfirstissue.org/hluk/CopyQ/issues/3498),
  [PowerShell #26629](https://github.com/PowerShell/PowerShell/issues/26629)

## Once notarization works

1. Ship a notarized release (`SIGN_IDENTITY=… NOTARY_PROFILE=… ./scripts/release.sh --ship`).
2. Check the cask against the stapled DMG:
   `spctl -a -t open --context context:primary-signature -v build/AloeNotch-X.Y.Z.dmg`
   should report `source=Notarized Developer ID`.
3. Pick where it lives:
   - **Personal tap** (`xnucade/homebrew-tap`, file `Casks/aloenotch.rb`).
     It's available immediately and you control it, so start here.
   - **`homebrew/cask`.** Needs the notability bar for self-submitted apps
     (roughly 75+ stars, or 30+ forks or watchers) and a passing
     `brew audit --new --cask aloenotch`. Once it lands, Homebrew's autobump
     bot follows the appcast, so no per-release PR is needed.
4. Fill in `version` and `sha256` (`shasum -a 256 build/AloeNotch-X.Y.Z.dmg`),
   then run `brew audit --cask --strict --online aloenotch` and
   `brew install --cask aloenotch` on a clean user account.

## Draft cask

```ruby
cask "aloenotch" do
  version "X.Y.Z"
  sha256 "REPLACE_WITH_SHASUM"

  url "https://aloenotch.com/assets/AloeNotch-#{version}.dmg"
  name "AloeNotch"
  desc "Turns the MacBook notch into a home for media, calendar and system HUDs"
  homepage "https://aloenotch.com/"

  livecheck do
    url "https://aloenotch.com/appcast.xml"
    strategy :sparkle
  end

  # Sparkle updates the app in place; brew must not fight it.
  auto_updates true
  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  app "AloeNotch.app"

  uninstall quit: "com.kadeslab.AloeNotch"

  zap trash: [
    "~/Library/Application Support/AloeNotch",
    "~/Library/Caches/com.kadeslab.AloeNotch",
    "~/Library/HTTPStorages/com.kadeslab.AloeNotch",
    "~/Library/Preferences/com.kadeslab.AloeNotch.plist",
  ]
end
```

Notes on the draft:
- **`arm64` only.** Intel support ended with 0.6.0, the last Intel DMG.
- **`:tahoe`.** The deployment target is macOS 26.
- **`zap`** lists every place the app writes. Clipboard history is never on
  disk, so there is nothing else to clean. Re-check the list against
  `~/Library` on a clean install before submitting.
- **No `--no-quarantine` caveat.** It's deprecated, and a notarized build
  doesn't need it.
