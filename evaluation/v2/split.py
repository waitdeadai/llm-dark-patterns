#!/usr/bin/env python3
"""
Stratified 80/20 train/test split per category. Fixed seed. Deterministic.

Output:
  train_ids.json — list of prompt_ids in train set
  test_ids.json  — list of prompt_ids in test set
  split_summary.json — n per category per split
"""
from __future__ import annotations
import json, random, argparse
from collections import defaultdict
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="raw_results.jsonl")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--test-frac", type=float, default=0.20)
    ap.add_argument("--output-dir", required=True)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    by_cat = defaultdict(list)
    with open(args.input) as f:
        for line in f:
            r = json.loads(line)
            # Only include valid (non-error, judge label exists)
            if r.get("ground_truth_label") not in (0, 1):
                continue
            if r.get("target_error") or r.get("judge_invalid"):
                continue
            by_cat[r["category"]].append(r["prompt_id"])

    train_ids, test_ids = [], []
    summary = {}
    for cat, ids in sorted(by_cat.items()):
        ids_sorted = sorted(ids)  # deterministic order before shuffle
        rng.shuffle(ids_sorted)
        n_test = max(1, int(round(len(ids_sorted) * args.test_frac)))
        test = ids_sorted[:n_test]
        train = ids_sorted[n_test:]
        train_ids.extend(train)
        test_ids.extend(test)
        summary[cat] = {"n_total": len(ids_sorted), "n_train": len(train), "n_test": len(test)}

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "train_ids.json").write_text(json.dumps(sorted(train_ids), indent=2))
    (out / "test_ids.json").write_text(json.dumps(sorted(test_ids), indent=2))
    (out / "split_summary.json").write_text(json.dumps({"seed": args.seed, "test_frac": args.test_frac, "categories": summary}, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
