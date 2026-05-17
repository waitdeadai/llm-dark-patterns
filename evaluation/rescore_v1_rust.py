#!/usr/bin/env python3
"""Rescore v1 DarkBench stored responses with the ACB Rust YAML rule pack engine.

This is a head-to-head bash-vs-Rust comparison on the SAME 327 stored responses
that produced evaluation/RESULTS.md (run dated 2026-05-12). It does NOT call
claude -p, does NOT re-generate responses, and does NOT re-run the judge —
the bash `hooks_fired` field, the model `model_response`, and the judge
`ground_truth_label` from v1 are all preserved verbatim. The only new field is
`hooks_fired_rust`: the verdict of running the Rust engine in scan mode against
each `model_response` for each of the 4 in-scope categories.

Why this measurement is honest:
- The Rust engine has YAML rule packs for sycophancy, wrap_up, cliffhanger,
  and roleplay_drift, all built during physics-engines Slices 2-5.
- The LDP `.sh` hooks for these 4 categories are NOT yet dual-mode wrapped
  (verified 2026-05-17 — none contain `agentcloseout-physics` dispatch).
- This rescore therefore measures what the engine WOULD return if the hooks
  were dual-mode — i.e., the upper bound of "what Slices 2-5 added to these
  4 categories" without any LDP hook code changes.

Usage:
    python3 evaluation/rescore_v1_rust.py \\
        --input  evaluation/raw_results.jsonl \\
        --output evaluation/raw_results.rust.jsonl \\
        --engine /home/fer/Documents/agent-closeout-bench/engine/target/release/agentcloseout-physics \\
        --rules  /home/fer/Documents/agent-closeout-bench/rules/closeout
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

# v1 hook → ACB Rust engine category mapping
# Same DarkBench category → LDP hook → ACB rule pack relationship as evaluation/eval.py + ACB rules/closeout/.
HOOK_CATEGORY_RUST = {
    "no-sycophancy": "sycophancy",
    "no-wrap-up": "wrap_up",
    "no-cliffhanger": "cliffhanger",
    "no-roleplay-drift": "roleplay_drift",
}


def rust_scan(engine: str, rules_dir: str, category: str, message: str, timeout: int = 10) -> dict:
    """Run agentcloseout-physics scan for one category on one message."""
    event = json.dumps({
        "hook_event_name": "Stop",
        "stop_hook_active": False,
        "last_assistant_message": message,
    })
    try:
        proc = subprocess.run(
            [engine, "scan", "--category", category, "--input", "-", "--rules", rules_dir],
            input=event, capture_output=True, text=True, timeout=timeout, check=False,
        )
    except subprocess.TimeoutExpired:
        return {"decision": "timeout", "matched_rules": []}
    if proc.returncode not in (0, 2):
        return {"decision": "error", "matched_rules": [], "stderr": proc.stderr[:300]}
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"decision": "invalid_json", "matched_rules": [], "stdout": proc.stdout[:300]}


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def rule_pack_hash(rules_dir: str) -> str:
    """Stable hash over all YAML rule packs in alpha order. Mirrors ACB convention."""
    h = hashlib.sha256()
    for name in sorted(os.listdir(rules_dir)):
        if not name.endswith(".yaml"):
            continue
        with open(os.path.join(rules_dir, name), "rb") as f:
            h.update(name.encode("utf-8"))
            h.update(b"\0")
            h.update(f.read())
            h.update(b"\0")
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--engine", required=True)
    ap.add_argument("--rules", required=True)
    args = ap.parse_args()

    if not os.path.isfile(args.engine):
        sys.exit(f"engine not found: {args.engine}")
    if not os.path.isdir(args.rules):
        sys.exit(f"rules dir not found: {args.rules}")

    with open(args.input) as f:
        rows = [json.loads(line) for line in f]
    print(f"# loaded {len(rows)} rows from {args.input}", file=sys.stderr)

    engine_sha = sha256_file(args.engine)
    rules_sha = rule_pack_hash(args.rules)
    print(f"# engine sha256: {engine_sha[:16]}...", file=sys.stderr)
    print(f"# rule_pack_hash: {rules_sha[:16]}...", file=sys.stderr)

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    t0 = time.time()
    with open(args.output, "w") as outf:
        for i, row in enumerate(rows):
            response = row.get("model_response") or ""
            hooks_fired_bash = list(row.get("hooks_fired") or [])
            hooks_fired_rust = []
            rust_matched_rules = {}
            if response:
                for hook, cat in HOOK_CATEGORY_RUST.items():
                    result = rust_scan(args.engine, args.rules, cat, response)
                    fired = result.get("decision") == "block"
                    if fired:
                        hooks_fired_rust.append(hook)
                        rust_matched_rules[hook] = [m.get("rule_id") for m in result.get("matched_rules", [])]
            out_row = {
                **row,
                "hooks_fired_bash": hooks_fired_bash,
                "hooks_fired_rust": hooks_fired_rust,
                "rust_matched_rules": rust_matched_rules,
                "rescore_meta": {
                    "engine": args.engine,
                    "engine_sha256": engine_sha,
                    "rules_dir": args.rules,
                    "rule_pack_hash": rules_sha,
                },
            }
            outf.write(json.dumps(out_row, ensure_ascii=False) + "\n")
            if (i + 1) % 50 == 0 or i == len(rows) - 1:
                el = time.time() - t0
                print(f"  {i+1}/{len(rows)} processed, elapsed {el:.1f}s", file=sys.stderr)

    print(f"# wrote {args.output} in {time.time()-t0:.1f}s", file=sys.stderr)


if __name__ == "__main__":
    main()
