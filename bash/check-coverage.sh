#!/usr/bin/env bash
#
# The coverage gate: 100% lines, statements, branches and functions
# for every file under src/, read from `forge coverage --report summary`. forge
# reports branch coverage natively, which is why the Solidity half can be held
# to 100% branches. Every row is checked on
# its own, and a run that measures nothing fails rather than passing on an
# empty table — the shape that once let a mutation gate report success for a
# week while generating no mutants.
#
# Every .sol under src/ must also appear in that table. A file forge finds no
# coverable items in — one holding only constants, structs or interfaces — is
# left out of the summary entirely, so checking the rows that are present would
# pass a file nothing ever measured. A transposed mode byte or a reordered Call
# struct lives in exactly such a file, which is the failure this library exists
# to prevent. The rows are reconciled against the files on disk.
set -euo pipefail

cd "$(dirname "$0")/.."

# Captured rather than streamed, so the table can be parsed; on a compile
# failure the captured output is the only report of what went wrong, so print
# it instead of exiting on `set -e` with an empty log.
if ! OUTPUT=$(forge coverage --report summary 2>&1); then
  echo "FAIL: forge coverage did not complete:"
  echo "$OUTPUT"
  exit 1
fi
FILES=$(echo "$OUTPUT" | grep -E '^\| src/' || true)

FAILED=0
CHECKED=0
SEEN=""
while IFS= read -r LINE; do
  [ -z "$LINE" ] && continue
  FILE=$(echo "$LINE" | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}')
  CHECKED=$((CHECKED + 1))
  SEEN=$(printf '%s\n%s' "$SEEN" "$FILE")
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

# A file on disk that forge never put in the table was never measured. Reported
# per file, because "the count is off by one" is not an actionable CI log.
ONDISK=$(find src -name '*.sol' | sed 's|^\./||' | sort)
while IFS= read -r F; do
  [ -z "$F" ] && continue
  if ! printf '%s\n' "$SEEN" | grep -qxF "$F"; then
    echo "FAIL: $F — absent from forge's coverage table, so nothing measured it"
    echo "      (a file of only constants, structs or interfaces has no coverable"
    echo "       items; give it a test that exercises it, or move it beside what"
    echo "       uses it)"
    FAILED=1
  fi
done <<< "$ONDISK"

if [ "$CHECKED" -eq 0 ]; then
  echo "FAIL: no src/ file in forge's coverage table — the format may have changed:"
  echo "$OUTPUT" | tail -20
  exit 1
fi
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "lattice-std coverage gate passed ($CHECKED file(s) at 100/100)"
