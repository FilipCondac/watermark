# WaterMark 💧

A macOS menu-bar app that estimates the water footprint of your Claude Code usage,
computed entirely from local transcripts. Nothing leaves your machine.

The bar shows **today's** estimated water. Click it for last-7-days, all-time, a
per-model breakdown, and the water rate setting.

## How it works

- Reads `~/.claude/projects/**/*.jsonl` (the transcripts Claude Code already writes).
- Sums tokens per assistant turn, deduped by message id, bucketed by local day.
- **Effective tokens** = `input + output + cache_creation`. Cache *reads* are
  excluded as cheap retrieval, not fresh compute.
- **Water** = `effective_tokens ÷ 1000 × rate`. Default rate: **0.5 mL / 1k tokens**
  (a conservative midpoint — editable in the menu).
- Rescans every 60s, only re-parsing files whose size/mtime changed.

The water rate is a rough indicator, not a measurement: real data-centre water use
depends heavily on the model, cooling design (WUE), and local grid water intensity.
See *About / methodology* in the app.

## Install

### Homebrew (recommended)

```bash
brew install --cask filipcondac/tap/watermark
```

That's it — the app lands in `/Applications` and the cask removes the
quarantine flag on install, so it opens with no Gatekeeper warning. Launch it
from Spotlight/Applications, then turn on *Launch at login* from the menu.

**No admin rights?** If you're not an administrator (e.g. a managed Mac),
installing to `/Applications` will ask for a password. Install into your home
folder instead — no password needed:

```bash
HOMEBREW_CASK_OPTS="--appdir=~/Applications" brew install --cask filipcondac/tap/watermark
```

### Manual download

Grab `WaterMark.zip` from the [latest release](https://github.com/FilipCondac/watermark/releases/latest),
unzip, and move `WaterMark.app` to `/Applications`. Because it isn't notarized
(no paid Apple Developer account), clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/WaterMark.app
open /Applications/WaterMark.app
```

> The app **is** code-signed (ad-hoc), so it runs fine on Apple Silicon — the
> quarantine step just skips the "unidentified developer" prompt that
> un-notarized apps trigger.

## Build from source

```bash
./build_app.sh           # compiles + assembles WaterMark.app
open WaterMark.app
```

## Releasing

Tag a commit and push — the GitHub Actions workflow builds the app, attaches
`WaterMark.zip` to a Release, and (if the `TAP_GITHUB_TOKEN` secret is set)
bumps the cask in `FilipCondac/homebrew-tap`:

```bash
git tag v1.0.1 && git push --tags
```

## Project layout

| File | Purpose |
|------|---------|
| `Sources/WaterMark/Main.swift` | Entry point (accessory app, no Dock icon) |
| `Sources/WaterMark/AppDelegate.swift` | Menu bar item, menu, actions |
| `Sources/WaterMark/UsageScanner.swift` | Transcript parsing + aggregation + cache |
| `Sources/WaterMark/WaterModel.swift` | Token → water conversion + persisted rate |
| `Info.plist` | Bundle metadata (`LSUIElement` = menu-bar only) |
| `build_app.sh` | Build script |

Requires macOS 13+ and a Swift toolchain (Xcode command-line tools).
