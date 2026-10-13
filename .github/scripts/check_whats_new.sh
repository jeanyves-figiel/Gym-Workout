#!/usr/bin/env bash
# What's new (#183, #245): validates the bundled release notes shown on first open after an update and the
# history of earlier releases listed in Account → What's new.
# When the notes' id differs from the last TestFlight build's, that build's notes must be the first entry of
# the history (move them there when starting a new release's notes).
# With --since-last-testflight, also fails when the id is unchanged since the last TestFlight build tag,
# so every release ships new notes.
set -euo pipefail
F=ios/MonkeyWorkout/Resources/WhatsNew.json
H=ios/MonkeyWorkout/Resources/WhatsNewHistory.json
ITEMS='all(.items[]; (.symbol | length > 0) and (.title | length > 0) and (.body | length > 0)
  and (.tint | IN("warmup", "power", "strength", "mobility", "cardio", "stretch")))'
jq -e "(.id | type == \"string\" and length > 0)
  and (.items | type == \"array\" and length > 0 and length <= 5) and $ITEMS" "$F" >/dev/null \
  || { echo "::error file=$F::Invalid What's new: needs id and 1-5 items with symbol, tint (category), title, body"; exit 1; }
jq -e "(.releases | type == \"array\") and all(.releases[]; (.id | length > 0) and (.items | length > 0) and $ITEMS)
  and ([.releases[].id] | length == (unique | length))" "$H" >/dev/null \
  || { echo "::error file=$H::Invalid What's new history: releases need a unique id and valid items"; exit 1; }
ID=$(jq -r .id "$F")
echo "What's new $ID: $(jq '.items | length' "$F") items; history: $(jq '.releases | length' "$H") releases"

LAST=$(git tag -l 'testflight-*' --sort=-v:refname | head -1)
if [ -z "$LAST" ]; then echo "No TestFlight tag fetched; history order not checked"; exit 0; fi
SHIPPED=$(git show "$LAST:$F" 2>/dev/null | jq -r .id)
if [ "$SHIPPED" != "$ID" ] && [ "$(jq -r '.releases[0].id' "$H")" != "$SHIPPED" ]; then
  echo "::error file=$H::New notes $ID started, but $LAST's notes ($SHIPPED) are not first in the history. Add them on top of $H (id, build, date, items)."
  exit 1
fi

if [ "${1:-}" = "--since-last-testflight" ]; then
  if [ "$SHIPPED" = "$ID" ]; then
    echo "::error file=$F::What's new unchanged since $LAST. Write this release's notes (new id + items), or rerun with same_whats_new for a rebuild."
    exit 1
  fi
  echo "What's new changed since $LAST"
fi
