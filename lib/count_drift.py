#!/usr/bin/env python3
"""count_drift.py — deterministic count-vs-enumeration self-consistency gate.

Detects when a count stated in prose contradicts the artifact's OWN content:
  R1  fraction/percentage arithmetic self-check ("9/10 = 80%" -> wrong, 90%)
  R2  "N of M" bound check (N > M is impossible)
  R3  headline count vs a single immediately-following enumeration
      ("six findings:" then a 5-item list)

Design: high precision, abstain-on-ambiguity. This is a BLOCKING gate, so it
fires only on unambiguous, self-contained mismatches and otherwise passes.
Counting lives in deterministic code (LLMs are unreliable at counting and their
errors are self-consistent; see evaluation/v6/SPEC.md source ledger).

Pure standard library — no third-party dependencies.

Usage:
  echo "<message text>" | python3 lib/count_drift.py
  python3 lib/count_drift.py --text "..."   |   --file path
Output: a single JSON object on stdout:
  {"decision": "block"|"pass", "rule": "<id>", "evidence": "<short>"}
Always exits 0; the bash hook maps decision=block -> exit 2.
"""

import json
import re
import sys

# ---------------------------------------------------------------------------
# Number parsing (digits + spelled-out words, stdlib only).
# ---------------------------------------------------------------------------
_UNITS = {
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
    "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
    "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
}
_TENS = {
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
    "seventy": 70, "eighty": 80, "ninety": 90,
}
_ORDINALS = {
    "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
    "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
    "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
    "fifteenth": 15,
}
# Deliberately small special-case lexicon. "a dozen" is unambiguous; the vague
# words map to None so callers ABSTAIN rather than guess a cardinality.
_SPECIAL = {"dozen": 12}
_VAGUE = {"a few", "several", "a couple", "a handful", "some", "many", "various"}


def word_to_int(phrase):
    """Return an int for a spelled-out cardinal/ordinal phrase, else None.

    Handles 0-99, "N hundred", "N thousand", hyphenated tens ("twenty-five"),
    "a dozen", and ordinals. Returns None for anything ambiguous/unsupported so
    the caller abstains.
    """
    s = phrase.strip().lower().replace("-", " ")
    if s in _VAGUE:
        return None
    if s in _ORDINALS:
        return _ORDINALS[s]
    if s in ("a dozen", "one dozen", "dozen"):
        return 12
    tokens = [t for t in re.split(r"\s+", s) if t and t not in ("and", "a", "an")]
    if not tokens:
        return None
    total = 0
    current = 0
    saw = False
    for tok in tokens:
        if tok in _UNITS:
            current += _UNITS[tok]
            saw = True
        elif tok in _TENS:
            current += _TENS[tok]
            saw = True
        elif tok == "hundred":
            current = (current or 1) * 100
            saw = True
        elif tok == "thousand":
            total += (current or 1) * 1000
            current = 0
            saw = True
        elif tok in _SPECIAL:
            current += _SPECIAL[tok]
            saw = True
        else:
            return None  # unknown token -> abstain
    if not saw:
        return None
    return total + current


def parse_count_token(tok):
    """Parse a single count token (digits or one spelled word/phrase) -> int|None."""
    tok = tok.strip()
    if re.fullmatch(r"\d{1,4}", tok):
        return int(tok)
    return word_to_int(tok)


# A regex alternation matching a single number word (incl. hyphenated tens) or digits.
_NUMWORD = (
    r"(?:\d{1,4}|"
    r"(?:twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[ -](?:one|two|three|four|five|six|seven|eight|nine))?|"
    r"zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|"
    r"fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|"
    r"a dozen|dozen)"
)

_APPROX = re.compile(r"(~|≈|≅|\bapprox(?:imately)?\b|\babout\b|\broughly\b|\bor so\b)", re.I)


# ---------------------------------------------------------------------------
# R1 — fraction / percentage arithmetic self-check.
# ---------------------------------------------------------------------------
_FRAC_PCT = re.compile(
    r"(?P<num>\d{1,6})\s*/\s*(?P<den>\d{1,6})\s*"
    r"(?:=|\(|\bis\b|,|\s)\s*~?\s*(?P<pct>\d{1,3}(?:\.\d+)?)\s*%"
)


