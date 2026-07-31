# OpenCluely — Agent Notes

Invisible AI interview copilot. Electron desktop app. Overlay windows stay out of
screen-share/recording capture; user asks by voice or screenshot, Gemini answers,
response streams into overlay/chat.

## Tech Stack

- **Runtime**: Node.js, Electron 29 (CommonJS, not ESM)
- **AI**: Google Gemini via `@google/genai` — only provider wired up, hardcoded in `src/services/llm.service.js`
- **Speech**: Local Whisper (Python CLI, via `.venv-whisper`) or Azure Speech — optional, picked via `SPEECH_PROVIDER`
- **UI**: Plain HTML/CSS/JS windows (no framework) — `index.html`, `chat.html`, `llm-response.html`, `onboarding.html`, `settings.html`
- **Styling**: Tailwind CSS (`tailwind.config.js`, `src/input.css`) + `src/styles/common.css`
- **Packaging**: electron-builder (`npm run build:win|mac|linux`)
- **Logging**: winston + winston-daily-rotate-file (`src/core/logger.js`)

## Run / Build

```bash
npm install
npm start          # env -u ELECTRON_RUN_AS_NODE electron .   (bash syntax — breaks in native PowerShell)
npm run dev         # same + --no-sandbox --disable-gpu
npx electron . --no-sandbox --disable-gpu   # PowerShell-safe equivalent of dev
```

- `npm start`/`npm run dev` scripts use `env -u ...`, which is bash-only. On Windows, run via Git Bash/WSL, or use the `npx electron .` form directly in PowerShell.
- `./setup.sh` (Git Bash/WSL/macOS/Linux) does full first-time setup: deps, `.env`, Whisper venv, launch.
- `npm run build` / `build:win` / `build:mac` / `build:linux` → electron-builder, output in `dist/`.

## Project Structure

```
main.js                    # Electron main process entry — window lifecycle, IPC, .env persistence, stealth app-name/icon swap
preload.js                 # contextBridge IPC surface exposed to renderer windows
index.html / chat.html / llm-response.html / onboarding.html / settings.html   # renderer windows (plain JS, no bundler)
speech-recognition.js       # renderer-side mic capture glue
prompt-loader.js            # loads prompt templates from prompts/
src/
  core/
    config.js               # reads/merges config + env vars
    first-run.js             # onboarding/first-run detection (checks .env, sentinel file)
    logger.js                 # winston logger factory (createServiceLogger)
    whisper-installer.js       # bootstraps local Whisper venv
  managers/
    session.manager.js        # conversation/session memory
    window.manager.js          # creates/shows/hides/broadcasts to the 4 windows (main, chat, llmResponse, settings)
  services/
    llm.service.js            # Gemini client — init, generation config, streaming
    capture.service.js        # screenshot capture (primary)
    fallback-capture.service.js
    speech.service.js         # dispatches to whisper or azure
    whisper-worker.service.js  # spawns/talks to local whisper_worker.py
  ui/                         # renderer-side controllers per window
scripts/
  whisper_worker.py           # long-lived Python worker process for local transcription
  test-speech.js
prompts/                      # prompt templates (per skill/language), asar-unpacked in build
assests/icons/                # app icons — note the misspelling "assests" is intentional/existing, not a typo to fix
```

## Key Conventions

