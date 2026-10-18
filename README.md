# local-ai-setup

A local AI dev setup: chat in the browser, coding agents in VS Code.
Free, offline, nothing leaves your machine.

```
  VS Code + Cline ─────┐
  VS Code + Zoo Code ──┼──>  Ollama   native on the host, 127.0.0.1:11434, Metal GPU
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
your memory. It touches no editor or system configuration; the editors are set up by
hand, see below.

**Windows:** run the scripts in Git Bash, with Ollama for Windows and Docker Desktop
running. Start Ollama yourself first — the script only starts it on macOS. Set
`WORKSPACE_DIR` as `C:/Users/<you>/projects`, with forward slashes. Ollama runs natively
on the GPU there as well; the Metal check is skipped.

Then open http://localhost:3000 — the first account becomes admin. After registering,
set `ENABLE_SIGNUP=False` in `.env` and run `docker compose up -d` again.

---

## Editor setup

Cline and Zoo Code read rules and skills from the project; only provider and model are
one global setting each. Neither has autocomplete, so this setup has none: Continue,
which provided it, is no longer maintained since June 2026 and was dropped.

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
| Model | `qwen3.6:35b-a3b` or `qwen3.8:27b` |
| Model Context Window | `32768`, `65536`, `131072` or `262144` — see [Context sizes](#context-sizes) |
| Request Timeout (ms) | `1800000` |

No thousands separators — Cline passes the field to Ollama verbatim, and `131.072`
becomes a context of 131 tokens. With **Use different models for Plan and Act modes** on,
set both. The 5-minute default timeout is too short: ingesting 70k tokens takes about
2 minutes with `qwen3.6:35b-a3b` and over 10 with `qwen3.8:27b` on an M5 Pro, and Cline
would abort.

Telemetry follows VS Code: `"telemetry.telemetryLevel": "off"` in the user settings.

### Zoo Code

A fork of Roo Code (itself a Cline fork) that runs several agent modes — code, architect,
ask, debug. Like Cline it keeps provider and model globally, under **Settings → Providers**:

| Setting | Value |
|---|---|
| API Provider | `Ollama` |
| Base URL | `http://localhost:11434` |
| Model | `qwen3.6:35b-a3b` or `qwen3.8:27b` |

Raise `zoo-code.apiRequestTimeout` in the VS Code settings — it defaults to 600 seconds,
and ingesting 70k tokens with `qwen3.8:27b` takes over 10 minutes on an M5 Pro.

Unlike Cline it indexes the codebase itself with Ollama embeddings, for semantic search
over large projects. Its default model is `nomic-embed-text`; under codebase indexing
set the model to `qwen3-embedding:0.6b` with dimension `1024`, which the profiles pull.

From the project it reads `AGENTS.md` (`zoo-code.useAgentRules`, on by default), rules in
`.roo/rules/` plus per-mode folders like `.roo/rules-code/`, `.clinerules/` from Cline,
and skills in `.roo/skills/<name>/SKILL.md`.

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

**VS Code without Cline or Zoo Code** runs through the GitHub Copilot Chat extension,
which `ollama launch vscode` expects to be installed; it prints a hint if it is missing.
The models then appear in Copilot Chat's model picker under *Other models*. Two caveats:
the extension needs a GitHub account, and it covers chat only.

These clients send no context size of their own, so the **Context length** slider in the
Ollama app applies to them.

---

## Context sizes

Measured on an M5 Pro with 48 GB, where macOS gives the GPU at most 37.4 GiB, with
Ollama 0.34.2:

| Model | Context | Memory | Fully on the GPU | Prompt ingest |
|---|---|---|---|---|
| `qwen2.5-coder:7b` | 8k | 4.8 GiB | yes | ~1,300 tokens/s |
| `qwen3.6:35b-a3b` | 32k | 20.9 GiB | yes | |
| `qwen3.6:35b-a3b` | 64k | 21.0 GiB | yes | |
| `qwen3.6:35b-a3b` | 128k | 21.3 GiB | yes | 42k tokens in 58 s |
| `qwen3.6:35b-a3b` | 256k | 21.7 GiB | yes | |
| `qwen3.8:27b` | 32k | 17.0 GiB | yes | |
| `qwen3.8:27b` | 64k | 17.3 GiB | yes | |
| `qwen3.8:27b` | 128k | 17.2 GiB | yes | 42k tokens in 194 s |
| `qwen3.8:27b` | 256k | 20.3 GiB | **no**, 86% | 42k tokens in 362 s |

- **48 GB**: `qwen3.6:35b-a3b` with 128k as the default, 256k costs only 0.4 GiB more.
  Both Qwen 3.6 and 3.8 keep a KV cache in few of their layers, so context is cheap. As a
  mixture of experts with 3B active parameters, 3.6 reads prompts about 3x faster than the
  dense `qwen3.8:27b`; use 3.8 when the answer quality matters more than speed, up to
  128k — at 256k Ollama moves 4 of its 66 layers to the CPU and it gets twice as slow.
- **32 GB**: `qwen3.6:35b-a3b` with 32k — tight, check that `ollama ps` shows `100% GPU`.
  `qwen3.8:27b` with 32k or 64k leaves more room, at a third of the speed.
- **16 GB**: `qwen2.5-coder:7b` with 16k; the model handles at most 32k.

