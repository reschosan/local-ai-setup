#!/usr/bin/env bash
# Imports the skills from SKILLS_DIR into the browser chat: new ones are added, changed
# ones updated, unchanged ones left alone. Skills deleted from the folder stay in the chat.
#   ./load-skills-openwebui.sh
set -euo pipefail
cd "$(dirname "$0")"

# Keeps Git Bash on Windows from rewriting container paths like /tmp in docker arguments.
export MSYS_NO_PATHCONV=1

info() { printf "\n\033[1;34m==> %s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31m!! %s\033[0m\n" "$1"; exit 1; }

skills_dir=${SKILLS_DIR:-$(grep '^SKILLS_DIR=' .env 2>/dev/null | tr -d '\r' | cut -d= -f2- | sed "s|\${HOME}|$HOME|" || true)}
skills_dir=${skills_dir:-$HOME/.agents/skills}
[ -d "$skills_dir" ] || fail "No skills folder at '$skills_dir'. Set SKILLS_DIR in .env."
docker compose ps --status running 2>/dev/null | grep -q lai-open-webui \
  || fail "The chat is not running - start it with docker compose up -d."

info "Importing skills from $skills_dir"
docker exec lai-open-webui sh -c 'rm -rf /tmp/lai-skills && mkdir /tmp/lai-skills'
# -h copies the files that links point to, so linked skill folders arrive complete.
tar -chf - -C "$skills_dir" --exclude .DS_Store . | docker exec -i lai-open-webui tar -xf - -C /tmp/lai-skills --warning=no-unknown-keyword

docker exec -i -w /app/backend lai-open-webui python3 - <<'EOF'
import io, json, os, pathlib, sqlite3, time, uuid, zipfile
import jwt, requests
from open_webui.utils.skill_files import parse_import

root = pathlib.Path('/tmp/lai-skills')
skill_dirs = sorted(p.parent for p in root.rglob('SKILL.md'))
skill_dirs = [d for d in skill_dirs if not any(d != o and o in d.parents for o in skill_dirs)]
if not skill_dirs:
    raise SystemExit('  no folder with a SKILL.md found')

archive = io.BytesIO()
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for skill_dir in skill_dirs:
        for path in sorted(skill_dir.rglob('*')):
            if path.is_file():
                z.write(path, path.relative_to(root).as_posix())
archive = archive.getvalue()
packages = parse_import(archive, 'skills.zip')

db = sqlite3.connect('file:/app/backend/data/webui.db?mode=ro', uri=True)
admin = db.execute("SELECT id FROM user WHERE role='admin' ORDER BY created_at LIMIT 1").fetchone()
if not admin:
    raise SystemExit('  no admin account yet - register in the chat first')
token = jwt.encode({'id': admin[0], 'exp': int(time.time()) + 300, 'jti': str(uuid.uuid4())},
                   os.environ['WEBUI_SECRET_KEY'], algorithm='HS256')
api = 'http://localhost:8080/api/v1/skills'
headers = {'Authorization': f'Bearer {token}'}
upload = lambda: [('files', ('skills.zip', archive, 'application/zip'))]

def stored_files(skill_id):
    row = db.execute('SELECT data FROM skill WHERE id=?', (skill_id,)).fetchone()
    files = json.loads(row[0]).get('files', []) if row and row[0] else []
    return {f['path']: f.get('content') for f in files}

preview = requests.post(f'{api}/import/preview', headers=headers, files=upload(), timeout=60)
preview.raise_for_status()
decisions, labels = [], []
for item, package in zip(preview.json(), packages):
    if item['id_taken'] and not item['can_replace']:
        decisions.append({'action': 'skip'}); labels.append('skipped, owned by another user')
    elif item['id_taken'] and stored_files(item['id']) == {f['path']: f.get('content') for f in package['files']}:
        decisions.append({'action': 'skip'}); labels.append('unchanged')
    elif item['id_taken']:
        decisions.append({'action': 'replace', 'expected_version_id': item['expected_version_id']})
        labels.append('updated')
    elif item['name_taken']:
        decisions.append({'action': 'skip'}); labels.append('skipped, another skill has this name')
    else:
        decisions.append({'action': 'create'}); labels.append('added')

result = requests.post(f'{api}/import', headers=headers, files=upload(),
                       data={'decisions': json.dumps(decisions)}, timeout=120)
result.raise_for_status()
for item, label in zip(result.json(), labels):
    print(f"  {item['id']}: {item['error'] if item['status'] == 'error' else label}")
EOF

docker exec lai-open-webui rm -rf /tmp/lai-skills
echo
echo "Done - the skills are under Workspace -> Skills in the chat, no restart needed."
