# AI Editor desktop app

The macOS app for the local editor. It's a Flutter window over the Python engine in this repository: the app starts `aie.server`, talks to it on loopback with a token from that launch, and the engine stops when the app closes.

## Running it

For using the app, run a release build. It still uses the engine in this checkout:

```bash
flutter run -d macos --release
```

Or build it and open the app:

```bash
flutter build macos --release
```

```bash
open build/macos/Build/Products/Release/aie_app.app
```

A debug build (`flutter run -d macos`) is only for working on the app. If a key's release goes to another app, for example because another app came to the front while the key was held, a debug build stops taking any typing. Its log repeats "A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed". Restart it, or use a release build, which doesn't run that check.

Close any running copy first. `open` only brings an old one forward.

Projects live in `/Volumes/1TB/AiEditorProjects/app`, or `~/AiEditorProjects` without that drive. Set `AIE_PROJECTS` to use another folder. The engine's log is `~/Library/Logs/AiEditor/engine.log`, which is the first place to look when something fails without a clear message.

The app's own settings are in `~/Library/Application Support/AiEditor/settings.json`. Each project's conversation and memory are in that project's `project.sqlite`.

Geist and Geist Mono are in `assets/fonts` with their license, `OFL.txt`. Phosphor Icons come with `phosphor_flutter`, and Settings lists every license.

macOS asks once for access to a removable drive, and sometimes again after a rebuild. Choose Allow.

## Pages

| Page | What it's for |
|---|---|
| Projects | Create or open a project, and see its media, proxy, manifest and anything missing or out of date |
| Footage | Add the clip, from a file, a folder, Resolve or EffectCraft, read what analysis found, and send clips out |
| Style | Measure a reference, keep measured apart from interpreted, and edit what the title uses |
| Review | Instruction to plan, cheap preview, title stills, timestamped notes, flagged sentences, approval |
| Resolve | What this install can do, the run's steps, cancel and resume, read-back, final render |
| Assistant | This project's own AI: chat, edits by request on any clip, style questions, memory and its choice of model |
| Activity | Revision history, assets and versions, model metrics, the action log |
| Connections | Whether Resolve, EffectCraft, the model and speech-to-text are reachable |
| Settings | The default AI model, what's installed, and your account on this Mac |

## Tests

```bash
flutter test
```

`test/live` drives these same pages against the real engine and every real tool, and saves a picture of each page. It needs Resolve open with the bridge started, and it makes one scratch project in Resolve:

```bash
AIE_LIVE=1 FLUTTER_ROOT=/opt/homebrew/share/flutter AIE_CLIP=/path/clip.mp4 AIE_REFERENCE=/path/look.png AIE_PROJECTS=/tmp/aie-projects AIE_SHOTS=/tmp/aie-shots flutter test test/live
```

Add `--plain-name "each project has its own AI"` to run only the assistant test, which needs Ollama but not Resolve.

Create the `AIE_SHOTS` folder first. Video can't play in that harness, so playback and the native file pickers are only checked in the real window.
