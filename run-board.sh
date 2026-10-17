#!/bin/sh
# Opposing counsel — fan one review brief out to a panel of different models in
# parallel, each told to break the artifact, each writing its findings to its own
# file. Read-only by instruction: the runner embeds a READ-ONLY clause in every
# prompt and the brief template repeats it, but opencode seats have no CLI-level
# tool restriction, and opencode auto-loads project config (opencode.json, MCP
# servers) from the reviewed repo. Treat "read-only" as policy, not mechanism;
# sandbox when reviewing repositories you do not trust (see README).
#
# Usage:
#   run-board.sh <output-dir> <repo-dir> <brief-file> [workers] [model-filter]
#
#   output-dir    where <model-slug>.txt + status.tsv land; MUST be outside repo-dir
#   repo-dir      the repository the panel reads
#   brief-file    the review brief (see brief-template.md); resolved to a
#                 physical absolute path before any seat starts, so a
#                 same-named file inside the reviewed repo can never shadow it
#   workers       parallel model runs (default 6, must be a positive integer)
#   model-filter  ripgrep pattern selecting the panel (default '^opencode-go/')
#
# Provider note: this uses `opencode` (opencode run / opencode models). To drive a
# different panel provider, swap the two `opencode` lines for that provider's
# "list models" and "run model against a dir with a file + prompt" commands — the
# workflow (one brief -> N diverse models -> N findings files -> synthesize) is
# provider-agnostic.
#
# Output contract:
#   status.tsv columns: model <TAB> exit_code <TAB> output_bytes <TAB> utc_finish
#   The runner exits 1 when: the filter matches zero seats, any seat exits
#   nonzero or returns an empty findings file, or the output dir fails the
#   safety checks. A dead board never reports success.
# Output-dir safety: the dir must sit outside the reviewed repo (findings would
# contaminate the panel), contain no symlinks, and be either empty or one this
# runner created (marker file with a known token; stale findings cleared on
# rerun). These checks defeat accidents and planted dirs; they do not make a
# hostile reviewed repo safe — see README "Reviewing untrusted repositories".
set -eu

ROOT=${1:?output directory is required}
REPO=${2:?repository directory is required}
BRIEF=${3:?review brief is required}
WORKERS=${4:-6}
FILTER=${5:-'^opencode-go/'}

for tool in opencode rg xargs; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: required tool not found: $tool" >&2; exit 1; }
done
case $WORKERS in ''|*[!0-9]*|0)
  echo "error: workers must be a positive integer" >&2; exit 1;;
esac

# The brief is validated and resolved to a physical absolute path BEFORE any
# side effect: seats run against the repo dir, so a relative brief path would
# resolve inside the REVIEWED repo, and a same-named file there would
# silently shadow the intended one.
[ -f "$BRIEF" ] || { echo "error: brief not found: $BRIEF" >&2; exit 1; }
[ -r "$BRIEF" ] || { echo "error: brief not readable: $BRIEF" >&2; exit 1; }
[ -s "$BRIEF" ] || { echo "error: brief is empty: $BRIEF (an empty brief is a dead board)" >&2; exit 1; }

# Seats first: an empty panel is a failed board, never a silent success.
SEATS=$(opencode models | rg "$FILTER" || true)
[ -n "$SEATS" ] || { echo "error: zero seats selected (filter or catalog problem); refusing to run an empty board" >&2; exit 1; }

mkdir -p "$ROOT"
rroot=$(cd "$ROOT" && pwd -P)
rrepo=$(cd "$REPO" && pwd -P)
rbrief=$(cd "$(dirname "$BRIEF")" && pwd -P)/$(basename "$BRIEF")
case "$rroot" in
  "$rrepo"|"$rrepo"/*)
    echo "error: output dir is inside the reviewed repo; seats would read each other's findings and panel independence is lost" >&2; exit 1;;
esac
if [ -L "$ROOT" ] || [ -n "$(find "$ROOT" -maxdepth 1 -type l -print -quit 2>/dev/null)" ]; then
  echo "error: $ROOT involves symlinks; refusing" >&2; exit 1
fi
MARKER="opposing-counsel-output-dir v1"
if [ -f "$ROOT/.opposing-counsel" ]; then
  [ "$(cat "$ROOT/.opposing-counsel")" = "$MARKER" ] || { echo "error: $ROOT carries a foreign .opposing-counsel marker; refusing" >&2; exit 1; }
  find "$ROOT" -maxdepth 1 -type f -name '*.txt' -delete
elif [ -n "$(ls -A "$ROOT" 2>/dev/null)" ]; then
  echo "error: $ROOT is not empty and was not created by this script; refusing to touch it" >&2
  exit 1
fi
printf "%s\n" "$MARKER" > "$ROOT/.opposing-counsel"
: > "$ROOT/status.tsv"

for f in opencode.json .opencode .claude .kimi .kimi-code AGENTS.md CLAUDE.md; do
  [ -e "$REPO/$f" ] && echo "warning: reviewed repo contains $f; agent config travels with the repo, see README 'Reviewing untrusted repositories'" >&2
done

PROMPT="Review the requested artifact now, adversarially: find where this control lies, can be bypassed, or loosens what it should tighten. Give severity, exact file:line, a concrete failing case, impact, evidence, a proposed fix, and untested limitations. Separate proven defects from hypotheses. This is a READ-ONLY review: do not edit files, do not run commands that write artifacts, no network, no credentials. Return the findings in your final response only."

# From here on, only canonical paths cross into a seat.
ROOT=$rroot; REPO=$rrepo; BRIEF=$rbrief

export ROOT REPO BRIEF PROMPT

rc=0
printf "%s\n" "$SEATS" | xargs -n1 -P"$WORKERS" sh -c '
  model="$1"
  slug=$(printf "%s" "$model" | tr -c "A-Za-z0-9._-" "-")
  msafe=$(printf "%s" "$model" | tr "\t\n" "  ")
  output="$ROOT/$slug.txt"
  opencode run --dir "$REPO" --model "$model" \
    --title "opposing-counsel-$slug" \
    --file "$BRIEF" \
    -- \
    "$PROMPT" \
    > "$output" 2>&1
  code=$?
  bytes=$(wc -c < "$output" | tr -d " ")
  printf "%s\t%s\t%s\t%s\n" "$msafe" "$code" "$bytes" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$ROOT/status.tsv"
  [ "$code" -eq 0 ] && [ -s "$output" ]
' sh || rc=$?

echo "Opposing counsel adjourned. Findings: $ROOT/*.txt  ·  status: $ROOT/status.tsv"
if [ "$rc" -ne 0 ]; then
  echo "WARNING: one or more seats failed or produced empty findings; see $ROOT/status.tsv" >&2
  exit 1
fi
echo "Next: synthesize (>=2 models agree, or 1 + reproduced = confirmed), fix, re-run invariant tests."
