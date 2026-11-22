#!/usr/bin/env bash
# Build the People Insights React UI and deploy the app (backend + built UI) to the workspace.
# Usage: scripts/deploy_app.sh <profile> [app_name] [workspace_dir]
set -euo pipefail
PROFILE=${1:?profile}
APP=${2:-abac-hr-genie-demo}
ME=$(databricks current-user me -p "$PROFILE" -o json | python3 -c "import json,sys;print(json.load(sys.stdin)['userName'])")
DEST=${3:-/Workspace/Users/$ME/abac-hr-demo/app}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

(cd "$ROOT/app/frontend" && npm install --silent && npm run build >/dev/null)

STAGE=$(mktemp -d)
cp "$ROOT/app/app.yaml" "$ROOT/app/requirements.txt" "$STAGE/"
mkdir -p "$STAGE/backend" "$STAGE/frontend"
cp "$ROOT/app/backend/main.py" "$STAGE/backend/"
cp -R "$ROOT/app/frontend/dist" "$STAGE/frontend/dist"

databricks workspace delete "$DEST" --recursive -p "$PROFILE" >/dev/null 2>&1 || true
databricks workspace import-dir "$STAGE" "$DEST" -p "$PROFILE" >/dev/null
databricks apps deploy "$APP" --source-code-path "$DEST" -p "$PROFILE" -o json \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['status']['state'], '-', d['status'].get('message',''))"
rm -rf "$STAGE"
