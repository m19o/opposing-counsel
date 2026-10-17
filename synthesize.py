#!/usr/bin/env python3
"""Merge opposing-counsel seat outputs into one ranked findings list.

Step 3 of the board workflow. Reads every <seat>.txt in a board output
directory, extracts findings with deliberately simple heuristics (the
transcripts are full agent logs: thinking narration, tool echoes,
directory listings, and only then findings), clusters findings that look
like the same issue across seats, and writes findings.jsonl plus
summary.md. Heuristics over free-form text miss things; the caveats
section of the summary is part of the deliverable, not boilerplate.
"""

import argparse
import json
import os
import re
import sys

QUOTE_MAX = 200           # chars kept from the first evidence snippet
TINY_BYTES = 1024         # seat outputs below this look like failed runs
SUBSTANTIAL_BYTES = 4096  # zero findings above this size = extraction failure
LINE_BUCKET_WIDTH = 10    # same-basename lines sharing line // 10 cluster
JACCARD_MIN = 0.6         # title-token Jaccard needed to merge two clusters

SEVERITIES = ("critical", "high", "medium", "low")
SEV_RANK = {name: rank for rank, name in enumerate(SEVERITIES)}
SEV_RANK["unknown"] = len(SEVERITIES)

SEV_RE = re.compile(r"\b(critical|high|medium|low)\b", re.IGNORECASE)
SEV_PREFIX_RE = re.compile(
    r"^(?:critical|high|medium|low)(?:\s*/\s*(?:critical|high|medium|low))?"
    r"\s*[:\u2013\u2014.\-]\s*",
    re.IGNORECASE,
)

# Finding-heading shapes seen in real seat transcripts. First match wins.
HEADING_RES = (
    # ## Finding: ...   or   ## Finding 3: ...
    re.compile(r"^\s*#{2,6}\s+Finding(?:\s+\d+)?\s*[:\u2014\-]\s*(?P<title>.+?)\s*#*\s*$", re.IGNORECASE),
    # ### 1. Title   (numbered markdown heading)
    re.compile(r"^\s*#{2,6}\s+\d+[.)]\s+(?P<title>.+?)\s*#*\s*$"),
    # **Finding 2 (HIGH): Title**
    re.compile(r"^\s*\*\*Finding\s+\d+(?:\s*\([^)]*\))?\s*[:\u2014\-]\s*(?P<title>.+?)(?:\*\*)?\s*$", re.IGNORECASE),
    # **S2. Title**   or   **1. Title**   (bold-wrapped label)
    re.compile(r"^\s*\*\*[A-Za-z]{0,3}\d+[.)]\s+(?P<title>.+?)\*\*"),
    # 1. **Title**   (numbered list item with a bold title)
    re.compile(r"^\s*\d+[.)]\s+\*\*(?P<title>.+?)\*\*"),
)

FILE_COLON_RE = re.compile(r"([\w][\w./-]*\.py):(\d+)(?:\s*-\s*\d+)?")
FILE_WORD_RE = re.compile(r"([\w][\w./-]*\.py)\s+lines?\s+(\d+)(?:\s*-\s*\d+)?", re.IGNORECASE)
FENCE_RE = re.compile(r"^\s*```")
QUOTE_LINE_RE = re.compile(r"^\s*>")
INLINE_CODE_RE = re.compile(r"`([^`]{12,})`")
BULLET_RE = re.compile(r"^\s*•")
TOKEN_RE = re.compile(r"[a-z0-9]+")

STOPWORDS = {
    "the", "a", "an", "and", "or", "of", "to", "in", "is", "on", "for",
    "with", "by", "at", "from", "that", "this", "it", "as", "be", "are",
    "was", "were", "not", "no", "so", "if", "its", "via", "per", "into",
    "critical", "high", "medium", "low", "proven", "finding", "severity",
}


def clean_title(title):
    """Strip a leading severity tag from a heading title."""
    return SEV_PREFIX_RE.sub("", title.strip()).strip()


def detect_heading(line):
    """Return (title, raw_heading) if the line looks like a finding heading."""
    for pat in HEADING_RES:
        m = pat.match(line)
        if m:
            title = clean_title(m.group("title"))
            if title:
                return title, line.strip()
    return None


def severity_near(heading, block):
    """First severity keyword in the heading, else in the first block lines."""
    m = SEV_RE.search(heading)
    if m:
        return m.group(1).lower()
    for line in block[:3]:
        m = SEV_RE.search(line)
        if m:
            return m.group(1).lower()
    return "unknown"