- **CommonJS**, not ESM — `require`/`module.exports` throughout, no `"type": "module"` in package.json.
- **No renderer framework/bundler** — windows are hand-written HTML + vanilla JS, loaded directly by Electron.
- **`chat.html` has its own inline `<script>` implementation** — it does **not** load `src/ui/chat-window.js`. That file looks like the chat window's controller but is dead code, never included by any `<script src>`. **Always edit the inline script in `chat.html` directly for chat-window behavior changes**; editing `chat-window.js` alone does nothing.
- **IPC**: `preload.js` bridges main ↔ renderer via `contextBridge`/`ipcRenderer`; broadcasts fan out to all 4 windows (`window.manager.js`), each renderer filters by `isVisible`/relevance.
- **Recording state must be driven by the dedicated `onRecordingStarted`/`onRecordingStopped` IPC events, never by matching substrings in the human-readable `onSpeechStatus` text.** The final status string is literally `"Recording stopped"`, which contains the substring `"Recording"` — a naive `status.includes('Recording') → treat as started` check false-triggers on it and desyncs the mic button after one cycle. `main-window.js` always used the dedicated events (worked); `chat.html`'s inline script used to also toggle state off the status text and got clobbered — fixed by removing state-toggling from the status listener there.
- **`.env` resolution** (`main.js`, top of file): prefers project-root `.env` in dev *only if it already exists*; otherwise resolves to `app.getPath("userData")/.env` (e.g. `%APPDATA%\opencluely\.env` on Windows) so packaged builds always have a writable location. **Check the userData path, not just the repo root, when debugging config/env issues** — the app may be reading/writing there instead.
- **Settings persistence**: Settings window writes back into that resolved `.env` at runtime (`Persisted .env updates` log line) — no restart needed for most keys.
- **Stealth mode**: app renames itself (window title, process name, icon) on startup to blend in — see `[MAIN] App name updated for stealth mode` in logs; this is intentional product behavior, not a bug.
- **Logging**: use `logger.createServiceLogger('NAME')` per module; logs go to console + rotating files. Prefer this over `console.log`.
- **LLM provider is single-vendor**: `src/services/llm.service.js` only supports Gemini (`GoogleGenAI` from `@google/genai`). Adding another provider (e.g. Claude) means adding a new client + provider-switch logic here, not swapping a config flag.
- **Cursor is forced to default everywhere** (`*, *:hover { cursor: default !important; }` in `src/styles/common.css`, plus inline in `llm-response.html`/`onboarding.html` since they don't load `common.css`) — no hand/pointer cursor on any clickable element, per product preference. This also removes the text-beam cursor in inputs/textareas; that's a known trade-off, not an oversight.
- **Chat answer scroll behavior** (`chat.html`): a new assistant message scrolls its own top into view (`scrollIntoView({block:'start'})`), not the chat container's bottom. This is deliberate — snapping to the absolute bottom on a long answer used to force the user to scroll back up to read it from the start. Only the *first* appended piece of a rendered response scrolls (`addMessage`/`addCodeSnippet` take a `scroll` param) — code blocks appended after the text must not re-scroll past the text's top.

## Skill / Prompt System

- Prompts live in `prompts/*.md`, loaded by `prompt-loader.js`. Currently three: `dsa.md` (strict single-language code-only DSA solver), `programming.md` (adaptive — conceptual/coding/system-design/debugging/internals/framework-specific questions across the full stack), and `business-ai.md` (AI-for-business curriculum — prompt engineering, ethics, business writing, Excel/PowerPoint/Canva/Copilot, marketing/HR/finance/ops AI, automation/agents, case studies/capstone).
- Default active skill is `"programming"` (was hardcoded to `"dsa"` in `main.js`, `session.manager.js`, `main-window.js` — changed in all three; keep them in sync if adding a new default).
- Skill selection surfaces read from `availableSkills`/`getAvailableSkills()` in **two separate places that must both stay in sync**, since it's easy to fix one and miss the other:
  - Dynamic (auto-picks up new `.md` files, no code change needed): `prompt-loader.js`'s `getAvailableSkills()` (returns whatever's actually loaded), and `main.js`'s `navigateSkill()` (the main-process-authoritative skill-cycle, e.g. tied to a global shortcut) — this one used to be hardcoded to `["dsa"]` even after the default skill changed to `"programming"`, silently breaking the cycle (index -1, early return) until fixed to call `promptLoader.getAvailableSkills()`.
  - Manual (needs a new line added per skill): `settings.html`'s `#activeSkill` `<select>` (plain hardcoded `<option>`s, not populated from JS), `main-window.js`'s own `this.availableSkills` array (renderer-side click-cycle for the skill badge, separate from main.js's copy), the `skillNames` label map in `main-window.js` (appears 3x, same object literal — used for display text on the badge/response), and `prompt-loader.js`'s `normalizeSkillName()` `skillMap` (name aliases, e.g. `'coding' → 'programming'`).
- The coding-language dropdowns (`index.html`, `settings.html`) list the language sent to Gemini for `dsa`'s strict "output ONLY in this language" lock; `prompt-loader.js`'s `injectProgrammingLanguage()` has a `languageMap`/`fenceTagMap` per language for correct casing/fence tags — add new entries there when adding dropdown options, or it falls back to a naive capitalize (wrong for e.g. `C#`).

## Local Whisper / GPU

- `.venv-whisper`'s `torch` installs as a **CPU-only build by default** (`pip install openai-whisper` pulls plain `torch`), even when an NVIDIA GPU is present — silently slow, no error. Fix: `pip install --force-reinstall --no-cache-dir torch --index-url https://download.pytorch.org/whl/cu124` (or matching CUDA version) inside the venv. Verify with `python -c "import torch; print(torch.cuda.is_available())"`.
- The first Whisper inference after a (re)load pays a one-time CUDA kernel/cudnn JIT-compile cost (~15-30s even on GPU) that plain model-loading doesn't trigger. `speech.service.js` now runs a dummy `warmup()` (which itself runs a silent-audio `transcribe()` in `whisper_worker.py`) right at app startup, before the user's first real question, so that cost doesn't land on them.
- `WHISPER_DEVICE=auto` in `.env` resolves to `cuda` automatically once `torch.cuda.is_available()` is `True` — no explicit device config needed once CUDA torch is installed.
- **`WHISPER_GPU_IDLE_MS` (idle-unload timer) is the single biggest real-world latency lever** — default was 60s, which in practice means the model unloads between almost every question (natural gaps in conversation), so nearly every question repays the ~15-25s CUDA reload/JIT-compile cost. Default raised to 30 min (`1800000`) in both `speech.service.js`'s fallback and `env.example`. If "listening feels slow" is reported and per-call `processingTime` in the logs is already low (1-5s), suspect this setting or a recent unload before jumping to model/GPU theories — check for `"Whisper model unloaded after idle timeout"` log lines right before the slow call.
- **VAD end-of-question timing** (`_ingestWhisperAudio` in `speech.service.js`): `WHISPER_SILENCE_HANGOVER_MS` (default 700ms in code, currently overridden to `2000` in this user's `.env`) controls how long a pause must last before the question is considered finished and sent to the LLM. Too short (700ms) cuts off long/situational questions on natural mid-sentence pauses; too long (5000ms, tried and reverted) makes every short question feel sluggish. `WHISPER_MAX_UTTERANCE_MS` (default 15000, raised to `120000` here) is a hard cap regardless of pauses — also needs raising for long questions or it force-flushes mid-sentence.
- **Local Whisper has no interim/partial transcription built in** — unlike the Azure path (which streams `interim-transcription` natively from its continuous recognizer), Whisper only produces text once a segment is flushed. Added a periodic (`WHISPER_INTERIM_INTERVAL_MS`, default 2500ms) non-destructive preview: while `vadSpeaking` is true, `_emitInterimPreview()` transcribes a *copy* of the buffer accumulated so far (without touching the buffer the final flush owns) and emits `interim-transcription`, so the UI's live-preview overlay (already wired in `chat.html` via `showInterimText`) works for local Whisper too, not just Azure.

## UI / Window Positioning

- **Floating bar dragging**: the main command-tab bar drags via native OS `-webkit-app-region: drag` (works fine) — but `window.manager.js`'s `positionBoundWindows()` used to hardcode a fixed top-center position and re-run it on every LLM loading-state/response/resize (i.e. on every question), snapping the bar back regardless of where the user dragged it. Fixed: it now reads `mainWindow.getPosition()` and treats that as the anchor (falling back to top-center only if the position looks like the off-screen screen-share-hide parking spot, `< -5000`). The `move-bound-windows` IPC handler / `moveBoundWindows()` exists for programmatic nudging (arrow-key shortcuts) but no renderer code ever drives it for mouse drags — don't assume it's the drag mechanism.
- Image/screenshot instruction sent alongside the captured PNG lives in `llm.service.js`'s `formatImageInstruction()` — kept skill-agnostic (tells Gemini to locate the actual question among surrounding UI and match answer format to question type) rather than hardcoding `"for a {SKILL} question"` / forcing code output, since the active skill is no longer always DSA.

## Windows-Specific Gotchas

- `env -u` in npm scripts is bash syntax — fails in native PowerShell/cmd. Use Git Bash, WSL, or call `electron .` directly.
- `DXGI` capture errors (`IDXGIDuplicateOutput does not use RGBA...`) in logs during screen-share-hide polling are benign/cosmetic on some Windows/GPU combos — not a functional failure unless capture actually stops working.
- Killing the app: `npm start` run inside an agent/VSCode-integrated shell dies when that shell's parent (e.g. VSCode) closes. For a persistent run, launch from a standalone terminal, or use a detached launcher — see `start-opencluely.vbs`.
- **`start-opencluely.vbs`** (repo root) is a detached launcher a desktop shortcut can point at: `objShell.Run "cmd /c npx electron .", 0, False` — runs hidden (no console window), survives the parent terminal/VSCode closing. Originally had `--no-sandbox --disable-gpu`; **removed** — `--disable-gpu` forces software rendering and made the whole UI noticeably more sluggish than a plain `npm start`, and neither flag was actually needed for normal operation. Since it always runs `npx electron .` against the current source tree (not a packaged build), it needs no updates when app code changes — only touch it if the launch *command itself* needs to change.

## Environment

- `GEMINI_API_KEY` — required. Real Gemini keys start `AIza...`; anything else (e.g. an OAuth/session-token-shaped string) will likely fail auth even if "configured" per first-run checks.
- `SPEECH_PROVIDER` — `whisper` or `azure`, optional (mic UI hides if unset).
- `AZURE_SPEECH_KEY` / `AZURE_SPEECH_REGION` — required if `SPEECH_PROVIDER=azure`.
- `WHISPER_COMMAND` / `WHISPER_MODEL` / `WHISPER_LANGUAGE` / `WHISPER_MODEL_DIR` — local Whisper config, if `SPEECH_PROVIDER=whisper`.
- Full `.env` template: `env.example`.
