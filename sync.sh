#!/usr/bin/env bash
# Stage all changes in this repo, commit with the given message (or a default),
# and push to the remote. Run from anywhere.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    msg="${1:-docs: update $(date +%Y-%m-%d)}"
    git add -A
    git commit -m "$msg"
    git push
    echo "Pushed: $msg"
else
    echo "No changes to commit."
fi
