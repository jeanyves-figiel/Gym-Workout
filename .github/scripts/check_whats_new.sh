#!/usr/bin/env bash
# What's new (#183): validates the bundled release notes shown on first open after an update.
# With --since-last-testflight, also fails when their id is unchanged since the last TestFlight build tag,
# so every release ships new notes.
set -euo pipefail
F=ios/MonkeyWorkout/Resources/WhatsNew.json
jq -e '(.id | type == "string" and length > 0)
  and (.items | type == "array" and length > 0 and length <= 5)
  and all(.items[]; (.symbol | length > 0) and (.title | length > 0) and (.body | length > 0)
    and (.tint | IN("warmup", "power", "strength", "mobility", "cardio", "stretch")))' "$F" >/dev/null \
  || { echo "::error file=$F::Invalid What's new: needs id and 1-5 items with symbol, tint (category), title, body"; exit 1; }
echo "What's new $(jq -r .id "$F"): $(jq '.items | length' "$F") items"

if [ "${1:-}" = "--since-last-testflight" ]; then
  LAST=$(git tag -l 'testflight-*' --sort=-v:refname | head -1)
  if [ -z "$LAST" ]; then echo "No previous TestFlight tag"; exit 0; fi
  if [ "$(git show "$LAST:$F" 2>/dev/null | jq -r .id)" = "$(jq -r .id "$F")" ]; then
    echo "::error file=$F::What's new unchanged since $LAST. Write this release's notes (new id + items), or rerun with same_whats_new for a rebuild."
    exit 1
  fi
  echo "What's new changed since $LAST"
fi