def check_r1(text):
    """Flag 'A/B = P%' when P does not match A/B within rounding tolerance."""
    for m in _FRAC_PCT.finditer(text):
        num = int(m.group("num"))
        den = int(m.group("den"))
        if den == 0:
            continue
        pct_str = m.group("pct")
        stated = float(pct_str)
        # Abstain on explicit approximation markers right before the percent.
        head = text[max(0, m.start()): m.start("pct")]
        if _APPROX.search(head):
            continue
        computed = num / den * 100.0
        # Half-ULP rounding tolerance at the stated decimal precision, +epsilon.
        decimals = len(pct_str.split(".")[1]) if "." in pct_str else 0
        tol = 0.5 * (10 ** (-decimals)) + 1e-9
        if abs(computed - stated) > tol:
            return {
                "decision": "block",
                "rule": "count_drift.fraction_percent_mismatch",
                "evidence": "%s = %s%% but %d/%d = %.2f%%" % (
                    m.group("num") + "/" + m.group("den"), pct_str, num, den, computed),
            }
    return None


# ---------------------------------------------------------------------------
# R2 — "N of M" bound check.
# ---------------------------------------------------------------------------
_N_OF_M = re.compile(
    r"\b(?P<n>%s)\s+of\s+(?:the\s+|those\s+|these\s+|all\s+)?(?P<m>%s)\b" % (_NUMWORD, _NUMWORD),
    re.I,
)


def check_r2(text):
    """Flag 'N of M' where N > M (impossible)."""
    for m in _N_OF_M.finditer(text):
        n = parse_count_token(m.group("n"))
        mm = parse_count_token(m.group("m"))
        if n is None or mm is None:
            continue
        if n > mm:
            return {
                "decision": "block",
                "rule": "count_drift.n_of_m_exceeds",
                "evidence": "'%s of %s' — %d exceeds %d" % (
                    m.group("n"), m.group("m"), n, mm),
            }
    return None


# ---------------------------------------------------------------------------
# Enumeration parsing (markdown lists + tables), depth-aware, stdlib only.
# ---------------------------------------------------------------------------
_LIST_RE = re.compile(r"^(?P<indent>[ \t]*)(?:[-*+]|\d{1,3}[.)])\s+\S")
_HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s")

# Label words: when a number directly follows one of these it is an index/ID,
# not a count (e.g. "Section 3", "Step 2", "v4", "Figure 1"). Abstain.
_LABEL_BEFORE = re.compile(
    r"(?:section|step|part|phase|chapter|figure|fig|table|appendix|item|version|"
    r"v|level|tier|round|pass|day|group|page|line|note|task|issue|pr|#)\s*$",
    re.I,
)


def _is_table_sep(line):
    """A markdown table separator row, for any column count (1+)."""
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    cells = [c for c in cells if c != ""]
    return bool(cells) and all(re.fullmatch(r":?-{2,}:?", c) for c in cells)


def find_enumerations(lines):
    """Return contiguous enumeration blocks as dicts:
    {kind, count, start, end}  (count = TOP-LEVEL items / table data rows).
    Conservative: a blank line or a heading ends a block.
    """
    blocks = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        m = _LIST_RE.match(line)
        if m:
            start = i
            indents = []
            j = i
            while j < n:
                lm = _LIST_RE.match(lines[j])
                if lm:
                    indents.append(len(lm.group("indent").replace("\t", "    ")))
                    j += 1
                elif lines[j].strip() == "":
                    break
                elif _HEADING_RE.match(lines[j]):
                    break
                else:
                    # continuation / lazy line within the list: keep going
                    j += 1
            base = min(indents) if indents else 0
            top = 0
            k = start
            while k < j:
                lm = _LIST_RE.match(lines[k])
                if lm and len(lm.group("indent").replace("\t", "    ")) == base:
                    top += 1
                k += 1
            blocks.append({"kind": "list", "count": top, "start": start, "end": j})
            i = j
            continue
        # table: contiguous lines containing a pipe, with a separator row
        if "|" in line and line.strip():
            start = i
            j = i
            while j < n and "|" in lines[j] and lines[j].strip():
                j += 1
            tbl = lines[start:j]
            sep_idx = next((idx for idx, l in enumerate(tbl) if _is_table_sep(l)), None)
            if sep_idx is not None and sep_idx >= 1:
                data_rows = len(tbl) - (sep_idx + 1)
                if data_rows >= 1:
                    blocks.append({"kind": "table", "count": data_rows,
                                   "start": start, "end": j})
            i = max(j, i + 1)
            continue
        i += 1
    return blocks


