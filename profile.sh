#!/usr/bin/env bash
# Tunes models and context size to the available hardware.
#   ./profile.sh          suggests a profile based on RAM
#   ./profile.sh small    applies a profile directly
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=continue.config.yaml

info() { printf "\n\033[1;34m==> %s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31m!! %s\033[0m\n" "$1"; exit 1; }

total_ram_gb() {
  if [ "$(uname)" = "Darwin" ]; then
    echo $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
  else
    echo $(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
  fi
}

# profile -> chat model, context, autocomplete model, minimum RAM
profile_values() {
  case "$1" in
    small)  echo "qwen2.5-coder:7b 16384 qwen2.5-coder:1.5b 16" ;;
    medium) echo "qwen3-coder:30b  32768 qwen2.5-coder:7b   32" ;;
    large)  echo "qwen3-coder:30b  65536 qwen2.5-coder:7b   48" ;;
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
  read -r chat ctx complete _min <<<"$(profile_values "$1")"

  # Decide before rewriting: an existing ~/.continue/config.yaml that differs from
  # ours belongs to the user and is never touched.
  managed=1
  if [ -f ~/.continue/config.yaml ] && ! cmp -s "$CONFIG" ~/.continue/config.yaml; then
    managed=0
  fi

  # Only touch model and context inside the models block. The rules block uses
  # "- name:" entries at the same indentation, so scope matters here.
  awk -v chat="$chat" -v ctx="$ctx" -v complete="$complete" '
    /^models:/                 { in_models=1 }
    /^[a-z]/ && !/^models:/    { in_models=0 }
    in_models && /^  - name: Chat & Agent/  { block="chat" }
    in_models && /^  - name: Chat \(fast\)/ { block="quick" }
    in_models && /^  - name: Autocomplete/  { block="complete" }
    in_models && /^  - name: Embeddings/    { block="embed" }
    in_models && /^    model:/ {
      if (block=="chat")     { print "    model: " chat;     next }
      if (block=="quick")    { print "    model: " complete; next }
      if (block=="complete") { print "    model: " complete; next }
    }
    in_models && /^      contextLength:/ {
      if (block=="chat") { print "      contextLength: " ctx; next }
    }
    { print }
  ' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"

  mkdir -p ~/.continue/skills
  if [ "$managed" = "1" ]; then
    cp "$CONFIG" ~/.continue/config.yaml
  fi

  info "Pulling models"
  for m in "$chat" "$complete" nomic-embed-text; do
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

  Chat & Agent    $chat with $ctx tokens of context
  Autocomplete    $complete
  Embeddings      nomic-embed-text
EOF

  if [ "$managed" = "1" ]; then
    cat <<EOF

Written to ~/.continue/config.yaml. Reload VS Code to pick it up.
EOF
  else
    cat <<EOF

You already have your own ~/.continue/config.yaml, so it was left untouched.
Merge the settings yourself, or replace the file:

  diff ~/.continue/config.yaml $PWD/$CONFIG
  cp $PWD/$CONFIG ~/.continue/config.yaml

Then reload VS Code.
EOF
  fi
}

command -v ollama >/dev/null 2>&1 || fail "ollama not found."
[ -f "$CONFIG" ] || fail "$CONFIG not found."

if [ $# -ge 1 ] && [ -n "$1" ]; then
  profile_values "$1" >/dev/null 2>&1 || fail "Unknown profile '$1'. Available: small, medium, large"
  apply "$1"
  exit 0
fi

ram=$(total_ram_gb)
suggested=$(suggest_profile)
cat <<EOF

Memory: ${ram} GB  ->  suggested profile: $suggested

  small    qwen2.5-coder:7b    16k context    16 GB+
  medium   qwen3-coder:30b     32k context    32 GB+
  large    qwen3-coder:30b     64k context    48 GB+

EOF
printf "Profile [%s]: " "$suggested"
read -r choice
apply "${choice:-$suggested}"
