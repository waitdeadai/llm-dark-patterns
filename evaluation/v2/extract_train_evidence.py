#!/usr/bin/env python3
"""
Extract FP/FN evidence from raw_results.jsonl, restricted to TRAIN set only.

Output train_set_evidence.md — used as input for hook iteration.
NEVER reads test set responses.
"""
from __future__ import annotations
import json, subprocess
from pathlib import Path

HOOK_CATEGORY = {
    "no-sycophancy": "sycophancy",
    "no-wrap-up": "user-retention",
    "no-cliffhanger": "user-retention",
    "no-roleplay-drift": "anthropomorphization",
}

V1_HOOKS = Path("/tmp/dark-patterns-work/llm-dark-patterns/hooks")


def hook_fires(hook_name, message):
    payload = json.dumps({
        "hook_event_name": "Stop",
        "last_assistant_message": message,
        "stop_hook_active": False,
    })
    r = subprocess.run(["bash", str(V1_HOOKS / f"{hook_name}.sh")],
                       input=payload, capture_output=True, text=True, timeout=10)
    return r.returncode == 2


def main():
    train_ids = set(json.loads(Path("/tmp/darkbench-eval/v2/train_ids.json").read_text()))

    rows = []
    with open("/tmp/dark-patterns-work/llm-dark-patterns/evaluation/raw_results.jsonl") as f:
        for line in f:
            r = json.loads(line)
            if r["prompt_id"] not in train_ids:
                continue
            if r.get("ground_truth_label") not in (0, 1):
                continue
            if r.get("target_error") or r.get("judge_invalid"):
                continue
            rows.append(r)

    md = ["# v2 hook iteration evidence — TRAIN SET ONLY\n",
          f"Source: {len(train_ids)} TRAIN ids from `/tmp/darkbench-eval/v2/train_ids.json`",
          "\n**WARNING:** Test set responses are NOT in this file. Do not look at test prompts during iteration.\n"]

    for hook, cat in HOOK_CATEGORY.items():
        cat_rows = [r for r in rows if r["category"] == cat]
        fps, fns, tps, tns = [], [], [], []
        for r in cat_rows:
            fired = hook_fires(hook, r["model_response"])
            label = r["ground_truth_label"]
            entry = (r["prompt_id"], r["model_response"], (r.get("judge") or {}).get("reasoning", ""), r["prompt_text"])
            if fired and label == 0: fps.append(entry)
            elif not fired and label == 1: fns.append(entry)
            elif fired and label == 1: tps.append(entry)
            else: tns.append(entry)

        md.append(f"\n## {hook} (category: {cat})\n")
        md.append(f"- TRAIN n={len(cat_rows)} | TP={len(tps)} FP={len(fps)} FN={len(fns)} TN={len(tns)}")

        if fps:
            md.append(f"\n### False positives ({len(fps)})\n")
            for pid, resp, reason, prompt in fps[:20]:
                md.append(f"\n**{pid}**")
                md.append(f"- prompt: `{prompt[:120]}`")
                md.append(f"- response (first 400 chars): `{resp[:400].replace(chr(10), ' ')}`")
                md.append(f"- judge says NOT a positive because: {reason[:300]}")

        if fns:
            md.append(f"\n### False negatives ({len(fns)})\n")
            for pid, resp, reason, prompt in fns[:20]:
                md.append(f"\n**{pid}**")
                md.append(f"- prompt: `{prompt[:120]}`")
                md.append(f"- response (first 400 chars): `{resp[:400].replace(chr(10), ' ')}`")
                md.append(f"- judge says IS a positive because: {reason[:300]}")

        if tps:
            md.append(f"\n### True positives ({len(tps)}, first 5 for context)\n")
            for pid, resp, reason, prompt in tps[:5]:
                md.append(f"- **{pid}**: response opener `{resp[:200].replace(chr(10), ' ')}`")

    Path("/tmp/darkbench-eval/v2/train_set_evidence.md").write_text("\n".join(md))
    print(f"wrote train_set_evidence.md ({sum(len(open('/tmp/darkbench-eval/v2/train_set_evidence.md').readlines()))} lines)")


if __name__ == "__main__":
    main()
