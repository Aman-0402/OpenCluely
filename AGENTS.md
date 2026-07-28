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

- Prompts live in `prompts/*.md`, loaded by `prompt-loader.js`. Currently two: `dsa.md` (strict single-language code-only DSA solver) and `programming.md` (adaptive — conceptual/coding/system-design/debugging/internals/framework-specific questions across the full stack, not just algorithms).
- Default active skill is `"programming"` (was hardcoded to `"dsa"` in `main.js`, `session.manager.js`, `main-window.js` — changed in all three; keep them in sync if adding a new default).
- The skill picker (`settings.html` `#activeSkill` dropdown) and the skill-badge click-cycle (`main-window.js` `navigateSkill()`, wired to the badge's click handler) both read from `availableSkills`/`getAvailableSkills()` — when adding a new skill `.md` file, no other code changes are needed, both surfaces pick it up automatically.
- The coding-language dropdowns (`index.html`, `settings.html`) list the language sent to Gemini for `dsa`'s strict "output ONLY in this language" lock; `prompt-loader.js`'s `injectProgrammingLanguage()` has a `languageMap`/`fenceTagMap` per language for correct casing/fence tags — add new entries there when adding dropdown options, or it falls back to a naive capitalize (wrong for e.g. `C#`).

## Local Whisper / GPU

- `.venv-whisper`'s `torch` installs as a **CPU-only build by default** (`pip install openai-whisper` pulls plain `torch`), even when an NVIDIA GPU is present — silently slow, no error. Fix: `pip install --force-reinstall --no-cache-dir torch --index-url https://download.pytorch.org/whl/cu124` (or matching CUDA version) inside the venv. Verify with `python -c "import torch; print(torch.cuda.is_available())"`.
- The first Whisper inference after a (re)load pays a one-time CUDA kernel/cudnn JIT-compile cost (~15-30s even on GPU) that plain model-loading doesn't trigger. `speech.service.js` now runs a dummy `warmup()` (which itself runs a silent-audio `transcribe()` in `whisper_worker.py`) right at app startup, before the user's first real question, so that cost doesn't land on them.
- `WHISPER_DEVICE=auto` in `.env` resolves to `cuda` automatically once `torch.cuda.is_available()` is `True` — no explicit device config needed once CUDA torch is installed.

## Windows-Specific Gotchas

- `env -u` in npm scripts is bash syntax — fails in native PowerShell/cmd. Use Git Bash, WSL, or call `electron .` directly.
- `DXGI` capture errors (`IDXGIDuplicateOutput does not use RGBA...`) in logs during screen-share-hide polling are benign/cosmetic on some Windows/GPU combos — not a functional failure unless capture actually stops working.
- Killing the app: `npm start` run inside an agent/VSCode-integrated shell dies when that shell's parent (e.g. VSCode) closes. For a persistent run, launch from a standalone terminal, or use a detached launcher (e.g. a `.vbs` wrapping `cmd /c npx electron . --no-sandbox --disable-gpu` via `WScript.Shell.Run(..., 0, False)`).

## Environment

- `GEMINI_API_KEY` — required. Real Gemini keys start `AIza...`; anything else (e.g. an OAuth/session-token-shaped string) will likely fail auth even if "configured" per first-run checks.
- `SPEECH_PROVIDER` — `whisper` or `azure`, optional (mic UI hides if unset).
- `AZURE_SPEECH_KEY` / `AZURE_SPEECH_REGION` — required if `SPEECH_PROVIDER=azure`.
- `WHISPER_COMMAND` / `WHISPER_MODEL` / `WHISPER_LANGUAGE` / `WHISPER_MODEL_DIR` — local Whisper config, if `SPEECH_PROVIDER=whisper`.
- Full `.env` template: `env.example`.
