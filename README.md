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

**Requirements**

- **Ollama** from [ollama.com](https://ollama.com). On macOS install it into
  `/Applications`, not `~/Applications` — otherwise a prompt blocks every start.
  Confirm the password prompt on first launch, it creates `/usr/local/bin/ollama`.
- **A Docker runtime**: [Colima](https://github.com/abiosoft/colima)
  (`brew install colima`), Docker Desktop or OrbStack.
- **16 GB RAM** for the small profile, 48 GB+ for the large models with long context.

**Install**

```bash
git clone https://github.com/reschosan/local-ai-setup.git
cd local-ai-setup
cp .env.example .env          # set WORKSPACE_DIR to the folder the chat may read
./setup.sh
```

Start your Docker runtime first — the script only checks that one is running. It then
checks Ollama, generates secrets, starts the containers and pulls the models that fit
your memory. It does not touch any editor or
system configuration in your home directory — the editor setup lives in your projects,
see below.

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

`<project>` is the folder you open in VS Code — Continue only looks for `.continue/` at
the root of each opened folder, not in subfolders or parent folders:

| Opened in VS Code | Copy `.continue/` into |
|---|---|
| a repository | the repository root |
| a parent folder holding several repositories | the parent folder; it covers everything below |
| a subfolder of a monorepo | that subfolder |
| a multi-root workspace (`.code-workspace`) | one of its folders; copies in several are harmless, models with the same name are merged |

A symlink to a shared `.continue/` works as well, if several projects should use the
same file.

This adds two blocks: `.continue/models/local-ai.yaml` with the models and context sizes,
and `.continue/context/local-ai.yaml` with `@codebase`, `@folder` and the other context
providers. Continue injects both into its config, so the config selector shows a single
entry and every model in it comes from the project. Pick model and context size in the
model selector. Commit `.continue/` so the whole team gets it, or add it to `.gitignore`.

Keep `~/.continue/config.yaml` at Continue's empty default and put nothing in it:

```yaml
name: Main Config
version: 1.0.0
schema: v1
models: []
```

Continue always lists this global config and recreates it when it is missing, so it can
only be kept empty, not removed. Do not use `.continue/agents/` either: every file there
shows up as an additional config.

To switch off telemetry for the project, add to `<project>/.vscode/settings.json`:

```json
{ "continue.telemetryEnabled": false }
```

### Cline

Everything Cline reads from the project stays in the project: `AGENTS.md`,
`.clinerules/` (rules, workflows, hooks) and skills in `.claude/skills/`,
`.agents/skills/`, `.cline/skills/` and `.clinerules/skills/`.

The one exception is provider and model: Cline has no project file for them (checked in
4.1.24) and keeps a single global configuration, so there is still only one to choose
from. Set it once in the Cline panel under **Settings → API Configuration**:

| Setting | Value |
|---|---|
| API Provider | `Ollama` |
| Base URL | leave empty (`http://localhost:11434`) |
| Model | `qwen3-coder:30b` or `qwen3.8:27b` |
| Model Context Window | `131072`, or `262144` for 256k — see [Context sizes](#context-sizes) |
| Request Timeout (ms) | `1800000` |

Enter the numbers without thousands separators: Cline passes the field to Ollama as it
is, and `131.072` becomes a context of 131 tokens. With **Use different models for Plan
and Act modes** switched on, set model and context for both modes.
The default timeout of 5 minutes is too short for local models: ingesting 70k tokens
takes 8 to 13 minutes on an M5 Pro, and Cline would abort the request.

Cline follows the VS Code telemetry setting: `"telemetry.telemetryLevel": "off"` in the
user settings switches it off.

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

A bigger window reserves its memory as soon as the model loads, and once it no longer
fits on the GPU even short prompts get slow. Filling 256k takes well over half an hour,
because attention grows quadratically. For large codebases use `@codebase` instead:
semantic search sends a few thousand relevant tokens rather than a hundred thousand
arbitrary ones.

The **Context length** slider in the Ollama app only applies to clients that send no
context size of their own, such as `ollama launch` or Ollama's own chat. Continue and
Cline always send one, Open WebUI the one `profile.sh` sets.

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

`nomic-embed-text` is always pulled for embeddings. The profile only decides which models
are downloaded and what the browser chat uses — in VS Code you choose in the model selector.
For a model outside the profiles: `ollama pull <name>` and add an entry to
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
`@terminal`. Cline always works with tools; it asks before every change unless you allow
auto-approve. Autocomplete comes from Continue — Cline has none.

In the browser the chat can also read your workspace under `/workspace`, analyse
dropped documents, and store system prompts as custom "models". Writing is technically
impossible there — that is what VS Code is for.

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

Outbound connections without content: Ollama checks for updates, models and images are
downloaded once, and the editors' telemetry unless switched off as described above.
Ollama also offers cloud models (tags ending in `:cloud`); those **do** send your prompts.
To block them, set `"disable_ollama_cloud": true` in `~/.ollama/server.json` and restart
Ollama.

---

## Commands

```bash
docker compose up -d / down / logs -f
docker compose pull && docker compose up -d   # update

ollama list / ps / stop <model>
```

The containers come back up via `restart: unless-stopped` once the Docker runtime runs.
With Colima, `brew services start colima` starts it at login.

**Upgrading from an older version of this repo:** it installed a LaunchAgent that set
`OLLAMA_HOST`, `OLLAMA_KV_CACHE_TYPE` and others. The Ollama app starts its server with
its own environment, so these never arrived — the server log shows them empty. It is no
longer needed. To remove it, and to reset the Continue config the scripts copied into
your home to the empty default:

```bash
launchctl bootout gui/$(id -u)/local.ollama.host
rm ~/Library/LaunchAgents/local.ollama.host.plist
for v in OLLAMA_HOST OLLAMA_KEEP_ALIVE OLLAMA_FLASH_ATTENTION OLLAMA_KV_CACHE_TYPE OLLAMA_MAX_LOADED_MODELS; do
  launchctl unsetenv "$v"
done
rm ~/.continue/config.yaml    # Continue recreates it empty; back it up first if you edited it
```

Older versions also named containers and volumes after the folder the repo was cloned
into. `setup.sh` replaces such containers and copies their chat data into the new
`lai-open-webui-data` volume once. The old volumes are kept as a backup; list them with
`docker volume ls` and remove them with `docker volume rm` when everything works.

---

## Troubleshooting

**No autocomplete** — check `ollama ps`. The first request after a start loads the model
and takes a few seconds.

**Chat finds no models** — check that the container reaches Ollama:

```bash
docker exec lai-open-webui python3 -c "import urllib.request; print(urllib.request.urlopen('http://host.docker.internal:11434/api/version').read())"
```

Colima, Docker Desktop and OrbStack forward this to the host's `127.0.0.1`. A runtime
that does not needs **Expose Ollama to the network** in the Ollama settings — that makes
Ollama reachable for the whole network, without a password.

**Running on the GPU?** — `ollama ps` must show `100% GPU`. Something like
`25%/75% CPU/GPU` means the context does not fit; pick a smaller one. On a fresh install,
`grep "inference compute" ~/.ollama/logs/server.log` must show `library=Metal`.

**Cline aborts with a timeout** — raise **Request Timeout** in the Cline settings, see
[Cline](#cline).

**"I don't have access to the files"** — true in Continue's chat mode; only **agent**
mode gives the model tools. Even then a 30B model sometimes skips the tool on "create
file X" — phrase it more directly.

**Raw JSON in the reply** like `{"name": "ask_user", ...}` — the model cannot do proper
tool calling. Verify the call lands in `message.tool_calls` rather than
`message.content`:

```bash
curl -s http://localhost:11434/api/chat -d '{"model":"MODEL","stream":false,
  "tools":[{"type":"function","function":{"name":"t","description":"x",
  "parameters":{"type":"object","properties":{}}}}],
  "messages":[{"role":"user","content":"call t"}]}' | python3 -m json.tool
```

**Machine feels slow** — `ollama stop <model>` unloads immediately.

---

## Files

| File | Purpose |
|---|---|
| `setup.sh` | first-time install, calls `profile.sh` |
| `profile.sh` | pull the models that fit the hardware, set browser chat defaults |
| `docker-compose.yml` | chat and file tool service |
| `workspace/.continue/` | Continue blocks for models with context sizes and for context providers; copy into a project |
| `.env.example` | template for `.env`, which is never committed |