def file_ref(heading, block):
    """First path.py:NN reference in the heading, else in the block."""
    for text in [heading] + block:
        hits = [m for m in (FILE_COLON_RE.search(text), FILE_WORD_RE.search(text)) if m]
        if hits:
            m = min(hits, key=lambda h: h.start())
            path = m.group(1)
            if path.startswith("./"):
                path = path[2:]
            return path, int(m.group(2))
    return None, None


def trim_quote(text):
    return re.sub(r"\s+", " ", text).strip()[:QUOTE_MAX]


def extract_quote(block, heading_indent):
    """First evidence snippet: fenced, blockquoted, indented, or inline code."""
    i = 0
    while i < len(block):
        if FENCE_RE.match(block[i]):
            j = i + 1
            while j < len(block) and not FENCE_RE.match(block[j]):
                j += 1
            body = "\n".join(block[i + 1:j]).strip()
            if body:
                return trim_quote(body)
            i = j + 1
        else:
            i += 1
    quoted = []
    for line in block:
        if QUOTE_LINE_RE.match(line):
            quoted.append(line)
        elif quoted:
            break
    if quoted:
        return trim_quote("\n".join(quoted))
    indented = []
    for line in block:
        if not line.strip():
            if indented:
                break
            continue
        indent = len(line) - len(line.lstrip())
        if indent >= heading_indent + 4 and not FENCE_RE.match(line):
            indented.append(line)
        elif indented:
            break
    if indented:
        return trim_quote("\n".join(indented))
    for line in block:
        m = INLINE_CODE_RE.search(line)
        if m:
            return trim_quote(m.group(1))
    return None


def parse_seat(seat, text):
    """Extract finding records from one seat transcript."""
    lines = text.splitlines()
    headings = []
    for i, line in enumerate(lines):
        hit = detect_heading(line)
        if hit:
            headings.append((i,) + hit)
    findings = []
    for pos, (i, title, raw) in enumerate(headings):
        end = headings[pos + 1][0] if pos + 1 < len(headings) else len(lines)
        block = []
        for line in lines[i + 1:end]:
            if BULLET_RE.match(line):
                break
            block.append(line)
        heading_indent = len(lines[i]) - len(lines[i].lstrip())
        fpath, fline = file_ref(raw, block)
        findings.append({
            "seat": seat,
            "title": title,
            "severity": severity_near(raw, block),
            "file": fpath,
            "line": fline,
            "quote": extract_quote(block, heading_indent),
            "raw_heading": raw,
        })
    return findings


class DSU:
    """Union-find; union attaches the second root under the first."""

    def __init__(self, n):
        self.parent = list(range(n))

    def find(self, x):
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[rb] = ra


def tokens(title):
    return {t for t in TOKEN_RE.findall(title.lower())
            if len(t) >= 2 and t not in STOPWORDS}


