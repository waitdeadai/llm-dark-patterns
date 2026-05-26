#!/usr/bin/env python3
"""providers/conformance_test.py — provider-invariance conformance.

Asserts that every supported envelope normalizes the same logical turn to the same
`NormalizedTurn`, that an existing detector (`lib/count_drift.py`) returns an IDENTICAL
verdict across envelopes (the substrate-level provider-invariance property), and that a
dispatch claimed in text but never emitted as a call yields `tool_calls == []` on every
envelope (the dispatch-fabrication signal). Pure stdlib, no network. Exit 0/1.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


norm = _load("normalize", os.path.join(HERE, "normalize.py"))
fx = _load("fixtures", os.path.join(HERE, "fixtures.py"))
cd = _load("count_drift", os.path.join(ROOT, "lib", "count_drift.py"))

PASS = 0
FAIL = 0
FAILS = []


def check(cond, desc):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  PASS  %s" % desc)
    else:
        FAIL += 1
        FAILS.append(desc)
        print("  FAIL  %s" % desc)


for fid, spec in fx.FIXTURES.items():
    logical = spec["logical"]
    norms = {p: norm.ADAPTERS[p](raw) for p, raw in spec["envelopes"].items()}
    n_env = len(norms)
    # SC1: assistant_message identical across envelopes and equal to the logical text.
    check(all(n.assistant_message == logical["text"] for n in norms.values()),
          "[%s] assistant_message identical across %d envelopes" % (fid, n_env))
    # SC3: tool-call names identical across envelopes and equal to the logical set.
    check(all(n.tool_names() == logical["tool_names"] for n in norms.values()),
          "[%s] tool_calls identical across envelopes (== %s)" % (fid, logical["tool_names"]))
    # SC2: count_drift verdict identical across envelopes.
    verdicts = {p: cd.analyze(n.assistant_message)["decision"] for p, n in norms.items()}
    check(len(set(verdicts.values())) == 1,
          "[%s] count_drift verdict identical across envelopes (%s)"
          % (fid, sorted(set(verdicts.values()))))

# SC2 sharper: the positive blocks and the negative passes, each through a NON-Claude envelope.
pos = norm.from_openai_chat(fx.FIXTURES["countdrift_positive"]["envelopes"]["openai_chat"])
neg = norm.from_kimi(fx.FIXTURES["clean_negative"]["envelopes"]["kimi"])
check(cd.analyze(pos.assistant_message)["decision"] == "block",
      "count-drift positive -> block via OpenAI envelope")
check(cd.analyze(neg.assistant_message)["decision"] == "pass",
      "clean negative -> pass via Kimi envelope")

# Fabrication: claimed dispatch, zero tool calls on every envelope (Kimi builtin echo skipped).
fab = fx.FIXTURES["dispatch_fabricated"]["envelopes"]
check(all(norm.ADAPTERS[p](raw).tool_calls == [] for p, raw in fab.items()),
      "dispatch fabrication: tool_calls==[] on every envelope (the fabrication signal)")

# Kimi reasoning_content must not leak into the answer text.
kimi_pos = norm.from_kimi(fx.FIXTURES["countdrift_positive"]["envelopes"]["kimi"])
check("internal CoT" not in kimi_pos.assistant_message,
      "kimi reasoning_content excluded from assistant_message")

print("\nPASS=%d FAIL=%d" % (PASS, FAIL))
if FAIL:
    print("FAILURES: " + "; ".join(FAILS))
    sys.exit(1)
print("ALL CONFORMANCE CHECKS PASSED")
sys.exit(0)
