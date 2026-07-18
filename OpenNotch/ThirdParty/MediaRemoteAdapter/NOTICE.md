# MediaRemoteAdapter (vendored)

Source: https://github.com/ungive/mediaremote-adapter
Commit: 3ac3d4bdf862c7b5399b4fba4df5689f5c38609a
License: BSD 3-Clause (see LICENSE-mediaremote-adapter.txt)

## What this is

macOS 15.4 removed third-party access to the private MediaRemote framework's
now-playing APIs. This adapter works around it: `/usr/bin/perl` carries the
Apple bundle identifier `com.apple.perl`, so a perl process IS entitled to use
MediaRemote. The perl script loads `MediaRemoteAdapterLib` (an ObjC dylib) via
DynaLoader and streams system-wide now-playing data as JSON on stdout —
covering every source that publishes to the system's now-playing center
(Apple Music, Spotify, YouTube in Safari/Chrome, Podcasts, etc.).

NOT App Store safe (private API). This app is personal/off-store only.

## Files

- `mediaremote-adapter.pl` — the entitled entry point, run via /usr/bin/perl.
- `MediaRemoteAdapterLib.dat` — the adapter dylib (the .dat extension keeps
  Xcode's synchronized-group file classification treating it as a plain
  resource to copy, not a binary to link), built arm64-only with:
  `clang -dynamiclib -fobjc-arc -O2 -arch arm64 -Iinclude -Isrc
   src/adapter/*.m src/private/*.m src/utility/*.m
   -framework Foundation -framework AppKit -framework CoreFoundation
   -framework UniformTypeIdentifiers -o MediaRemoteAdapter`
  (At runtime the app installs it into Application Support as
  `MediaRemoteAdapter.framework/MediaRemoteAdapter`, the layout the perl
  script expects.)

## Rebuilding

Clone the repo at the commit above and run the clang command from its root.
Add `-arch x86_64` alongside `-arch arm64` for a universal binary if needed.
