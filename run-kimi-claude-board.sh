#!/bin/sh
# Opposing counsel (kimi + claude) — fan one review brief out to the native Claude
# Code and Kimi Code CLIs in parallel, each told to break the artifact, each
# writing its findings to its own file.
#
# Usage:
#   run-kimi-claude-board.sh <output-dir> <repo-dir> <brief-file> [workers] [claude-models] [kimi-models]
#
#   output-dir     where <runtime>-<model>.txt + status.tsv land; MUST be outside repo-dir
#   repo-dir       the repository the panel reads
#   brief-file     the review brief (see brief-template.md); resolved to a
#                  physical absolute path before any seat starts, so a
#                  same-named file inside the reviewed repo can never shadow it
#   workers        parallel seats (default 4, must be a positive integer)
#   claude-models  comma-separated claude model ids (default "opus,sonnet,haiku";
#                  pass '' to run no claude seats)
#   kimi-models    comma-separated kimi model ids (default "kimi-code/k3";
#                  pass '' to run no kimi seats)
#
# Read-only: claude seats are restricted to read tools at the CLI level
# (--allowedTools "Read,Grep,Glob"). The kimi CLI has no tool-allowlist flag,
# so kimi seats are read-only by instruction: the prompt below forbids edits,
# writes, network and credentials. Keep that sentence if you modify this
# script. With kimi's default permission mode a read-only review needs no
# approvals; do not pass -y/--auto, they only widen what runs without asking.
# Both CLIs read project-level config from the reviewed repo (AGENTS.md,
# .claude/ hooks, .kimi* config); sandbox when reviewing repos you do not
# trust (see README).
#
# Output contract:
#   status.tsv columns: runtime/model <TAB> exit_code <TAB> output_bytes <TAB> utc_finish
#   The runner exits 1 when: zero seats are configured, any seat exits nonzero
#   or returns an empty findings file, or the output dir fails the safety
#   checks. A dead board never reports success.
# Output-dir safety: the dir must sit outside the reviewed repo, contain no
# symlinks, and be either empty or one this runner created (marker file with a
# known token; stale findings cleared on rerun).
set -eu

ROOT=${1:?output directory is required}
REPO=${2:?repository directory is required}
BRIEF=${3:?review brief is required}
WORKERS=${4:-4}
# Distinguish "unset" from "explicitly empty": empty disables a family.
if [ $# -ge 5 ]; then CLAUDE_MODELS=$5; else CLAUDE_MODELS="opus,sonnet,haiku"; fi
if [ $# -ge 6 ]; then KIMI_MODELS=$6; else KIMI_MODELS="kimi-code/k3"; fi

case $WORKERS in ''|*[!0-9]*|0)
  echo "error: workers must be a positive integer" >&2; exit 1;;
esac
# The brief is validated and resolved to a physical absolute path BEFORE any
# side effect. This runner reads it in the parent shell today, but the check
# keeps that from ever depending on which directory a seat runs in.
[ -f "$BRIEF" ] || { echo "error: brief not found: $BRIEF" >&2; exit 1; }
[ -r "$BRIEF" ] || { echo "error: brief not readable: $BRIEF" >&2; exit 1; }
[ -s "$BRIEF" ] || { echo "error: brief is empty: $BRIEF (an empty brief is a dead board)" >&2; exit 1; }
if [ -n "$CLAUDE_MODELS" ]; then
  command -v claude >/dev/null 2>&1 || { echo "error: claude CLI not found" >&2; exit 1; }
fi
if [ -n "$KIMI_MODELS" ]; then
  command -v kimi >/dev/null 2>&1 || { echo "error: kimi CLI not found" >&2; exit 1; }
fi
command -v xargs >/dev/null 2>&1 || { echo "error: required tool not found: xargs" >&2; exit 1; }

SEATS=$( {
  if [ -n "$CLAUDE_MODELS" ]; then
    for m in $(printf "%s" "$CLAUDE_MODELS" | tr ',' ' '); do printf "claude %s\n" "$m"; done
  fi
  if [ -n "$KIMI_MODELS" ]; then
    for m in $(printf "%s" "$KIMI_MODELS" | tr ',' ' '); do printf "kimi %s\n" "$m"; done
  fi
} )
[ -n "$SEATS" ] || { echo "error: zero seats configured (both families disabled); refusing to run an empty board" >&2; exit 1; }

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

# From here on, only canonical paths are read or cross into a seat.
ROOT=$rroot; REPO=$rrepo; BRIEF=$rbrief

PROMPT="$(cat "$BRIEF")

---

Review the requested artifact now, adversarially: find where this control lies, can be bypassed, or loosens what it should tighten. Give severity, exact file:line, a concrete failing case, impact, evidence, a proposed fix, and untested limitations. Separate proven defects from hypotheses. This is a READ-ONLY review: do not edit files, do not run commands that write artifacts, no network, no credentials. Return the findings in your final response only."

export ROOT REPO PROMPT

rc=0
printf "%s\n" "$SEATS" | xargs -n2 -P"$WORKERS" sh -c '
  runtime=$1 model=$2
  slug=$(printf "%s-%s" "$runtime" "$model" | tr -c "A-Za-z0-9._-" "-")
  msafe=$(printf "%s/%s" "$runtime" "$model" | tr "\t\n" "  ")
  output="$ROOT/$slug.txt"
  case "$runtime" in
    claude)
      # prompt via stdin: --allowedTools is variadic and would eat an argv prompt
      (cd "$REPO" && printf "%s" "$PROMPT" | claude -p --model "$model" \
        --allowedTools "Read,Grep,Glob") > "$output" 2>&1
      ;;
    kimi)
      (cd "$REPO" && kimi --model "$model" -p "$PROMPT") > "$output" 2>&1
      ;;
  esac
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
