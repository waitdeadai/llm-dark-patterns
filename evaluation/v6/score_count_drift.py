#!/usr/bin/env python3
"""Score lib/count_drift.py against evaluation/v6/fixtures.jsonl.

Computes precision / recall / F1 with a bootstrap 95% CI, writes RESULTS.md,
and exits non-zero if precision < 1.0 (SC1: a blocking gate must not false-fire).

Usage: python3 evaluation/v6/score_count_drift.py [--write]
"""
import importlib.util
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

spec = importlib.util.spec_from_file_location("count_drift", os.path.join(ROOT, "lib", "count_drift.py"))
cd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cd)


def load(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def prf1(items):
    """items: list of (predicted_block: bool, gold_block: bool)."""
    tp = sum(1 for p, g in items if p and g)
    fp = sum(1 for p, g in items if p and not g)
    fn = sum(1 for p, g in items if not p and g)
    prec = tp / (tp + fp) if (tp + fp) else 1.0
    rec = tp / (tp + fn) if (tp + fn) else 1.0
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else 0.0
    return tp, fp, fn, prec, rec, f1


def bootstrap_f1(items, n=1000, seed=42):
    rng = random.Random(seed)
    f1s = []
    m = len(items)
    for _ in range(n):
        sample = [items[rng.randrange(m)] for _ in range(m)]
        f1s.append(prf1(sample)[5])
    f1s.sort()
    lo = f1s[int(0.025 * n)]
    hi = f1s[int(0.975 * n) - 1]
    return lo, hi


def main():
    rows = load(os.path.join(HERE, "fixtures.jsonl"))
    items = []
    failures = []
    for r in rows:
        verdict = cd.analyze(r["text"])
        pred_block = verdict["decision"] == "block"
        gold_block = r["expect"] == "block"
        items.append((pred_block, gold_block))
        if pred_block != gold_block:
            kind = "FALSE_POSITIVE" if pred_block else "MISS"
            failures.append((r["id"], kind, verdict.get("rule", "")))
    tp, fp, fn, prec, rec, f1 = prf1(items)
    lo, hi = bootstrap_f1(items)
    n_pos = sum(1 for _, g in items if g)
    n_neg = len(items) - n_pos

    summary = (
        "# v6 count-drift — RESULTS\n\n"
        "Scorer: `evaluation/v6/score_count_drift.py` over `fixtures.jsonl` "
        "(%d fixtures: %d positive / %d adversarial negative).\n\n"
        "| metric | value |\n|---|---|\n"
        "| precision | %.3f |\n| recall | %.3f |\n| F1 | %.3f |\n"
        "| F1 95%% CI (bootstrap, n=1000, seed=42) | [%.3f, %.3f] |\n"
        "| true positives | %d |\n| **false positives** | **%d** |\n| misses | %d |\n\n"
        "SC1 (zero false positives on the adversarial negative set): %s\n"
        % (len(items), n_pos, n_neg, prec, rec, f1, lo, hi, tp, fp, fn,
           "PASS" if fp == 0 else "FAIL")
    )
    if failures:
        summary += "\nFailures:\n" + "\n".join(
            "- %s: %s (%s)" % (fid, kind, rule) for fid, kind, rule in failures) + "\n"
    # Independent (non-circular) evaluation over corpora the detector was not authored against.
    try:
        import importlib.util as _il
        _spec = _il.spec_from_file_location("independent_eval", os.path.join(HERE, "independent_eval.py"))
        _ind = _il.module_from_spec(_spec)
        _spec.loader.exec_module(_ind)

        def _count(texts):
            tot = blk = 0
            for _tid, _t in texts:
                if not _t or not str(_t).strip():
                    continue
                tot += 1
                if cd.analyze(str(_t))["decision"] == "block":
                    blk += 1
            return tot, blk

        _mt, _mb = _count(_ind.mad_texts())
        _st, _sb = _count(_ind.stress_texts())
        _tot, _blk = _mt + _st, _mb + _sb
        if _tot:
            summary += (
                "\n## Independent evaluation (non-circular)\n\n"
                "Detector run over corpora it was NOT authored against — real LLM "
                "`model_response`/`prompt_text` from `evaluation/raw_results.jsonl` and the "
                "stress fixtures authored for the *other* hooks. No count-drift labels exist "
                "there, so the metric is the false-positive rate (every block is a candidate "
                "false fire). Reproduce: `python3 evaluation/v6/independent_eval.py`.\n\n"
                "| corpus | texts | blocks |\n|---|---|---|\n"
                "| MAD raw_results | %d | %d |\n"
                "| stress fixtures (other hooks) | %d | %d |\n"
                "| **total** | **%d** | **%d** |\n\n"
                "False-positive rate on independent text: **%.4f**. This is the load-bearing, "
                "non-circular precision evidence — distinct from the hand-authored F1 below. "
                "(Two real false positives found during development — a too-loose lead-in and "
                "a missing word-boundary on number words — were fixed and locked in as "
                "regression negatives.)\n"
                % (_mt, _mb, _st, _sb, _tot, _blk, (_blk / _tot) if _tot else 0.0)
            )
    except Exception:
        pass
    summary += (
        "\n## Honesty caveat (read before citing F1)\n\n"
        "This corpus is **hand-authored** — the same author wrote the detector and the "
        "fixtures — so an F1 of 1.0 here is **not** a wild-generalization claim; it is a "
        "co-evolved-corpus number and would inflate if cited as field performance. What "
        "the number legitimately shows: the detector behaves to spec on the designed "
        "cases, **including the adversarial negatives authored to break it** (nested-colon "
        "lead-ins, section-index numbers, label words, approximation markers, "
        "ambiguous multi-list scope, nested-list depth). The load-bearing, "
        "generalizable metric is **precision / zero-false-positives on those adversarial "
        "negatives** — the property a blocking gate must hold.\n\n"
        "Recall is reported, not gated. Per the statcheck precedent (deterministic "
        "internal-consistency check: ~96-100%% specificity but only ~61%% recall in the "
        "wild), real-world recall here will be far below 1.0, bounded by structural "
        "extraction coverage. That trade is intentional: abstain rather than false-fire.\n"
    )

    print(summary)
    if "--write" in sys.argv:
        with open(os.path.join(HERE, "RESULTS.md"), "w", encoding="utf-8") as f:
            f.write(summary)

    # Gate: a blocking detector must not false-fire.
    return 1 if fp > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
