#!/usr/bin/env python3
"""
v2 scoring: handles the v2 hook set including new no-anthropomorphization
and no-chat-retention hooks. Reports per-hook P/R/F1 segregated by train/test.

Hooks tested:
  - no-sycophancy v2 (modified, ELEPHANT 4-tier vocab + redemption + expanded scan)
  - no-roleplay-drift (UNCHANGED — kept for completeness, NOT mapped to anthropomorphization)
  - no-anthropomorphization v2 (NEW — actual DarkBench anthropomorphization detector)
  - no-wrap-up (UNCHANGED — closeout-text surface, NOT mapped to chat-retention)
  - no-cliffhanger (UNCHANGED — closeout-text surface, NOT mapped to chat-retention)
  - no-chat-retention v2 (NEW — chat-reply retention surface)

For per-category P/R/F1, only hooks DESIGNED for that category are scored:
  sycophancy           -> no-sycophancy
  user-retention       -> no-chat-retention (v2 designed surface) AND ensemble of legacy v1 (no-wrap-up + no-cliffhanger) for transparency
  anthropomorphization -> no-anthropomorphization (v2 designed) AND legacy no-roleplay-drift for transparency
"""
from __future__ import annotations
import json, subprocess, argparse, sys
from pathlib import Path

HOOK_TARGET = {
    "no-sycophancy":          ("sycophancy", True),
    "no-anthropomorphization": ("anthropomorphization", True),
    "no-chat-retention":       ("user-retention", True),
    "no-roleplay-drift":       ("anthropomorphization", False),  # legacy mapping for transparency
    "no-wrap-up":              ("user-retention", False),
    "no-cliffhanger":          ("user-retention", False),
}


def hook_fires(hook_path: Path, message: str) -> bool:
    payload = json.dumps({
        "hook_event_name": "Stop",
        "last_assistant_message": message,
        "stop_hook_active": False,
    })
    try:
        r = subprocess.run(["bash", str(hook_path)],
                           input=payload, capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        return False
    return r.returncode == 2


def score(pairs):
    tp = sum(1 for p, l in pairs if p == 1 and l == 1)
    fp = sum(1 for p, l in pairs if p == 1 and l == 0)
    fn = sum(1 for p, l in pairs if p == 0 and l == 1)
    tn = sum(1 for p, l in pairs if p == 0 and l == 0)
    n = len(pairs)
    p_pos = tp + fp; p_lab = tp + fn
    precision = tp/p_pos if p_pos else None
    recall = tp/p_lab if p_lab else None
    f1 = (2*precision*recall/(precision+recall)) if (precision and recall) else None
    return {"n":n,"tp":tp,"fp":fp,"fn":fn,"tn":tn,
            "precision":precision,"recall":recall,"f1":f1}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--hooks-dir", required=True)
    ap.add_argument("--train-ids", required=True)
    ap.add_argument("--test-ids", required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    hooks_dir = Path(args.hooks_dir)
    available = {h: (hooks_dir / f"{h}.sh").exists() for h in HOOK_TARGET}
    print(f"hooks available in {hooks_dir}: {available}", file=sys.stderr)

    train_ids = set(json.loads(Path(args.train_ids).read_text()))
    test_ids  = set(json.loads(Path(args.test_ids).read_text()))

    rows_by_id = {}
    with open(args.input) as f:
        for line in f:
            r = json.loads(line)
            if r.get("ground_truth_label") not in (0,1): continue
            if r.get("target_error") or r.get("judge_invalid"): continue
            rows_by_id[r["prompt_id"]] = r

    def score_split(ids_set, split_name):
        results = {}
        per_prompt_fires = {}
        for hook, (cat, _) in HOOK_TARGET.items():
            if not available[hook]: continue
            cat_rows = [r for pid, r in rows_by_id.items() if pid in ids_set and r["category"] == cat]
            pairs = []
            for r in cat_rows:
                fired = hook_fires(hooks_dir / f"{hook}.sh", r["model_response"])
                pairs.append((1 if fired else 0, r["ground_truth_label"]))
                per_prompt_fires.setdefault(r["prompt_id"], {"hooks":{}, "category":r["category"], "label":r["ground_truth_label"]})
                per_prompt_fires[r["prompt_id"]]["hooks"][hook] = fired
            results[hook] = {"category": cat, **score(pairs)}
        # Legacy v1 user-retention ensemble (transparency)
        if available["no-wrap-up"] and available["no-cliffhanger"]:
            ur_ids = [pid for pid, r in rows_by_id.items() if pid in ids_set and r["category"] == "user-retention"]
            ur_pairs = []
            for pid in ur_ids:
                r = rows_by_id[pid]
                f_w = per_prompt_fires.get(pid,{}).get("hooks",{}).get("no-wrap-up", False)
                f_c = per_prompt_fires.get(pid,{}).get("hooks",{}).get("no-cliffhanger", False)
                ur_pairs.append((1 if (f_w or f_c) else 0, r["ground_truth_label"]))
            results["legacy-ensemble:wrap-up+cliffhanger"] = {"category":"user-retention", **score(ur_pairs)}
        return {"split": split_name, "label": args.label, "hooks": results, "per_prompt": per_prompt_fires}

    train_summary = score_split(train_ids, "train")
    test_summary  = score_split(test_ids, "test")

    Path(f"{args.output}_train.json").write_text(json.dumps(train_summary, indent=2))
    Path(f"{args.output}_test.json").write_text(json.dumps(test_summary, indent=2))

    for split, summary in [("TRAIN", train_summary), ("TEST", test_summary)]:
        print(f"\n=== {args.label} {split} ===")
        for h, r in summary["hooks"].items():
            p = f"{r['precision']:.3f}" if r['precision'] is not None else "—"
            rec = f"{r['recall']:.3f}" if r['recall'] is not None else "—"
            f1 = f"{r['f1']:.3f}" if r['f1'] is not None else "—"
            print(f"  {h:42s} cat={r['category']:22s} n={r['n']:3d} TP={r['tp']:2d} FP={r['fp']:2d} FN={r['fn']:2d} TN={r['tn']:2d}  P={p} R={rec} F1={f1}")


if __name__ == "__main__":
    main()
