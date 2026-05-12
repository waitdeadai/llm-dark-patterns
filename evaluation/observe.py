#!/usr/bin/env python3
"""
Failure-pattern observation pass.

OBSERVATIONAL ONLY. No regex suggestions. No fix proposals.
Per spec: this script extracts up to 5 most common false-positive contexts
and 5 most common false-negative contexts per hook, with verbatim text
snippets and the relevant judge reasoning. Output is for a separate
optimization pass.
"""
from __future__ import annotations
import json, argparse, re
from collections import Counter

HOOKS = {
    "no-sycophancy":     "sycophancy",
    "no-wrap-up":        "user-retention",
    "no-cliffhanger":    "user-retention",
    "no-roleplay-drift": "anthropomorphization",
}


def normalize_opening(text: str, n: int = 80) -> str:
    """Take first n chars, strip markdown markers, normalize whitespace."""
    if not text:
        return ""
    s = text.strip()
    # strip leading markdown
    s = re.sub(r'^[*_>"#\-\s]+', '', s)
    s = re.sub(r'\s+', ' ', s)
    return s[:n]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    rows = [json.loads(l) for l in open(args.input)]
    usable = [r for r in rows if r.get("ground_truth_label") in (0, 1) and not r.get("judge_invalid")]

    md = ["# IMPROVEMENT_NOTES — observation-only failure analysis\n"]
    md.append("Strictly observational. No regex suggestions. No fix proposals.")
    md.append("Use as input to a separate optimization pass with held-out train/test split.\n")

    for hook, cat in HOOKS.items():
        rel = [r for r in usable if r["category"] == cat]
        fps = [r for r in rel if hook in r["hooks_fired"] and r["ground_truth_label"] == 0]
        fns = [r for r in rel if hook not in r["hooks_fired"] and r["ground_truth_label"] == 1]

        md.append(f"\n## {hook} (category: {cat})\n")
        md.append(f"- n in category: {len(rel)}")
        md.append(f"- false positives (hook fired, judge said no): {len(fps)}")
        md.append(f"- false negatives (hook did not fire, judge said yes): {len(fns)}\n")

        if fps:
            md.append("### False positives — first 5\n")
            for r in fps[:5]:
                opener = normalize_opening(r["model_response"], 200)
                judge_reason = (r.get("judge") or {}).get("reasoning", "")[:200]
                md.append(f"- **{r['prompt_id']}**")
                md.append(f"  - response opener: `{opener}`")
                md.append(f"  - judge reasoning: {judge_reason}")
                md.append("")

        if fns:
            md.append("### False negatives — first 5\n")
            for r in fns[:5]:
                opener = normalize_opening(r["model_response"], 200)
                judge_reason = (r.get("judge") or {}).get("reasoning", "")[:200]
                md.append(f"- **{r['prompt_id']}**")
                md.append(f"  - response opener: `{opener}`")
                md.append(f"  - judge reasoning: {judge_reason}")
                md.append("")

    with open(args.output, "w") as f:
        f.write("\n".join(md) + "\n")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
