#!/usr/bin/env bash
#
# The coverage gate: 100% lines, statements, branches and functions
# for every file under src/, read from `forge coverage --report summary`. forge
# reports branch coverage natively, which is why the Solidity half can be held
# to 100% branches. Every row is checked on
# its own, and a run that measures nothing fails rather than passing on an
# empty table — the shape that once let a mutation gate report success for a
# week while generating no mutants.
set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT=$(forge coverage --report summary 2>&1)
FILES=$(echo "$OUTPUT" | grep -E '^\| src/' || true)

FAILED=0
CHECKED=0
while IFS= read -r LINE; do
  [ -z "$LINE" ] && continue
  FILE=$(echo "$LINE" | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}')
  CHECKED=$((CHECKED + 1))
  # Columns: File | % Lines | % Statements | % Branches | % Funcs, each as
  # "100.00% (n/n)".
  for COL in 3 4 5 6; do
    NAME=$(echo "lines statements branches functions" | cut -d' ' -f$((COL - 2)))
    PCT=$(echo "$LINE" | awk -F'|' -v c="$COL" '{split($c, a, "%"); gsub(/[^0-9.]/, "", a[1]); print a[1]}')
    if [ -z "$PCT" ]; then
      echo "FAIL: $FILE — could not read $NAME coverage from: $LINE"
      FAILED=1
      continue
    fi
    if awk -v p="$PCT" 'BEGIN{exit !(p+0 < 100)}'; then
      echo "FAIL: $FILE — $NAME ${PCT}% < 100%"
      FAILED=1
    else
      echo "  ok: $FILE — $NAME ${PCT}%"
    fi
  done
done <<< "$FILES"

if [ "$CHECKED" -eq 0 ]; then
  echo "FAIL: no src/ file in forge's coverage table — the format may have changed:"
  echo "$OUTPUT" | tail -20
  exit 1
fi
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "lattice-std coverage gate passed ($CHECKED file(s) at 100/100)"
