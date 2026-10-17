#!/bin/sh
# Regression tests for synthesize.py. Uses small synthetic seat transcripts
# written inline below; never touches the real corpus. Covers extraction
# counts, clustering verdicts, exit codes, both status.tsv formats, the
# zero-extraction alarm, and the refuse-to-overwrite guard.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd -P)
BOARD_ROOT=$(dirname "$HERE")
SYN="$BOARD_ROOT/synthesize.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS $*"; }
bad() { fail=$((fail + 1)); echo "FAIL $*"; }

# ---- fixture: one board, three seats ---------------------------------------
# seat-alpha and seat-beta agree on src/auth.py within the same line bucket
# (42 vs 45); each also raises one lone finding (util.py, log.py). seat-zero
# is big prose with zero extractable findings.
mkdir -p "$TMP/board"

cat > "$TMP/board/seat-alpha.txt" <<'EOF'
seat stub transcript
- Let me read the repository first.

  Reading src/auth.py and src/util.py now.

  total 8
  -rw-r--r-- 1 user group 220 Oct 17 src

  ## Findings

  ### 1. CRITICAL - Session token never expires in auth
  `src/auth.py:42`

  The token is a compile-time constant shared by every user.
  ```python
  42    SESSION_TOKEN = "static-sentinel"
  ```

  ### 2. LOW - Vague helper name in util
  src/util.py:7 names a helper `do_stuff`.
EOF

cat > "$TMP/board/seat-beta.txt" <<'EOF'
seat stub transcript
- thinking out loud about the code, nothing structured yet

  Reading auth and logging modules.

  **1. Static session token shared across users**
  Severity: high. See src/auth.py:45 for the assignment.
  The line `SESSION_TOKEN = "static-sentinel"` is the problem.

  ### 2. MEDIUM - log module rotates late
  lib/log.py:99 rotates only daily.
EOF

i=0
while [ "$i" -lt 150 ]; do
  printf 'Careful prose about the code with no headings, no numbered lists, no bold markers, just narrative sentence %s of the review.\n' "$i"
  i=$((i + 1))
done > "$TMP/board/seat-zero.txt"

printf 'seat-alpha\t0\t2400\t2026-10-17T00:00:00Z\n' > "$TMP/board/status.tsv"
printf 'seat-beta\t1\t1800\t2026-10-17T00:00:01Z\n' >> "$TMP/board/status.tsv"
printf 'seat-zero\t0\t18000\t2026-10-17T00:00:02Z\n' >> "$TMP/board/status.tsv"

# ---- case 1: happy path, exit 0, both outputs ------------------------------
rc=0
out=$(python3 "$SYN" "$TMP/board") || rc=$?
if [ "$rc" -eq 0 ] && [ -f "$TMP/board/findings.jsonl" ] && [ -f "$TMP/board/summary.md" ]; then
  ok "happy path: exit 0, findings.jsonl and summary.md written"
else
  bad "happy path: rc=$rc, outputs missing"
fi

# ---- case 2: cluster verdict counts ----------------------------------------
if grep -q "Confirmed clusters: 1" "$TMP/board/summary.md" \
   && grep -q "Plausible clusters: 2" "$TMP/board/summary.md"; then
  ok "verdicts: 1 confirmed cluster, 2 plausible clusters"
else
  bad "verdicts: wrong cluster counts in summary.md"
fi

# ---- case 3: the agreed finding lands in C1 with both seats -----------------
if grep -q "| C1 | seat-alpha, seat-beta | critical | src/auth.py:42 |" "$TMP/board/summary.md"; then
  ok "clustering: auth.py:42/45 findings merged into C1 with both seats"
else
  bad "clustering: C1 row wrong: $(grep '^| C1 ' "$TMP/board/summary.md" || echo '<none>')"
fi

