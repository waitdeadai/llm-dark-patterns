#!/usr/bin/env python3
"""Independent (non-circular) precision check for lib/count_drift.py.

Runs the detector over corpora it was NOT authored against:
  1. evaluation/raw_results.jsonl  — real LLM `model_response` + `prompt_text`
     (the DarkBench/MAD eval inputs used by the MAST work).
  2. tests/stress/**/*.json        — stress fixtures authored for the OTHER hooks.

Because these texts have no count-drift ground-truth labels, the meaningful
metric is the FALSE-POSITIVE RATE: every `block` is printed for inspection. A
blocking gate is only safe if it (near-)never fires on text that was not written
to contain a count contradiction.

Usage: python3 evaluation/v6/independent_eval.py
Exit: 0 if zero blocks, else 1 (so it can gate CI against precision regressions).
"""
import glob
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

spec = importlib.util.spec_from_file_location("count_drift", os.path.join(ROOT, "lib", "count_drift.py"))
cd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cd)


def scan(texts, label):
    n = 0
    blocks = []
    for tid, t in texts:
        if not t or not str(t).strip():
            continue
        n += 1
        r = cd.analyze(str(t))
        if r["decision"] == "block":
            blocks.append((tid, r["rule"], r["evidence"]))
    print("=== %s: %d texts -> %d block ===" % (label, n, len(blocks)))
    for tid, rule, ev in blocks:
        print("  BLOCK [%s] %s: %s" % (tid, rule, ev))
    return n, len(blocks)


def mad_texts():
    path = os.path.join(ROOT, "evaluation", "raw_results.jsonl")
    out = []
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            d = json.loads(line)
            pid = d.get("prompt_id", "?")
            out.append((pid + "/resp", d.get("model_response", "")))
            out.append((pid + "/prompt", d.get("prompt_text", "")))
    return out


def stress_texts():
    out = []
    for p in glob.glob(os.path.join(ROOT, "tests", "stress", "**", "*.json"), recursive=True):
        try:
            d = json.load(open(p, encoding="utf-8"))
        except Exception:
            continue
        msg = ""
        if isinstance(d, dict):
            msg = d.get("last_assistant_message") or d.get("message") or ""
            if not msg:
                strs = [v for v in d.values() if isinstance(v, str)]
                msg = max(strs, key=len) if strs else ""
        elif isinstance(d, list):
            strs = [x for x in d if isinstance(x, str)]
            msg = max(strs, key=len) if strs else ""
        out.append((os.path.relpath(p, os.path.join(ROOT, "tests", "stress")), msg))
    return out


def main():
    n1, b1 = scan(mad_texts(), "MAD raw_results (model_response + prompt_text)")
    n2, b2 = scan(stress_texts(), "stress fixtures (other hooks)")
    total, blocks = n1 + n2, b1 + b2
    print("\nTOTAL independent texts: %d | blocks: %d | false-positive rate: %.4f"
          % (total, blocks, (blocks / total) if total else 0.0))
    return 1 if blocks > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
