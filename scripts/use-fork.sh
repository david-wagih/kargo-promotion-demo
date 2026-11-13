#!/usr/bin/env bash
# Point the whole demo at your own fork: ./scripts/use-fork.sh <owner>/<repo>
set -euo pipefail
NEW=${1:?usage: use-fork.sh <owner>/<repo>}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OLD=$(grep '^GITHUB_REPO=' "$ROOT/scripts/lib.sh" | cut -d= -f2)
new_owner=$(echo "${NEW%%/*}" | tr '[:upper:]' '[:lower:]'); old_owner=${OLD%%/*}
grep -rlE "$OLD|ghcr.io/$old_owner/" "$ROOT" --exclude-dir=.git --exclude-dir=bin --exclude-dir=.generated \
  | xargs sed -i.bak -e "s#$OLD#$NEW#g" -e "s#ghcr.io/$old_owner/#ghcr.io/$new_owner/#g"
find "$ROOT" -name '*.bak' -not -path '*/.git/*' -delete
echo "now using $NEW (image ghcr.io/$new_owner/demo-app)"