# ---- case 4: per-seat extraction counts, in stdout and in the report --------
if printf '%s\n' "$out" | grep -q "seat-alpha: 2 findings" \
   && printf '%s\n' "$out" | grep -q "seat-beta: 2 findings" \
   && printf '%s\n' "$out" | grep -q "seat-zero: 0 findings" \
   && grep -q "| seat-alpha | 2 |" "$TMP/board/summary.md" \
   && grep -q "| seat-beta | 2 |" "$TMP/board/summary.md" \
   && grep -q "| seat-zero | 0 |" "$TMP/board/summary.md"; then
  ok "extraction counts: 2 / 2 / 0, printed and tabulated"
else
  bad "extraction counts: per-seat counts wrong"
fi

# ---- case 5: findings.jsonl shape -------------------------------------------
if [ "$(wc -l < "$TMP/board/findings.jsonl")" -eq 4 ] \
   && [ "$(grep -c '"verdict": "confirmed"' "$TMP/board/findings.jsonl")" -eq 2 ] \
   && [ "$(grep -c '"verdict": "plausible"' "$TMP/board/findings.jsonl")" -eq 2 ] \
   && [ "$(grep -c '"cluster": "C1"' "$TMP/board/findings.jsonl")" -eq 2 ] \
   && grep -q '"file": "src/auth.py", "line": 42' "$TMP/board/findings.jsonl"; then
  ok "findings.jsonl: 4 records, 2 confirmed in C1, file:line extracted"
else
  bad "findings.jsonl: wrong shape"
fi

# ---- case 6: zero-extraction seat is flagged loudly -------------------------
if grep -q "EXTRACTION FAILURE: seat-zero" "$TMP/board/summary.md"; then
  ok "caveats: zero-finding seat with substantial output flagged loudly"
else
  bad "caveats: extraction failure for seat-zero not flagged"
fi

# ---- case 7: nonzero exit from status.tsv surfaces in caveats ---------------
if grep -q "seat-beta: exited 1" "$TMP/board/summary.md"; then
  ok "caveats: seat-beta nonzero exit code surfaced"
else
  bad "caveats: seat-beta exit code missing"
fi

# ---- case 8: refuse to overwrite without --force ----------------------------
cp "$TMP/board/summary.md" "$TMP/summary.before"
rc=0
python3 "$SYN" "$TMP/board" > /dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ] && cmp -s "$TMP/summary.before" "$TMP/board/summary.md"; then
  ok "overwrite: refused without --force (exit 2, file untouched)"
else
  bad "overwrite: rc=$rc or summary.md changed"
fi
rc=0
python3 "$SYN" "$TMP/board" --force > /dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "overwrite: --force re-runs clean"
else
  bad "overwrite: --force failed with rc=$rc"
fi

# ---- case 9: usage errors exit 2 --------------------------------------------
rc=0
python3 "$SYN" > /dev/null 2>&1 || rc=$?
rc2=0
python3 "$SYN" "$TMP/no-such-dir" > /dev/null 2>&1 || rc2=$?
if [ "$rc" -eq 2 ] && [ "$rc2" -eq 2 ]; then
  ok "usage: no args and missing dir both exit 2"
else
  bad "usage: rc=$rc rc2=$rc2"
fi

# ---- case 10: --out writes elsewhere ----------------------------------------
rc=0
python3 "$SYN" "$TMP/board" --out "$TMP/synth-elsewhere" > /dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && [ -f "$TMP/synth-elsewhere/summary.md" ]; then
  ok "--out: writes into the given directory"
else
  bad "--out: rc=$rc or output missing"
fi

# ---- case 11: legacy 3-column status.tsv is tolerated -----------------------
mkdir -p "$TMP/board2"
cp "$TMP/board/seat-alpha.txt" "$TMP/board2/seat-one.txt"
printf 'seat-one\t0\t2026-10-17T00:00:03Z\n' > "$TMP/board2/status.tsv"
rc=0
python3 "$SYN" "$TMP/board2" > /dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && grep -q "legacy 3-column" "$TMP/board2/summary.md"; then
  ok "status.tsv: legacy 3-column format tolerated and noted"
else
  bad "status.tsv: legacy format rc=$rc or caveat missing"
fi

echo
echo "SCORE $pass/$((pass + fail))"
[ "$fail" -eq 0 ]