A bigger window reserves its memory the moment the model loads, and once it no longer
fits on the GPU even short prompts get slow. Attention grows quadratically, so filling
256k takes well over half an hour. For large codebases let the agent search instead —
Zoo Code's codebase index sends a few thousand relevant tokens rather than a hundred
thousand arbitrary ones.

The **Context length** slider in the Ollama app only applies to clients that send no
context size of their own: Cline always sends one, Open WebUI the one `profile.sh` sets.

---

## Profiles

```bash
./profile.sh          # suggests one based on your RAM
./profile.sh large    # apply directly
```

| Profile | Models pulled | Browser chat | RAM |
|---|---|---|---|
| `small` | `qwen2.5-coder:7b` | 7B, 16k | 16 GB+ |
| `medium` | + `qwen3.6:35b-a3b` | 3.6, 32k | 32 GB+ |
| `large` | + `qwen3.6:35b-a3b`, `qwen3.8:27b` | 3.6, 128k | 48 GB+ |

`qwen3-embedding:0.6b` is always pulled for embeddings. On German and English questions
against the sections of this README it found the right one 12 of 12 times,
`nomic-embed-text` 8 of 12.

The profile only decides what gets downloaded and what the browser chat uses; in VS Code
you set the model in Cline or Zoo Code. For a model outside the profiles,
`ollama pull <name>` and select it there.

---

## Usage

Cline and Zoo Code always work with tools and ask before every change unless you allow
auto-approve.

In the browser the chat reads your workspace under `/workspace`, analyses dropped
documents and stores system prompts as custom "models". Writing is impossible there — the
mount is read-only.

---

## Rules and skills

**`AGENTS.md`** in the project root is read by Cline, Zoo Code and Codex; it is the
equivalent of `CLAUDE.md`. More rules per project: `.clinerules/` for Cline and Zoo Code,
plus `.roo/rules/` for Zoo Code.

**Skills** in Claude's format work unchanged — same frontmatter, loaded on demand. Put
them in `<project>/.claude/skills/<name>/SKILL.md`: Claude Code and Cline read that
folder; Zoo Code uses `.roo/skills/` instead.

**Skills in the browser chat** live in Open WebUI's database, not in a folder — it scans
none, so import them from `SKILLS_DIR` in `.env`, by default `~/.agents/skills` (on
Windows `C:/Users/<you>/.agents/skills`), one subfolder with a `SKILL.md` per skill:

```bash
./load-skills-openwebui.sh
```

New skills are added, changed ones updated, unchanged ones left alone — run it again
after editing skills, no restart needed. Skills you delete from the folder stay in the
chat; remove them under **Workspace → Skills**, where **Import skills** also takes a ZIP
by hand. Models with native tool calling get the list and load a skill when it fits;
otherwise mention it with `$` in the message.

---

## Privacy

Prompts, code and chats stay on the machine. Inference is local, Ollama listens on
`127.0.0.1` only, Open WebUI binds to `127.0.0.1:3000` and talks to nothing but Ollama,
`ENABLE_OPENAI_API` is off, embeddings run on local `qwen3-embedding:0.6b`, and the file
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
Measured with a file edit, whose arguments span several lines: `qwen3.6:35b-a3b` and
`qwen3.8:27b` succeeded 5 of 5 times, `qwen3-coder:30b` only 4 of 10 — the reason it left
the profiles. `qwen2.5-coder:32b` never produces a valid call.

**Machine feels slow** — `ollama stop <model>` unloads immediately.

---

## Upgrading from an older version

Skip this on a fresh install.

Older versions installed a LaunchAgent for `OLLAMA_HOST`, `OLLAMA_KV_CACHE_TYPE` and
others. The Ollama app starts its server with its own environment, so these never
arrived — the server log shows them empty. Remove it, and the Continue config the
scripts copied into your home:

```bash
launchctl bootout gui/$(id -u)/local.ollama.host
rm ~/Library/LaunchAgents/local.ollama.host.plist
for v in OLLAMA_HOST OLLAMA_KEEP_ALIVE OLLAMA_FLASH_ATTENTION OLLAMA_KV_CACHE_TYPE OLLAMA_MAX_LOADED_MODELS; do
  launchctl unsetenv "$v"
done
rm -r ~/.continue             # back it up first if you edited it
```

They also named containers and volumes after the folder the repo was cloned into.
`setup.sh` replaces such containers and copies their chat data into the new
`lai-open-webui-data` volume once, keeping the old volumes as a backup — list them with
`docker volume ls`, remove them with `docker volume rm` once everything works.

Continue is no longer part of the setup: delete `.continue/` from your projects and
uninstall the extension.

Embeddings moved from `nomic-embed-text` to `qwen3-embedding:0.6b`. Open WebUI keeps the
model it started with, so switch it under **Admin Panel → Settings → Documents** —
documents uploaded before need re-indexing, which Open WebUI offers there. Then
`ollama rm nomic-embed-text`.

---

## Files

| File | Purpose |
|---|---|
| `setup.sh` | first-time install, calls `profile.sh` |
| `profile.sh` | pull the models that fit the hardware, set browser chat defaults |
| `load-skills-openwebui.sh` | import the skills from `SKILLS_DIR` into the browser chat |
| `docker-compose.yml` | chat and file tool service |
| `.env.example` | template for `.env`, which is never committed |