def cluster_findings(findings):
    """Cluster by (file basename, line bucket), then merge by title Jaccard."""
    dsu = DSU(len(findings))
    buckets = {}
    for i, f in enumerate(findings):
        if f["file"] and f["line"] is not None:
            key = (os.path.basename(f["file"]), f["line"] // LINE_BUCKET_WIDTH)
            buckets.setdefault(key, []).append(i)
    for ids in buckets.values():
        for other in ids[1:]:
            dsu.union(ids[0], other)
    groups = {}
    for i in range(len(findings)):
        groups.setdefault(dsu.find(i), []).append(i)
    clusters = sorted(groups.values(), key=lambda g: g[0])
    toksets = {}
    for g in clusters:
        toks = set()
        for i in g:
            toks |= tokens(findings[i]["title"])
        toksets[dsu.find(g[0])] = toks
    for a in range(len(clusters)):
        for b in range(a + 1, len(clusters)):
            ra, rb = dsu.find(clusters[a][0]), dsu.find(clusters[b][0])
            if ra == rb:
                continue
            ta, tb = toksets.get(ra, set()), toksets.get(rb, set())
            both = ta | tb
            if both and len(ta & tb) / len(both) >= JACCARD_MIN:
                dsu.union(ra, rb)
                toksets[dsu.find(ra)] = both
                toksets.pop(rb, None)
    groups = {}
    for i in range(len(findings)):
        groups.setdefault(dsu.find(i), []).append(i)
    clusters = []
    for members in groups.values():
        members.sort()
        rep_i = min(members, key=lambda i: (SEV_RANK[findings[i]["severity"]],
                                            findings[i]["seat"],
                                            findings[i]["title"]))
        rep = findings[rep_i]
        fpath, fline = rep["file"], rep["line"]
        if fpath is None:
            rest = sorted(members, key=lambda i: (findings[i]["seat"],
                                                  findings[i]["title"]))
            for i in rest:
                if findings[i]["file"]:
                    fpath, fline = findings[i]["file"], findings[i]["line"]
                    break
        clusters.append({
            "members": members,
            "seats": sorted({findings[i]["seat"] for i in members}),
            "severity": rep["severity"],
            "title": rep["title"],
            "file": fpath,
            "line": fline,
        })
    clusters.sort(key=lambda c: (-len(c["members"]), SEV_RANK[c["severity"]],
                                 c["title"].lower()))
    for rank, c in enumerate(clusters, 1):
        c["id"] = f"C{rank}"
        c["verdict"] = "confirmed" if len(c["seats"]) >= 2 else "plausible"
        for i in c["members"]:
            findings[i]["cluster"] = c["id"]
            findings[i]["verdict"] = c["verdict"]
    return clusters


def read_status(path):
    """Parse status.tsv, tolerating the 3-column legacy format.

    Returns (rows, legacy, malformed) where rows maps model to
    (exit_code, output_bytes or None); rows is None when absent.
    """
    rows, legacy, malformed = {}, False, 0
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if not line.strip():
                    continue
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 4:
                    model, code, nbytes, _ts = parts
                elif len(parts) == 3:
                    model, code, _ts = parts
                    nbytes = None
                    legacy = True
                else:
                    malformed += 1
                    continue
                try:
                    rows[model] = (int(code), int(nbytes) if nbytes else None)
                except ValueError:
                    malformed += 1
    except FileNotFoundError:
        return None, legacy, malformed
    return rows, legacy, malformed


def md_cell(text):
    text = re.sub(r"\s+", " ", text).replace("|", "\\|").strip()
    return text[:107] + "..." if len(text) > 110 else text


def build_caveats(seat_rows, status_rows, legacy, malformed_rows):
    """The honest-limits section; extraction failures come first and loud."""
    caveats = []
    for seat, count, nbytes in seat_rows:
        if count == 0 and nbytes >= SUBSTANTIAL_BYTES:
            caveats.append(
                f"EXTRACTION FAILURE: {seat} produced {nbytes} bytes of output "
                "but zero extractable findings. The parser found no heading it "
                "recognizes in that transcript; read the seat output by hand "
                "before trusting this report.")
    if status_rows is None:
        caveats.append("No status.tsv found; seat exit codes are unknown.")
    else:
        if legacy:
            caveats.append(
                "status.tsv uses the legacy 3-column format "
                "(model, exit_code, timestamp); output_bytes was unavailable.")
        for model in sorted(status_rows):
            code, _nbytes = status_rows[model]
            if code != 0:
                caveats.append(
                    f"{model}: exited {code} per status.tsv; treat its output "
                    "as truncated or failed.")
        for seat, _count, nbytes in seat_rows:
            entry = status_rows.get(seat)
            size = entry[1] if entry and entry[1] is not None else nbytes
            if size is not None and size < TINY_BYTES:
                caveats.append(
                    f"{seat}: tiny output ({size} bytes < {TINY_BYTES}); "
                    "likely a failed seat.")
        for model in sorted(status_rows):
            if not any(seat == model for seat, _c, _n in seat_rows):
                caveats.append(
                    f"{model}: listed in status.tsv but has no .txt output file.")
        if malformed_rows:
            caveats.append(f"status.tsv: skipped {malformed_rows} malformed row(s).")
    caveats.append(
        "This report is regex heuristics over free-form agent transcripts. "
        "Headings that are not findings get extracted; findings stated in bare "
        "prose get missed; a seat that restates one finding three times counts "
        "as three extractions.")
    caveats.append(
        "Verdicts count distinct seat names only: a seat repeating itself never "
        "confirms a finding, but two seats from one vendor may not be "
        "independent reviewers.")
    caveats.append(
        f"Clustering merges on (file basename, line // {LINE_BUCKET_WIDTH}), "
        f"then merges clusters whose title-token sets reach Jaccard >= "
        f"{JACCARD_MIN}. Lines just across a bucket edge (69 vs 71) do not "
        "merge; differently worded duplicates stay separate; distinct defects "
        "citing nearby lines merge. Confirmed means independent agreement, not "
        "proof: reproduce against the code before fixing.")
    caveats.append(
        "Severity is the first severity keyword at or near the heading "
        "(section-level context is not inherited), so 'unknown' is common. "
        f"Quotes are the first fenced, blockquoted, indented, or inline-code "
        f"snippet in the finding block, trimmed to {QUOTE_MAX} chars and not "
        "verified against the code.")
    return caveats


def render_summary(board, seat_rows, findings, clusters,
                   status_rows, legacy, malformed_rows):
    confirmed = [c for c in clusters if c["verdict"] == "confirmed"]
    plausible = [c for c in clusters if c["verdict"] == "plausible"]
    out = [f"# Synthesis: {os.path.basename(os.path.abspath(board))}", ""]
    out.append(f"- Seats: {len(seat_rows)}")
    out.append(f"- Findings extracted: {len(findings)}")
    out.append(f"- Clusters: {len(clusters)}")
    out.append(f"- Confirmed clusters: {len(confirmed)}")
    out.append(f"- Plausible clusters: {len(plausible)}")
    out.append("")
    for heading, group in (("## Confirmed findings (2 or more seats)", confirmed),
                           ("## Plausible findings (1 seat)", plausible)):
        out.append(heading)
        out.append("")
        if not group:
            out.append("None.")
        else:
            out.append("| Cluster | Seats | Severity | File:line | Title |")
            out.append("|---|---|---|---|---|")
            for c in group:
                loc = f"{c['file']}:{c['line']}" if c["file"] else "-"
                out.append("| {} | {} | {} | {} | {} |".format(
                    c["id"], ", ".join(c["seats"]), c["severity"], loc,
                    md_cell(c["title"])))
        out.append("")
    out.append("## Per-seat extraction")
    out.append("")
    out.append("| Seat | Findings | Bytes |")
    out.append("|---|---|---|")
    for seat, count, nbytes in seat_rows:
        out.append(f"| {seat} | {count} | {nbytes} |")
    out.append("")
    out.append("## Caveats")
    out.append("")
    for caveat in build_caveats(seat_rows, status_rows, legacy, malformed_rows):
        out.append(f"- {caveat}")
    out.append("")
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="synthesize.py",
        description="Merge board seat outputs into one ranked findings list.")
    ap.add_argument("board_dir",
                    help="directory with <seat>.txt outputs (and status.tsv)")
    ap.add_argument("--out", default=None,
                    help="output directory for findings.jsonl and summary.md "
                         "(default: the board dir)")
    ap.add_argument("--force", action="store_true",
                    help="overwrite an existing summary.md")
    args = ap.parse_args(argv)

    board = args.board_dir
    if not os.path.isdir(board):
        print(f"synthesize: not a directory: {board}", file=sys.stderr)
        return 2
    out_dir = args.out or board
    summary_path = os.path.join(out_dir, "summary.md")
    jsonl_path = os.path.join(out_dir, "findings.jsonl")
    if os.path.exists(summary_path) and not args.force:
        print(f"synthesize: {summary_path} exists; pass --force to overwrite",
              file=sys.stderr)
        return 2
    seat_files = sorted(f for f in os.listdir(board) if f.endswith(".txt"))
    if not seat_files:
        print(f"synthesize: no seat .txt files in {board}", file=sys.stderr)
        return 2
    os.makedirs(out_dir, exist_ok=True)

    findings = []
    seat_rows = []
    for fname in seat_files:
        seat = fname[:-4]
        path = os.path.join(board, fname)
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        found = parse_seat(seat, text)
        findings.extend(found)
        seat_rows.append((seat, len(found), os.path.getsize(path)))
        print(f"{seat}: {len(found)} findings")

    status_rows, legacy, malformed = read_status(
        os.path.join(board, "status.tsv"))
    clusters = cluster_findings(findings)

    with open(jsonl_path, "w", encoding="utf-8") as fh:
        for c in clusters:
            for i in sorted(c["members"],
                            key=lambda i: (findings[i]["seat"], i)):
                f = findings[i]
                fh.write(json.dumps({
                    "seat": f["seat"],
                    "title": f["title"],
                    "severity": f["severity"],
                    "file": f["file"],
                    "line": f["line"],
                    "quote": f["quote"],
                    "raw_heading": f["raw_heading"],
                    "cluster": f["cluster"],
                    "verdict": f["verdict"],
                }, ensure_ascii=False) + "\n")

    summary = render_summary(board, seat_rows, findings, clusters,
                             status_rows, legacy, malformed)
    with open(summary_path, "w", encoding="utf-8") as fh:
        fh.write(summary)

    n_conf = sum(1 for c in clusters if c["verdict"] == "confirmed")
    print(f"{len(findings)} findings, {len(clusters)} clusters "
          f"({n_conf} confirmed, {len(clusters) - n_conf} plausible)")
    print(f"wrote {jsonl_path} and {summary_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
