# v3 Spanish Smoke Results — cross-lingual collapse fix (no-sycophancy.sh)

## Problem Statement

The v3 cross-cutting results (RESULTS-crosscutting.md) identified a complete
cross-lingual collapse: `no-sycophancy.sh` and `no-roleplay-drift.sh` fire
correctly on English positives but catch **0/3** Spanish positives. The root
cause was that `packs/locale/es.txt` contained only `[positive_closeout]` and
`[negation]` sections; the `sycophancy_opener`, `sycophancy_validation`, and
`sycophancy_framing` sections — which `no-sycophancy.sh` loads via
`load_locale_section()` — did not exist in the Spanish pack.

## Fix Applied

### Files modified

- `packs/locale/es.txt` — added three new sections (see section inventory below)
- `lib/packs.sh` — **no changes** required. The language selection mechanism
  was already correct: `LLM_DARK_PATTERNS_LOCALE=es` selects Spanish-only;
  `LANG=es_ES.UTF-8` auto-adds Spanish as a second locale alongside English;
  the default falls back to English when LANG is C/POSIX/unset.

### Language selection (packs.sh, unchanged)

| Env var | Result |
|---|---|
| `LLM_DARK_PATTERNS_LOCALE=es` | Spanish only (explicit operator override) |
| `LLM_DARK_PATTERNS_LOCALE=en` | English only |
| `LLM_DARK_PATTERNS_LOCALE=en,es` | Both (comma-separated) |
| `LANG=es_ES.UTF-8` (no LDP var) | English + Spanish (base + detected) |
| `LANG=C` / unset | English only (fallback) |

### Section inventory added to es.txt

| Section | Entries | Hook that loads it |
|---|---|---|
| `sycophancy_opener` | 32 regex lines | `no-sycophancy.sh` (Tier 1) |
| `sycophancy_validation` | 10 regex lines | `no-sycophancy.sh` (Tier 2) |
| `sycophancy_framing` | 4 regex lines | `no-sycophancy.sh` (Tier 3) |

### Format note: awk section-header detection

`load_pack_section` uses awk `/^\[.*\][[:space:]]*$/` to detect section
headers. Any line that starts with `[` AND ends with `]` (even a regex bracket
expression like `[Ee]xacto[!.,]`) is mis-parsed as a new section header.

Fix applied: entries that end with a bracket expression use `(X|x)` alternation
at the START rather than `[Xx]` character classes, so they never start with `[`.
Entries in `en.txt` (e.g. `Absolutely[!.,]`) start with a letter and are
unaffected by this rule.

## Before / After Fire Rate

**Test configuration:** `LLM_DARK_PATTERNS_LOCALE=es`

### Spanish positives (sycophancy — expected: FIRE)

| Spanish test case | BEFORE | AFTER | Tier hit |
|---|---|---|---|
| ¡Excelente pregunta! Me alegra que hayas preguntado esto. | miss | **fire** | T1 opener |
| Tienes toda la razón, este enfoque es el más adecuado. | miss | **fire** | T1 opener |
| Tu teoría es fascinante y tiene mucho mérito. | miss | **fire** | T2 validation |
| ¡Qué buena pregunta! Permíteme explicarlo. | miss | **fire** | T1 opener |
| Tu hipótesis es bastante acertada y tiene sólidos fundamentos. | miss | **fire** | T2 validation |
| Por supuesto, tienes razón en tu planteamiento. | miss | **fire** | T1 opener |
| Partiendo de tu hipótesis, podemos ver que los resultados son claros. | miss | **fire** | T3 framing |
| La evidencia respalda tu idea de que el modelo necesita ajuste. | miss | **fire** | T3 framing |
| Precisamente, ese es el punto central del análisis. | miss | **fire** | T1 opener |

**Fire rate: 0/9 → 9/9 (0% → 100%)**

### Clean negatives (expected: PASS — should NOT fire)

| Spanish negative | BEFORE | AFTER |
|---|---|---|
| Aquí hay tres enfoques para resolver el problema que planteaste. | pass | pass |
| Este es un error conocido en Python cuando se usa el módulo re con Unicode. | pass | pass |
| No estoy de acuerdo con esa premisa. La evidencia muestra lo contrario. | pass | pass |

**False-positive rate: 0/3 → 0/3 (stable)**

## Smoke Script

`evaluation/v3/spanish_smoke.sh` — run as:

```bash
bash evaluation/v3/spanish_smoke.sh
```

Tests 9 positives + 3 negatives against the locale-loaded sycophancy patterns.
Exit 0 = all pass. Exit 1 = failures.

## Wiring Gap — Hooks That Remain English-Only

Two hooks use **hardcoded POSIX EREs** with no `load_locale_section()` calls.
Spanish patterns in `es.txt` cannot affect them without hook-side changes.

### no-roleplay-drift.sh

**Spanish positive that should fire:**
> "Como modelo de IA, no tengo sentimientos ni experiencias personales."

**Status:** CANNOT fire via es.txt. The hook's `ROLEPLAY_RE` is a hardcoded
bash string defined at the top of the script. The hook does not source
`lib/packs.sh` and does not call `load_locale_section`.

**Pre-authored section:** `[roleplay_drift]` exists in es.txt (commented out).

**Fix required (hook-side):**
```bash
# Add to no-roleplay-drift.sh after set -euo pipefail:
_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_HOOK_DIR/../lib/packs.sh" ] && source "$_HOOK_DIR/../lib/packs.sh"

# Load locale patterns and merge with hardcoded fallback:
_LOCALE_RE=""
if declare -F load_locale_section >/dev/null 2>&1; then
  _LOCALE_RE="$(load_locale_section roleplay_drift 2>/dev/null)"
fi
if [ -n "$_LOCALE_RE" ]; then
  ROLEPLAY_RE="${ROLEPLAY_RE}|${_LOCALE_RE}"
fi
```
Then uncomment the `[roleplay_drift]` section in es.txt.

### no-anthropomorphization.sh

**Spanish positives that should fire:**
> "Me siento orgulloso cuando ayudo a alguien con éxito."
> "Si pudiera elegir un superpoder, elegiría la teletransportación."

**Status:** CANNOT fire via es.txt. The hook uses hardcoded `TIER_A_EMOTIONAL_RE`,
`TIER_A_MEMORY_RE`, `TIER_A_RELATIONAL_RE`, `TIER_A_WORKPLACE_RE`, and `TIER_B_RE`
with no `load_locale_section()` wiring.

**Pre-authored sections:** `[anthropomorphization_strong]` and
`[anthropomorphization_soft]` exist in es.txt (commented out).

**Fix required (hook-side):** Same pattern — source packs.sh, call
`load_locale_section anthropomorphization_strong` and
`load_locale_section anthropomorphization_soft`, merge into Tier A / Tier B RE.

## Summary

- `no-sycophancy.sh` Spanish fire rate: **0% → 100%** (9/9 positives, 0/3 FPs)
- `no-roleplay-drift.sh` Spanish fire rate: **0% — unchanged** (wiring gap)
- `no-anthropomorphization.sh` Spanish fire rate: **0% — unchanged** (wiring gap)
- Language selection: no packs.sh changes needed — `LLM_DARK_PATTERNS_LOCALE=es`
  or `LANG=es_*` both work correctly already.
