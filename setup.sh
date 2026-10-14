#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Keeps Git Bash on Windows from rewriting container paths like /from in docker arguments.
export MSYS_NO_PATHCONV=1

info() { printf "\n\033[1;34m==> %s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31m!! %s\033[0m\n" "$1"; exit 1; }
is_macos() { [ "$(uname)" = "Darwin" ]; }

info "Checking Ollama"
if is_macos; then
  [ -d /Applications/Ollama.app ] || fail "Ollama.app is not in /Applications. Download it from ollama.com and install it there."
  command -v ollama >/dev/null 2>&1 || fail "The ollama CLI is not on your PATH. Start Ollama.app once and confirm the symlink prompt."
else
  command -v ollama >/dev/null 2>&1 || fail "The ollama CLI is not on your PATH. Install Ollama from ollama.com and open a new terminal."
fi
echo "OK: $(ollama --version 2>/dev/null | tail -1)"

info "Starting Ollama"
if ! curl -fsS http://localhost:11434/api/version >/dev/null 2>&1; then
  if is_macos; then
    open -a /Applications/Ollama.app
  else
    fail "Ollama is not running. Start the Ollama app and run ./setup.sh again."
  fi
fi
for _ in $(seq 1 40); do
  curl -fsS http://localhost:11434/api/version >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS http://localhost:11434/api/version >/dev/null || fail "Ollama is not responding on port 11434."

if is_macos; then
  if grep -q "library=Metal" ~/.ollama/logs/server.log 2>/dev/null; then
    echo "GPU: Metal active"
  else
    echo "WARNING: no Metal GPU detected - inference will run on the CPU and be very slow."
  fi
fi

info "Checking the Docker daemon"
docker info >/dev/null 2>&1 || fail "No running Docker daemon. Start your Docker runtime (Colima, Docker Desktop, OrbStack) and run ./setup.sh again."
echo "OK"

info "Preparing .env"
env_created=0
if [ ! -f .env ]; then
  cp .env.example .env
  env_created=1
  echo "  created from .env.example"
fi

# Replace placeholders with random values, also in an existing .env in case
# new variables were added later.
sed_inplace() {
  if sed --version >/dev/null 2>&1; then sed -i "$1" .env; else sed -i '' "$1" .env; fi
}
grep -q CHANGE_ME_SECRET  .env && sed_inplace "s/CHANGE_ME_SECRET/$(openssl rand -hex 32)/"  && echo "  WEBUI_SECRET_KEY generated"
grep -q CHANGE_ME_MCP_KEY .env && sed_inplace "s/CHANGE_ME_MCP_KEY/$(openssl rand -hex 24)/" && echo "  MCP_API_KEY generated"

if [ "$env_created" = "1" ]; then
  fail "Adjust WORKSPACE_DIR in .env to the folder the browser chat may read on this
       machine - an absolute path or \${HOME}/..., not ~ (Windows: C:/Users/...).
       Then run ./setup.sh again."
fi

WORKSPACE_DIR=$(grep '^WORKSPACE_DIR=' .env | tr -d '\r' | cut -d= -f2- | sed "s|\${HOME}|$HOME|")
if [ ! -d "$WORKSPACE_DIR" ]; then
  fail "WORKSPACE_DIR points at '$WORKSPACE_DIR', which does not exist.
       Set it in .env to the folder the browser chat may read - an absolute path
       or \${HOME}/..., not ~ (Windows: C:/Users/...)."
fi
echo "  WORKSPACE_DIR: $WORKSPACE_DIR"
echo "  (to change it: edit WORKSPACE_DIR in .env, then docker compose up -d)"

info "Starting the containers"
# Older versions named the compose project after the folder, so a clone in another
# folder clashed with the fixed container names. Replace such containers and take
# over their chat data once; the old volumes are kept.
old_data=""
for container in lai-open-webui lai-mcp-files; do
  project=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$container" 2>/dev/null) || continue
  [ "$project" = "local-ai" ] && continue
  if [ "$container" = "lai-open-webui" ]; then
    old_data=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/app/backend/data"}}{{.Name}}{{end}}{{end}}' "$container")
  fi
  echo "  replacing $container from an older setup (project '$project')"
  docker rm -f "$container" >/dev/null
done
if [ -n "$old_data" ] && ! docker volume inspect lai-open-webui-data >/dev/null 2>&1; then
  echo "  taking over chat data from volume $old_data"
  docker compose create >/dev/null 2>&1 || fail "docker compose create failed - run it by hand to see why."
  docker run --rm -v "$old_data":/from:ro -v lai-open-webui-data:/to \
    --entrypoint sh ghcr.io/open-webui/open-webui:main -c 'cp -a /from/. /to/'
fi

docker compose up -d

# Colima, Docker Desktop and OrbStack forward host.docker.internal to the host, so
# Ollama can stay bound to 127.0.0.1.
if ! docker exec lai-open-webui python3 -c "import urllib.request; urllib.request.urlopen('http://host.docker.internal:11434/api/version', timeout=5)" >/dev/null 2>&1; then
  echo "WARNING: the chat container cannot reach Ollama on the host - see README, Troubleshooting."
fi

# Pulls the models that fit the available memory and sets the browser chat defaults.
./profile.sh "${1:-}"

cat <<DONE

Done.

  Chat      http://localhost:3000   the first account becomes admin
  VS Code   install Continue (Continue.continue) and/or Cline (saoudrizwan.claude-dev)

  Enable it for a project:
    cp -R $PWD/workspace/.continue <project>/
  Cline settings, usage and troubleshooting: README.md
  Change profile later: ./profile.sh

DONE
