# WaterMark 💧

A macOS menu-bar app that estimates the water footprint of your Claude Code usage,
computed entirely from local transcripts. Nothing leaves your machine.

The bar shows your estimated water for the chosen window. Click the droplet for a
popover dashboard with everyday-water comparisons, a 30-day trend, a per-model
breakdown, editable coefficients, and a shareable card.

## Why

"AI is drinking the planet dry" is one of the loudest takes around. WaterMark
measures the real number from your own usage — with fair, sourced, comprehensive
figures — and puts it next to everyday things. Not to wave away AI's footprint,
just to keep it in proportion: a whole history of coding usually lands somewhere
around a single shower, and a rounding error next to a hamburger.

## Features

- **Dashboard popover** — pick Today / 7 days / 30 days / All time; a hero figure,
  token count, and a 30-day trend chart.
- **In perspective** — your water vs everyday items (bottle, shower, coffee,
  hamburger), each with a bar showing how much of one whole item it equals.
- **By model** — per-model water, each with its own editable energy coefficients.
- **Shareable card** — one click copies a clean image (with the repo link) to your
  clipboard.
- **Sources** — in-app citations and methodology so the estimate is auditable.

## How it works

- Reads `~/.claude/projects/**/*.jsonl` (the transcripts Claude Code already writes).
- Sums tokens per assistant turn, deduped by message id, bucketed by local day **and model**.
- **Tokens → energy → water**, per model, summed:
  - `energy = output × e_out + (input + cache_creation) × e_prefill` (Wh/1k). Decode
    costs far more per token than prefill; cache *reads* are excluded (free retrieval).
  - `water = energy × (WUE_onsite + WUE_source)`. **Comprehensive** scope adds the
    off-site grid-electricity term (~4.35 L/kWh) on top of on-site cooling (~0.30).
- Energy defaults are calibrated to public measurements (Google's median Gemini prompt
  ≈ 0.24 Wh; the "How Hungry is AI?" benchmark). Every coefficient is editable.
- Optionally adds your **amortised share of model training** (training ÷ MAU) as a
  separate one-time figure.
- The menu shows **Today / 7 / 30 days / All time**; pick which the bar reflects via
  *Show in menu bar*. Re-scans every 60s, only re-parsing changed files.

These are order-of-magnitude estimates, not measurements: Anthropic publishes no
per-token energy or water for Claude, and the dominant unknown is which region/grid
served your requests. See *Sources* in the app for citations.

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
unzip, and drag `WaterMark.app` to your Applications folder (`~/Applications`
works without admin rights).

Because it isn't notarized (no paid Apple Developer account), macOS blocks the
**first** launch. Clear it once, either way:

- **No Terminal:** double-click the app, dismiss the warning, then open
  **System Settings → Privacy & Security**, scroll down, and click
  **"Open Anyway"** next to WaterMark. (On macOS 15+ the old right-click → Open
  trick no longer bypasses this.)
- **Terminal:** clear the quarantine flag directly —

  ```bash
  xattr -dr com.apple.quarantine ~/Applications/WaterMark.app
  open ~/Applications/WaterMark.app
  ```

> The app **is** code-signed (ad-hoc), so it runs fine on Apple Silicon — these
> steps just clear the one-time "unidentified developer" prompt that
> un-notarized apps trigger. The `brew install` route avoids this entirely.

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
