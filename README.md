# local-ai-setup

A local AI dev setup: chat in the browser, Copilot replacement in VS Code.
Free, offline, nothing leaves your machine.

```
  VS Code + Continue ──┐
  VS Code + Cline ─────┼──>  Ollama   native on the host, 127.0.0.1:11434, Metal GPU
  Browser :3000 ───────┘
   (Open WebUI)
        │
        └──>  mcp-files   reads the workspace, no port exposed
```

Ollama does **not** run in Docker: Docker Desktop on macOS has no access to the Metal
GPU, so a containerised Ollama would be 10-20x slower.

---

## Setup

Needs [Ollama](https://ollama.com) — on macOS in `/Applications`, not `~/Applications`,
or a prompt blocks every start; confirm the password prompt on first launch, it creates
`/usr/local/bin/ollama`. Plus a Docker runtime ([Colima](https://github.com/abiosoft/colima)
via `brew install colima`, Docker Desktop or OrbStack) and 16 GB RAM, 48 GB+ for the
large models with long context.

```bash
git clone https://github.com/reschosan/local-ai-setup.git
cd local-ai-setup
cp .env.example .env          # set WORKSPACE_DIR to the folder the chat may read
./setup.sh
```

Start your Docker runtime first — the script only checks that one is running. It then
checks Ollama, generates secrets, starts the containers and pulls the models that fit
your memory. It touches no editor or system configuration in your home directory; the
editor setup lives in your projects, see below.

**Windows:** run the scripts in Git Bash, with Ollama for Windows and Docker Desktop
running. Start Ollama yourself first — the script only starts it on macOS. Set
`WORKSPACE_DIR` as `C:/Users/<you>/projects`, with forward slashes. Ollama runs natively
on the GPU there as well; the Metal check is skipped.

Then open http://localhost:3000 — the first account becomes admin. After registering,
set `ENABLE_SIGNUP=False` in `.env` and run `docker compose up -d` again.

---

## Editor setup: workspace only

Continue and Cline are configured per project, not in the home directory, and there is
exactly **one** config to choose from: the workspace's.

### Continue

Copy the workspace config into the project:

```bash
cp -R /path/to/local-ai-setup/workspace/.continue <project>/
```

Continue only looks for `.continue/` at the root of each folder you open, not in
subfolders or parent folders:

| Opened in VS Code | Copy `.continue/` into |
|---|---|
| a repository | the repository root |
| a parent folder holding several repositories | the parent folder; it covers everything below |
| a subfolder of a monorepo | that subfolder |
| a multi-root workspace (`.code-workspace`) | one of its folders; copies in several are harmless, models with the same name are merged |

A symlink to a shared `.continue/` works too. It adds two blocks —
`.continue/models/local-ai.yaml` (models and context sizes) and
`.continue/context/local-ai.yaml` (`@codebase`, `@folder` and the other providers) —
which Continue injects into its config, so the selector shows one entry and every model
in it comes from the project. Commit `.continue/` for the team, or ignore it.

Keep `~/.continue/config.yaml` at Continue's empty default (`models: []`) and put nothing
in it — Continue always lists this global config and recreates it when missing, so it can
only be kept empty, not removed. Avoid `.continue/agents/` as well: every file there shows
up as an additional config.

Telemetry off per project, in `<project>/.vscode/settings.json`:
`{ "continue.telemetryEnabled": false }`

### Cline

Everything Cline reads from the project stays in the project: `AGENTS.md`,
`.clinerules/` (rules, workflows, hooks) and skills in `.claude/skills/`,
`.agents/skills/`, `.cline/skills/` and `.clinerules/skills/`.

Provider and model are the exception — Cline has no project file for them (as of 4.1.24),
only one global setting. Set it once under **Settings → API Configuration**:

| Setting | Value |
|---|---|
| API Provider | `Ollama` |
| Base URL | leave empty (`http://localhost:11434`) |
| Model | `qwen3-coder:30b` or `qwen3.8:27b` |
| Model Context Window | `131072`, or `262144` for 256k — see [Context sizes](#context-sizes) |
| Request Timeout (ms) | `1800000` |

No thousands separators — Cline passes the field to Ollama verbatim, and `131.072`
becomes a context of 131 tokens. With **Use different models for Plan and Act modes** on,
set both. The 5-minute default timeout is too short: ingesting 70k tokens takes 8 to 13
minutes on an M5 Pro, and Cline would abort.

Telemetry follows VS Code: `"telemetry.telemetryLevel": "off"` in the user settings.

---

## Other clients

Ollama ships launchers that point a client at your local models:

```bash
ollama launch              # interactive menu
ollama launch claude       # Claude Code
ollama launch vscode       # VS Code
ollama launch cline        # Cline
```

`ollama launch --help` lists the rest (`copilot`, `opencode`, `codex`, `qwen`, `droid`,
`kimi` and more). The model chosen per integration lands in `~/.ollama/config.json`.

**Claude Code** on local models: `ollama launch claude` routes it through a local proxy,
so no requests reach Anthropic. Caps cost on routine work while keeping the interface.

**VS Code without Continue or Cline** runs through the GitHub Copilot Chat extension,
which `ollama launch vscode` expects to be installed; it prints a hint if it is missing.
The models then appear in Copilot Chat's model picker under *Other models*. Two caveats:
the extension needs a GitHub account, and it covers chat only — autocomplete,
`@codebase` embeddings, skills and `AGENTS.md` stay with Continue and Cline.

Unlike Continue and Cline, these clients send no context size of their own, so the
**Context length** slider in the Ollama app applies to them.

---

## Context sizes

Measured on an M5 Pro with 48 GB, where macOS gives the GPU at most 37.4 GiB:

| Model | Context | Memory | Fully on the GPU | Prompt ingest |
|---|---|---|---|---|
| `qwen2.5-coder:7b` | 8k | 4.8 GiB | yes | ~1,300 tokens/s |
| `qwen3-coder:30b` | 32k | 20.3 GiB | yes | 29k tokens in 80 s |
| `qwen3-coder:30b` | 64k | 23.4 GiB | yes | 45k tokens in 191 s |
| `qwen3-coder:30b` | 128k | 29.5 GiB | yes | 71k tokens in 474 s |
| `qwen3-coder:30b` | 256k | 41.9 GiB | **no** | 6k tokens in 113 s — 15-20x slower |
| `qwen3.8:27b` | 128k | 24.4 GiB | yes | 43k tokens in 200 s |
| `qwen3.8:27b` | 256k | 33.1 GiB | yes | 73k tokens in 805 s |

- **48 GB**: `Qwen3 Coder 30B · 128k` as the default. For 256k use `Qwen 3.8 27B · 256k`:
  only 16 of its layers keep a KV cache, so 256k costs 17 GiB instead of 24 GiB.
- **`Qwen3 Coder 30B · 256k`** needs 64 GB+. With less, part of the model runs on the CPU.
- **32 GB**: `Qwen3 Coder 30B · 32k`. **16 GB**: `Qwen2.5 Coder 7B · 16k`.

A bigger window reserves its memory the moment the model loads, and once it no longer
fits on the GPU even short prompts get slow. Attention grows quadratically, so filling
256k takes well over half an hour. For large codebases use `@codebase` instead: semantic
search sends a few thousand relevant tokens rather than a hundred thousand arbitrary
ones.

The **Context length** slider in the Ollama app does not apply here: Continue and Cline
always send a context size, Open WebUI the one `profile.sh` sets. It only affects the
clients under [Other clients](#other-clients).

---

## Profiles

```bash
./profile.sh          # suggests one based on your RAM
./profile.sh large    # apply directly
```

| Profile | Models pulled | Browser chat | RAM |
|---|---|---|---|
| `small` | `qwen2.5-coder:7b` | 7B, 16k | 16 GB+ |
| `medium` | + `qwen3-coder:30b` | 30B, 32k | 32 GB+ |
| `large` | + `qwen3-coder:30b`, `qwen3.8:27b` | 30B, 64k | 48 GB+ |

`nomic-embed-text` is always pulled for embeddings. The profile only decides what gets
downloaded and what the browser chat uses; in VS Code you pick in the model selector. For
a model outside the profiles: `ollama pull <name>`, then add an entry to
`.continue/models/local-ai.yaml` in your project.

---

## Usage

| Key | Action |
|---|---|
| `Tab` | accept autocomplete |
| `⌘I` | rewrite the selection |
| `⌘L` | send selection to chat |
| `⌘⇧Enter` | accept diff |

In Continue, switch the chat panel from `Chat` to **`Agent`** so the model may read and
edit files. Context via `@`: `@codebase`, `@file`, `@folder`, `@diff`, `@problems`,
`@terminal`. Cline always works with tools and asks before every change unless you allow
auto-approve. Autocomplete comes from Continue — Cline has none.

In the browser the chat reads your workspace under `/workspace`, analyses dropped
documents and stores system prompts as custom "models". Writing is impossible there — the
mount is read-only.

---

## Rules and skills

**`AGENTS.md`** in the project root is read by Continue, Cline and Codex; it is the
equivalent of `CLAUDE.md`. Note that Continue lists `["AGENTS.md", "AGENT.md", "CLAUDE.md"]`
but breaks after the first entry, so **only `AGENTS.md` works** (as of 2.0.0). It is only
looked for in the root, and with several folders open only the first one's file applies.

More rules per project: `.continue/rules/*.md` for Continue, `.clinerules/` for Cline.
Continue's frontmatter controls loading: `alwaysApply: true`, `globs: "src/**"`,
`description: ...` (model decides) or `invokable: true` (via `@name`).

**Skills** in Claude's format work unchanged — same frontmatter, loaded on demand. Put
them in `<project>/.claude/skills/<name>/SKILL.md`: Claude Code, Continue and Cline all
read that folder. Measured with Continue, 10 skills and 11 questions: 10/11 routed
correctly, all descriptions together cost about 850 tokens.

---

## Privacy

Prompts, code and chats stay on the machine. Inference is local, Ollama listens on
`127.0.0.1` only, Open WebUI binds to `127.0.0.1:3000` and talks to nothing but Ollama,
`ENABLE_OPENAI_API` is off, embeddings run on local `nomic-embed-text`, and the file
service has no port at all.

Outbound connections without content: Ollama's update check, the one-time model and
image downloads, and the editors' telemetry unless switched off as described above.
Ollama also offers cloud models (tags ending in `:cloud`) — those **do** send your
prompts. Block them with `"disable_ollama_cloud": true` in `~/.ollama/server.json`,
then restart Ollama.

---

## Commands

```bash
docker compose up -d / down / logs -f
docker compose pull && docker compose up -d   # update

ollama list            # installed models
ollama ps              # loaded now, with context size and GPU share
ollama pull <name>     # download
ollama rm <name>       # delete
ollama stop <name>     # unload from memory
ollama show <name>     # parameters, context length, template
ollama run <name>      # quick test in the terminal
```

The containers come back up via `restart: unless-stopped` once the Docker runtime runs.
With Colima, `brew services start colima` starts it at login.

## Troubleshooting

**No autocomplete** — check `ollama ps`. The first request after a start loads the model
and takes a few seconds.

**Chat finds no models** — check that the container reaches Ollama:

```bash
docker exec lai-open-webui python3 -c "import urllib.request; print(urllib.request.urlopen('http://host.docker.internal:11434/api/version').read())"
```

Colima, Docker Desktop and OrbStack forward this to the host's `127.0.0.1`. A runtime
that does not needs **Expose Ollama to the network** in the Ollama settings, which opens
Ollama to the whole network without a password.

**Running on the GPU?** — `ollama ps` must show `100% GPU`. Something like
`25%/75% CPU/GPU` means the context does not fit; pick a smaller one. On a fresh install,
`grep "inference compute" ~/.ollama/logs/server.log` must show `library=Metal`.

**Cline aborts with a timeout** — raise **Request Timeout** in the Cline settings, see
[Cline](#cline).

**"I don't have access to the files"** — true in Continue's chat mode; only **agent**
mode gives the model tools. Even there a 30B model sometimes skips the tool on "create
file X"; phrase it more directly.

**Tool calls fail** — `Tool edit_file not found`, `arguments were invalid`, or raw
`{"name": ...}` in the reply. The model emits its call in a format Ollama does not parse,
so it lands in `message.content` instead of `message.tool_calls`. Test a model with two
required arguments — one is not enough to reproduce it:

```bash
curl -s http://localhost:11434/api/chat -d '{"model":"MODEL","stream":false,
  "tools":[{"type":"function","function":{"name":"t","description":"x",
  "parameters":{"type":"object","required":["a","b"],
  "properties":{"a":{"type":"string"},"b":{"type":"string"}}}}}],
  "messages":[{"role":"user","content":"call t with a=1 and b=2"}]}' | python3 -m json.tool
```

The call must appear under `message.tool_calls` **with both arguments**. If
`<function=...>` turns up in `message.content`, that model cannot drive an agent.
Measured: `qwen3-coder:30b` fails whenever an argument spans several lines — 4 of 10
attempts succeeded — and a file edit passes exactly that, so ask it for small, targeted
replacements. `qwen2.5-coder:32b` never produces a valid call.

**Machine feels slow** — `ollama stop <model>` unloads immediately.

---

## Upgrading from an older version

Skip this on a fresh install.

Older versions installed a LaunchAgent for `OLLAMA_HOST`, `OLLAMA_KV_CACHE_TYPE` and
others. The Ollama app starts its server with its own environment, so these never
arrived — the server log shows them empty. Remove it, and reset the Continue config the
scripts copied into your home:

```bash
launchctl bootout gui/$(id -u)/local.ollama.host
rm ~/Library/LaunchAgents/local.ollama.host.plist
for v in OLLAMA_HOST OLLAMA_KEEP_ALIVE OLLAMA_FLASH_ATTENTION OLLAMA_KV_CACHE_TYPE OLLAMA_MAX_LOADED_MODELS; do
  launchctl unsetenv "$v"
done
rm ~/.continue/config.yaml    # Continue recreates it empty; back it up first if you edited it
```

They also named containers and volumes after the folder the repo was cloned into.
`setup.sh` replaces such containers and copies their chat data into the new
`lai-open-webui-data` volume once, keeping the old volumes as a backup — list them with
`docker volume ls`, remove them with `docker volume rm` once everything works.

---

## Files

| File | Purpose |
|---|---|
| `setup.sh` | first-time install, calls `profile.sh` |
| `profile.sh` | pull the models that fit the hardware, set browser chat defaults |
| `docker-compose.yml` | chat and file tool service |
| `workspace/.continue/` | Continue blocks for models with context sizes and for context providers; copy into a project |
| `.env.example` | template for `.env`, which is never committed |
