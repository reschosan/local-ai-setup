#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

AGENT_LABEL="local.ollama.host"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

info() { printf "\n\033[1;34m==> %s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31m!! %s\033[0m\n" "$1"; exit 1; }

info "Checking Ollama"
[ -d /Applications/Ollama.app ] || fail "Ollama.app is not in /Applications. Download it from ollama.com and install it there."
command -v ollama >/dev/null 2>&1 || fail "The ollama CLI is not on your PATH. Start Ollama.app once and confirm the symlink prompt."
echo "OK: $(ollama --version 2>/dev/null | tail -1)"

info "Making the network binding permanent"
# Ollama binds to 127.0.0.1 by default, which containers cannot reach.
# This agent sets the variables at every login, before the app starts.
cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>launchctl setenv OLLAMA_HOST 0.0.0.0; launchctl setenv OLLAMA_KEEP_ALIVE 30m; launchctl setenv OLLAMA_FLASH_ATTENTION 1; launchctl setenv OLLAMA_KV_CACHE_TYPE q8_0; launchctl setenv OLLAMA_MAX_LOADED_MODELS 2</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
launchctl setenv OLLAMA_HOST 0.0.0.0
launchctl setenv OLLAMA_KEEP_ALIVE 30m
launchctl setenv OLLAMA_FLASH_ATTENTION 1
launchctl setenv OLLAMA_KV_CACHE_TYPE q8_0
launchctl setenv OLLAMA_MAX_LOADED_MODELS 2

info "Starting Ollama"
if ! curl -fsS http://localhost:11434/api/version >/dev/null 2>&1; then
  open -a /Applications/Ollama.app
fi
for _ in $(seq 1 40); do
  curl -fsS http://localhost:11434/api/version >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS http://localhost:11434/api/version >/dev/null || fail "Ollama is not responding on port 11434."

if ! lsof -nP -iTCP:11434 -sTCP:LISTEN 2>/dev/null | grep -qE '\*:11434|\[::\]'; then
  echo "WARNING: Ollama is only listening locally. Quit Ollama.app and start it again so"
  echo "         OLLAMA_HOST=0.0.0.0 takes effect, otherwise the chat will find no models."
fi

if grep -q "library=Metal" ~/.ollama/logs/server.log 2>/dev/null; then
  echo "GPU: Metal active"
else
  echo "WARNING: no Metal GPU detected - inference will run on the CPU and be very slow."
fi

info "Checking the Docker daemon"
if ! docker info >/dev/null 2>&1; then
  if command -v colima >/dev/null 2>&1; then
    echo "Starting Colima ..."
    colima start --cpu 2 --memory 4 --disk 20
  else
    fail "No running Docker daemon. Install Colima: brew install colima"
  fi
fi
docker info >/dev/null 2>&1 || fail "Docker daemon not reachable."
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

# Picks models and context size to match the available memory, pulls the models
# and installs the Continue config. An existing ~/.continue/config.yaml is never
# overwritten - the script prints how to merge or replace it instead.
./profile.sh "${1:-}"

cat <<'DONE'

Done.

  Chat      http://localhost:3000   the first account becomes admin
  VS Code   install the "Continue" extension (Continue.continue)

  Skills go into ~/.continue/skills/<name>/SKILL.md
  Change profile later: ./profile.sh
  Usage, shortcuts and troubleshooting: README.md

DONE