# A count-claim that acts as a lead-in to a list: "<num> <noun>:" near line end,
# or a heading containing "<num> <noun>".
_LEADIN_RE = re.compile(
    r"(?P<num>%s)\s+(?P<noun>[A-Za-z][A-Za-z-]{2,30})\b[^\n]{0,40}?:\s*$" % _NUMWORD,
    re.I,
)
# Number must be the FIRST token of the heading content ("## 3 Key Findings"),
# not buried after a label ("## Section 3 notes" -> abstain).
_HEADING_COUNT_RE = re.compile(
    r"^\s{0,3}#{1,6}\s+(?P<num>%s)\s+(?P<noun>[A-Za-z][A-Za-z-]{2,30})\b" % _NUMWORD,
    re.I,
)


def check_r3(text, lines, enumerations):
    """Flag a lead-in count claim immediately followed by exactly one enumeration
    whose top-level count differs. Abstain on any ambiguity."""
    for idx, line in enumerate(lines):
        claim = None
        is_heading = False
        m = _LEADIN_RE.search(line)
        if m:
            claim = m
        else:
            hm = _HEADING_COUNT_RE.match(line)
            if hm:
                claim = hm
                is_heading = True
        if not claim:
            continue
        # Lead-in-only guards (a heading already requires the number to be the
        # first content token, so no label or second-number can precede it).
        if not is_heading:
            # Abstain if the number is an index/ID after a label word ("Step 3 tasks:").
            if _LABEL_BEFORE.search(line[:claim.start("num")]):
                continue
            # Abstain if a SECOND number sits between the noun and the lead-in colon
            # ("3 reasons: the top 2 are:" — the real enumerand is 2, not 3).
            if re.search(_NUMWORD, line[claim.end("noun"):claim.end()], re.I):
                continue
        stated = parse_count_token(claim.group("num"))
        if stated is None or stated == 0:
            continue  # abstain on vague / zero
        # Scope: from just after this line to the next heading/claim boundary.
        scope_end = len(lines)
        for k in range(idx + 1, len(lines)):
            if _HEADING_RE.match(lines[k]):
                scope_end = k
                break
        # Candidate enumerations that START within (idx, scope_end) and within a
        # small adjacency gap of the claim (<=2 non-empty lines before the block).
        cands = []
        for b in enumerations:
            if idx < b["start"] < scope_end:
                gap_lines = [l for l in lines[idx + 1:b["start"]] if l.strip()]
                if len(gap_lines) <= 2:
                    cands.append(b)
        # ABSTAIN unless exactly one adjacent candidate enumeration.
        if len(cands) != 1:
            continue
        actual = cands[0]["count"]
        if actual >= 1 and actual != stated:
            return {
                "decision": "block",
                "rule": "count_drift.headline_enumeration_mismatch",
                "evidence": "claim '%s %s' but the %s lists %d top-level item(s)" % (
                    claim.group("num"), claim.group("noun"),
                    cands[0]["kind"], actual),
            }
    return None


def analyze(text):
    lines = text.splitlines()
    enums = find_enumerations(lines)
    for check in (lambda: check_r1(text),
                  lambda: check_r2(text),
                  lambda: check_r3(text, lines, enums)):
        res = check()
        if res:
            return res
    return {"decision": "pass", "rule": "", "evidence": ""}


def _read_input(argv):
    if "--text" in argv:
        return argv[argv.index("--text") + 1]
    if "--file" in argv:
        with open(argv[argv.index("--file") + 1], "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    return sys.stdin.read()


def main():
    try:
        text = _read_input(sys.argv[1:])
    except Exception:
        print(json.dumps({"decision": "pass", "rule": "", "evidence": ""}))
        return 0
    if not text or not text.strip():
        print(json.dumps({"decision": "pass", "rule": "", "evidence": ""}))
        return 0
    try:
        result = analyze(text)
    except Exception:
        # Fail-open: never break a session on a parser bug.
        result = {"decision": "pass", "rule": "", "evidence": ""}
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
