#!/usr/bin/env bash
# Pulls the models that fit the available hardware and sets the browser chat defaults.
#   ./profile.sh          suggests a profile based on RAM
#   ./profile.sh small    applies a profile directly
set -euo pipefail
cd "$(dirname "$0")"

# Keeps Git Bash on Windows from rewriting paths in docker arguments.
export MSYS_NO_PATHCONV=1

info() { printf "\n\033[1;34m==> %s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31m!! %s\033[0m\n" "$1"; exit 1; }

total_ram_gb() {
  if [ "$(uname)" = "Darwin" ]; then
    echo $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
  else
    # Linux and Git Bash on Windows both provide /proc/meminfo.
    kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || true)
    echo $(( ${kb:-0} / 1024 / 1024 ))
  fi
}

# profile -> browser chat model, its context, models to pull
profile_values() {
  case "$1" in
    small)  echo "qwen2.5-coder:7b 16384 qwen2.5-coder:7b qwen3-embedding:0.6b" ;;
    medium) echo "qwen3.6:35b-a3b  32768 qwen3.6:35b-a3b qwen3-embedding:0.6b" ;;
    large)  echo "qwen3.6:35b-a3b 131072 qwen3.6:35b-a3b qwen3.8:27b qwen3-embedding:0.6b" ;;
    *) return 1 ;;
  esac
}

suggest_profile() {
  ram=$(total_ram_gb)
  if   [ "$ram" -ge 48 ]; then echo large
  elif [ "$ram" -ge 32 ]; then echo medium
  else echo small
  fi
}

apply() {
  read -r chat ctx models <<<"$(profile_values "$1")"

  info "Pulling models"
  for m in $models; do
    if ollama list 2>/dev/null | awk '{print $1}' | grep -qE "^${m}(:latest)?$"; then
      echo "  $m already present"
    else
      ollama pull "$m"
    fi
  done

  if docker compose ps --status running 2>/dev/null | grep -q lai-open-webui; then
    info "Applying settings to the chat"
    docker exec lai-open-webui python3 -c "
import sqlite3, json, time
c = sqlite3.connect('/app/backend/data/webui.db')
row = c.execute(\"SELECT value FROM config WHERE key='models.default_params'\").fetchone()
params = json.loads(row[0]) if row and row[0] else {}
params['num_ctx'] = $ctx
for key, value in [('models.default_params', params), ('ui.default_models', '$chat')]:
    c.execute('UPDATE config SET value=?, updated_at=? WHERE key=?',
              (json.dumps(value), int(time.time()), key))
c.commit()" >/dev/null
    docker compose restart open-webui >/dev/null 2>&1
    echo "  done, chat restarted"
  fi

  cat <<EOF

Profile "$1":

  Models          $models
  Browser chat    $chat with $ctx tokens of context

In VS Code, set model and context size in the Cline or Zoo Code settings.
EOF
}

command -v ollama >/dev/null 2>&1 || fail "ollama not found."

apply_checked() {
  profile_values "$1" >/dev/null 2>&1 || fail "Unknown profile '$1'. Available: small, medium, large"
  apply "$1"
}

if [ $# -ge 1 ] && [ -n "$1" ]; then
  apply_checked "$1"
  exit 0
fi

ram=$(total_ram_gb)
suggested=$(suggest_profile)
cat <<EOF

Memory: ${ram} GB  ->  suggested profile: $suggested

  small    qwen2.5-coder:7b                     16 GB+
  medium   + qwen3.6:35b-a3b                    32 GB+
  large    + qwen3.6:35b-a3b and qwen3.8:27b    48 GB+

EOF
printf "Profile [%s]: " "$suggested"
read -r choice
apply_checked "${choice:-$suggested}"
