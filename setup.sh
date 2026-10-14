#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

info() { printf "\n\033[1;34m==> %s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31m!! %s\033[0m\n" "$1"; exit 1; }

info "Checking Ollama"
[ -d /Applications/Ollama.app ] || fail "Ollama.app is not in /Applications. Download it from ollama.com and install it there."
command -v ollama >/dev/null 2>&1 || fail "The ollama CLI is not on your PATH. Start Ollama.app once and confirm the symlink prompt."
echo "OK: $(ollama --version 2>/dev/null | tail -1)"

info "Starting Ollama"
if ! curl -fsS http://localhost:11434/api/version >/dev/null 2>&1; then
  open -a /Applications/Ollama.app
fi
for _ in $(seq 1 40); do
  curl -fsS http://localhost:11434/api/version >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS http://localhost:11434/api/version >/dev/null || fail "Ollama is not responding on port 11434."

if grep -q "library=Metal" ~/.ollama/logs/server.log 2>/dev/null; then
  echo "GPU: Metal active"
else
  echo "WARNING: no Metal GPU detected - inference will run on the CPU and be very slow."
fi

info "Checking the Docker daemon"
docker info >/dev/null 2>&1 || fail "No running Docker daemon. Start your Docker runtime (Colima, Docker Desktop, OrbStack) and run ./setup.sh again."
echo "OK"

info "Preparing .env"
if [ ! -f .env ]; then
  cp .env.example .env
  echo "  created from .env.example"
fi

# Replace placeholders with random values, also in an existing .env in case
# new variables were added later.
sed_inplace() {
  if sed --version >/dev/null 2>&1; then sed -i "$1" .env; else sed -i '' "$1" .env; fi
}
grep -q CHANGE_ME_SECRET  .env && sed_inplace "s/CHANGE_ME_SECRET/$(openssl rand -hex 32)/"  && echo "  WEBUI_SECRET_KEY generated"
grep -q CHANGE_ME_MCP_KEY .env && sed_inplace "s/CHANGE_ME_MCP_KEY/$(openssl rand -hex 24)/" && echo "  MCP_API_KEY generated"

WORKSPACE_DIR=$(grep '^WORKSPACE_DIR=' .env | cut -d= -f2- | sed "s|\${HOME}|$HOME|")
if [ ! -d "$WORKSPACE_DIR" ]; then
  fail "WORKSPACE_DIR points at '$WORKSPACE_DIR', which does not exist.
       Set it in .env to the folder you want to work with."
fi
echo "  WORKSPACE_DIR: $WORKSPACE_DIR"

info "Starting the containers"
docker compose up -d

# Colima, Docker Desktop and OrbStack forward host.docker.internal to the host's
# loopback, so Ollama can stay bound to 127.0.0.1.
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
