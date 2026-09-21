# local-ai-infrastructure

A local AI dev setup: chat in the browser, Copilot replacement in VS Code.
Free, offline, nothing leaves your machine.

```
  VS Code + Continue ──┐
                       ├──>  Ollama   native on the host, port 11434, Metal GPU
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
- **16 GB RAM** for the small profile, 32 GB+ for the large model.

**Install**

```bash
git clone <repo-url> local-ai-infrastructure
cd local-ai-infrastructure
cp .env.example .env          # set WORKSPACE_DIR to the folder the chat may read
./setup.sh
```

The script does the rest: generate secrets, set up Ollama as a service, pick a profile
matching your memory, pull models, start the containers and install the Continue config
into `~/.continue/config.yaml`.

If `~/.continue/config.yaml` already exists and differs from this repo's version, it is
**never overwritten**. The script prints a `diff` and a `cp` line so you can merge or
replace it yourself. Nothing else in `~/.continue` is touched either.

Then open http://localhost:3000 — the first account becomes admin — and install the
`Continue.continue` extension in VS Code. After registering, set `ENABLE_SIGNUP=False`
in `.env` and run `docker compose up -d` again.

---

## Profiles

```bash
./profile.sh          # suggests one based on your RAM
./profile.sh small    # apply directly
```

| Profile | Chat & agent | Context | Autocomplete | RAM |
|---|---|---|---|---|
| `small` | `qwen2.5-coder:7b` | 16k | `qwen2.5-coder:1.5b` | 16 GB+ |
| `medium` | `qwen3-coder:30b` | 32k | `qwen2.5-coder:7b` | 32 GB+ |
| `large` | `qwen3-coder:30b` | 64k | `qwen2.5-coder:7b` | 48 GB+ |

Pulls missing models and updates `continue.config.yaml`. It is copied to
`~/.continue/config.yaml` — the file Continue actually reads — only if that file is
missing or was installed by this repo. A config of your own is left alone, and the
script tells you how to merge it. Reload VS Code afterwards.

For a model outside the profiles: `ollama pull <name>`, then edit
`~/.continue/config.yaml` directly.

**Why not more context?** Memory would allow 256k, compute does not — attention grows
quadratically. Measured on an M5 Pro: 10k tokens take 12 s to ingest, 49k take 203 s,
103k take 961 s. For large codebases use `@codebase` instead: semantic search sends a
few thousand relevant tokens rather than a hundred thousand arbitrary ones.

---

## Usage

| Key | Action |
|---|---|
| `Tab` | accept autocomplete |
| `⌘I` | rewrite the selection |
| `⌘L` | send selection to chat |
| `⌘⇧Enter` | accept diff |

Switch the chat panel from `Chat` to **`Agent`** so the model may read and edit files.
Context via `@`: `@codebase`, `@file`, `@folder`, `@diff`, `@problems`, `@terminal`.

In the browser the chat can also read your workspace under `/workspace`, analyse
dropped documents, and store system prompts as custom "models". Writing is technically
impossible there — that is what VS Code is for.

---

## Rules and skills

**`AGENTS.md`** in the project root is the equivalent of `CLAUDE.md` and is always in
context. Note that Continue lists `["AGENTS.md", "AGENT.md", "CLAUDE.md"]` but breaks
after the first entry, so **only `AGENTS.md` works** (as of 2.0.0). It is only looked
for in the root, and with several folders open only the first one's file applies.

Other sources, in `.continue/rules/*.md` per project or globally under `~/.continue/`,
plus the `rules:` block in `continue.config.yaml`. Frontmatter controls loading:
`alwaysApply: true`, `globs: "src/**"`, `description: ...` (model decides) or
`invokable: true` (via `@name`).

**Skills** in Claude's format work unchanged — same frontmatter, and a `read_skill` tool
loads the full text on demand. Put them in `~/.continue/skills/<name>/SKILL.md` for all
projects, or `<project>/.claude/skills/<name>/` for one (Claude reads those too).
Measured with 10 skills and 11 questions: 10/11 routed correctly, all descriptions
together cost about 850 tokens.

---

## Privacy

Prompts, code and chats stay on the machine. Inference is local, Open WebUI only talks
to `localhost:11434`, `ENABLE_OPENAI_API` is off, embeddings run on local
`nomic-embed-text`, and both services bind to `127.0.0.1`.

Three outbound connections carry no content: Ollama checks for updates, Continue
telemetry is disabled via `"continue.telemetryEnabled": false`, and models and images
are downloaded once. To also block Ollama Cloud: `launchctl setenv OLLAMA_NO_CLOUD 1`,
and add it to `~/Library/LaunchAgents/local.ollama.host.plist`.

---

## Commands

```bash
docker compose up -d / down / logs -f
docker compose pull && docker compose up -d   # update

ollama list / ps / stop <model>
brew services list                            # does Colima start at login?
```

The `local.ollama.host` agent sets `OLLAMA_HOST=0.0.0.0` (so containers can reach it),
`OLLAMA_FLASH_ATTENTION=1` and `OLLAMA_KV_CACHE_TYPE=q8_0` (halves context memory),
`OLLAMA_MAX_LOADED_MODELS=2` (chat and autocomplete stay loaded together) and
`OLLAMA_KEEP_ALIVE=30m` at every login. Colima runs as a Homebrew service; the
containers come back up via `restart: unless-stopped`.

---

## Troubleshooting

**No autocomplete** — check `ollama ps`. The first request after a start loads the model
and takes a few seconds.

**Chat finds no models** — Ollama must listen on `0.0.0.0`. Check with
`lsof -nP -iTCP:11434 -sTCP:LISTEN`, you want `*:11434`. Otherwise restart Ollama.app.

**Running on the GPU?** — `grep "inference compute" ~/.ollama/logs/server.log` must show
`library=Metal`, not `library=cpu`.

**"I don't have access to the files"** — true in chat mode; only **agent** mode gives
the model tools. Even then a 30B model sometimes skips the tool on "create file X" —
phrase it more directly.

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
| `profile.sh` | match models and context size to the hardware |
| `docker-compose.yml` | chat and file tool service |
| `continue.config.yaml` | models, context providers and rules; copied to `~/.continue/config.yaml` by the scripts |
| `.env.example` | template for `.env`, which is never committed |
