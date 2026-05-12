#!/usr/bin/env python3
"""
Fill the RESULTS.template.md placeholders with computed metrics + auto-derived
findings. Pure templating — no eval execution.
"""
from __future__ import annotations
import json, argparse, datetime
from pathlib import Path

HOOK_CATEGORY = {
    "no-sycophancy": "sycophancy",
    "no-wrap-up": "user-retention",
    "no-cliffhanger": "user-retention",
    "no-roleplay-drift": "anthropomorphization",
}


def fmt(x, nd=3):
    if x is None: return "—"
    if isinstance(x, float): return f"{x:.{nd}f}"
    return str(x)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", required=True)
    ap.add_argument("--scored-json", required=True)
    ap.add_argument("--raw-jsonl", required=True)
    ap.add_argument("--hook-commit", required=True)
    ap.add_argument("--repo-url", default="https://github.com/waitdeadai/llm-dark-patterns")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    summary = json.loads(Path(args.scored_json).read_text())
    raw_count = sum(1 for _ in open(args.raw_jsonl))
    today = datetime.date.today().isoformat()

    # Prevalence table
    pv = ["| Category | n (usable) | label-positive count | label-positive rate |",
          "|---|---|---|---|"]
    for cat, s in sorted(summary["categories"].items()):
        pv.append(f"| {cat} | {s['n']} | {s['label_positive_count']} | {fmt(s['label_positive_rate'])} |")

    # Hooks table
    ht = ["| Hook | Category | n | TP | FP | FN | TN | Precision | Recall | F1 |",
          "|---|---|---|---|---|---|---|---|---|---|"]
    for hook, r in summary["hooks"].items():
        ht.append(f"| {hook} | {r['category']} | {r['n']} | {r['tp']} | {r['fp']} | {r['fn']} | {r['tn']} | {fmt(r['precision'])} | {fmt(r['recall'])} | {fmt(r['f1'])} |")

    # Findings: auto-derived prose paragraphs based on the numbers
    findings = []
    for hook, r in summary["hooks"].items():
        if hook == "user-retention-ensemble": continue
        n_pos = r["tp"] + r["fn"]
        if n_pos == 0:
            findings.append(f"- **{hook}** had 0 overseer-positive prompts in its target category sample (n={r['n']}). The target model did not exhibit the pattern on the in-scope prompts at all, so precision and recall are undefined. A larger or different sample would be required to characterize hook recall on this category.")
        else:
            findings.append(f"- **{hook}**: precision {fmt(r['precision'])}, recall {fmt(r['recall'])}, F1 {fmt(r['f1'])} on {r['n']} {r['category']} prompts ({n_pos} overseer-positive). TP={r['tp']}, FP={r['fp']}, FN={r['fn']}, TN={r['tn']}.")
    ens = summary["hooks"].get("user-retention-ensemble")
    if ens:
        findings.append(f"- **user-retention ensemble (no-wrap-up OR no-cliffhanger)**: precision {fmt(ens['precision'])}, recall {fmt(ens['recall'])}, F1 {fmt(ens['f1'])} on {ens['n']} user-retention prompts.")

    findings_md = "\n".join(findings)

    t = Path(args.template).read_text()
    t = t.replace("<!-- TABLE_PREVALENCE -->", "\n".join(pv))
    t = t.replace("<!-- TABLE_HOOKS -->", "\n".join(ht))
    t = t.replace("<!-- FINDINGS -->", findings_md)
    t = t.replace("<HASH>", args.hook_commit)
    t = t.replace("<REPO_URL>", args.repo_url)
    t = t.replace("<YYYY-MM-DD>", today)
    t = t.replace("<local_time>", datetime.datetime.now().isoformat(timespec="seconds"))

    Path(args.output).write_text(t)
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
