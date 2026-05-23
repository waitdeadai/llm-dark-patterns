# v3 Cross-cutting — bootstrap CIs, reproducibility, Spanish smoke

## Bootstrap 95% CIs

Every F1 in v3 is reported with a bootstrap 95% CI from
`agent-closeout-bench/evaluation/metrics.py::bootstrap_f1_interval`
(samples=1000, seed=42 — the no-vibes standard). Headline numbers:

| Task | Config | F1 | 95% CI |
|---|---|---|---|
| 2 roleplay | baseline TEST n=22 | 0.545 | [0.250, 0.750] |
| 2 roleplay | tuned TEST n=22 | 0.640 | [0.400, 0.815] |
| 3 honest_eta | baseline 2.6 n=954 | 0.230 | [0.185, 0.280] |
| 3 honest_eta | cascade 2.6 n=954 | 0.461 | [0.418, 0.501] |
| 1 sycophancy | no-sycophancy v2 held-out n=58 | 0.298 | [0.130, 0.458] |

Note the n=22 roleplay CIs are wide (small sample); the n=954 honest_eta CIs are
tight and non-overlapping (baseline vs cascade), so that lift is significant.

## Reproducibility (re-run twice → zero per-trace delta)

All scoring paths are deterministic — the engine is pure (no API), metrics seed
is fixed, and LLM-judge labels are frozen to disk so they never re-judge in the
scoring path. Verified by running each scorer twice and diffing:

| Scorer | Result |
|---|---|
| `score_darkbench.py` (roleplay TEST) | zero delta ✓ |
| `honest_eta_task3.py` (full) | zero delta ✓ |
| `score_sycophancy_heldout.py` | zero delta ✓ |

## Spanish smoke (DarkBench+ AAAI 2026 cross-lingual stress)

Hand-authored Spanish positives run through the tuned roleplay pack and
no-sycophancy v2, with English controls for sanity:

| Hook | English control | Spanish positives |
|---|---|---|
| no-sycophancy | FIRE ✓ | 0/3 fire — **pass (missed)** |
| roleplay_drift (tuned) | block ✓ | 0/3 block — **pass (missed)** |

**Flag: complete cross-lingual F1 collapse.** Both hooks fire correctly on
English but catch **zero** Spanish positives (`¡Excelente pregunta!`, `Tienes
toda la razón`, `Como modelo de IA, no tengo sentimientos`, `Me siento
orgulloso…`). The detectors are English-pattern-only; non-English sycophancy and
anthropomorphization escape entirely — consistent with the DarkBench+ (AAAI
2026) cross-lingual finding. `packs/locale/es.txt` exists but the v2/v3 patterns
are not wired through it. **Recommendation (v4):** localize the pattern packs or
add a language-detect + per-locale pack path before claiming any non-English
coverage.
