#!/bin/sh
# Regression tests for the runners, no live providers: opencode/claude/kimi
# are stubbed on PATH and record what they were handed.
#
# Case 1 is the reported bug: a relative brief path (brief.md) passed from the
# user's own folder must reach the seats as THAT file, even when the reviewed
# repo carries its own brief.md. Before the fix, run-board.sh handed the
# relative path to opencode --file, which resolved it inside the repo.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd -P)
BOARD_ROOT=$(dirname "$HERE")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS $*"; }
bad() { fail=$((fail + 1)); echo "FAIL $*"; }

# ---- fixture: user's folder, the reviewed repo (with a decoy brief), stubs --
mkdir -p "$TMP/user" "$TMP/repo" "$TMP/bin"
printf "INTENDED-BRIEF-MARKER\n" > "$TMP/user/brief.md"
printf "DECOY-BRIEF-MARKER\n" > "$TMP/repo/brief.md"
printf "print('code under review')\n" > "$TMP/repo/code.py"
INTENDED=$(cd "$TMP/user" && pwd -P)/brief.md

cat > "$TMP/bin/opencode" <<'EOF'
#!/bin/sh
# Faithful stub: resolves --file against --dir, like the real opencode.
if [ "$1" = "models" ]; then
  printf "opencode-go/fake-a\nopencode-go/fake-b\n"
  exit 0
fi
if [ "$1" = "run" ]; then
  dir=.; file=
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir)  shift; dir=$1 ;;
      --file) shift; file=$1 ;;
    esac
    shift
  done
  printf "%s\n" "$file" >> "$OPENCODE_FILES_LOG"
  echo "stub findings for:"
  case "$file" in
    /*) cat "$file" ;;
    *)  cat "$dir/$file" ;;
  esac
  exit 0
fi
exit 1
EOF
chmod +x "$TMP/bin/opencode"

cat > "$TMP/bin/claude" <<'EOF'
#!/bin/sh
cat
EOF
chmod +x "$TMP/bin/claude"

cat > "$TMP/bin/kimi" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in -p) shift; printf "%s" "$1" ;; esac
  shift
done
EOF
chmod +x "$TMP/bin/kimi"

export PATH="$TMP/bin:$PATH"
export OPENCODE_FILES_LOG="$TMP/opencode-files.log"

# ---- case 1: run-board.sh, relative brief, decoy present in the repo -------
(cd "$TMP/user" && sh "$BOARD_ROOT/run-board.sh" "$TMP/out1" "$TMP/repo" \
   brief.md 2 '^opencode-go/') > /dev/null

if [ -f "$OPENCODE_FILES_LOG" ] \
   && [ "$(sort -u "$OPENCODE_FILES_LOG")" = "$INTENDED" ]; then
  ok "run-board: seats received the intended brief as an absolute path"
else
  bad "run-board: --file args were: $(cat "$OPENCODE_FILES_LOG" 2>/dev/null || echo '<none>')"
fi
if ! grep -rq "DECOY-BRIEF-MARKER" "$TMP/out1" \
   && grep -q "INTENDED-BRIEF-MARKER" "$TMP/out1/opencode-go-fake-a.txt"; then
  ok "run-board: findings carry the intended brief, never the repo decoy"
else
  bad "run-board: seat outputs show the wrong brief"
fi

# ---- case 2: run-kimi-claude-board.sh, same collision ----------------------
(cd "$TMP/user" && sh "$BOARD_ROOT/run-kimi-claude-board.sh" "$TMP/out2" \
   "$TMP/repo" brief.md 2 "" k3) > /dev/null

if grep -q "INTENDED-BRIEF-MARKER" "$TMP/out2/kimi-k3.txt" \
   && ! grep -rq "DECOY-BRIEF-MARKER" "$TMP/out2"; then
  ok "kimi-claude: seat prompt carries the intended brief, never the decoy"
else
  bad "kimi-claude: seat prompt shows the wrong brief"
fi

# ---- case 3: missing brief fails fast, before any seat runs ----------------
rm -f "$OPENCODE_FILES_LOG"
if (cd "$TMP/user" && sh "$BOARD_ROOT/run-board.sh" "$TMP/out3" "$TMP/repo" \
      nonexistent.md) > /dev/null 2>&1; then
  bad "run-board: missing brief did not fail"
elif [ -f "$OPENCODE_FILES_LOG" ]; then
  bad "run-board: a seat ran despite the missing brief"
else
  ok "run-board: missing brief exits nonzero before any seat runs"
fi

# ---- case 4: an empty brief is a dead board, refused ------------------------
: > "$TMP/user/empty.md"
if (cd "$TMP/user" && sh "$BOARD_ROOT/run-kimi-claude-board.sh" "$TMP/out4" \
      "$TMP/repo" empty.md) > /dev/null 2>&1; then
  bad "kimi-claude: empty brief did not fail"
else
  ok "kimi-claude: empty brief exits nonzero"
fi

echo
echo "SCORE $pass/$((pass + fail))"
[ "$fail" -eq 0 ]
