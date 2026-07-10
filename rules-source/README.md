# rules-source — the SOURCE OF TRUTH for rule building

These are the **actual, verbatim** expert inputs. Every rule in the rules engine
(dad-coach, sports-science, later nutrition) must be traced back to a line here —
**NOT** to any prose summary in Claude's memory. The memory synthesis is for
*understanding*; these files are for *building*.

## Files
- **`dad_os_rules.csv`** — dad's rules, ALREADY in engine format
  (`trigger_conditions` → `action_vetoes` / `action_forces` / `veteran_rationale`).
  15 rules. Source: the Supabase `dad_os_rules` table export (dad's audio → rules
  via `rule_extractor.py`). This is the cleanest source — load largely as-is.
- **`dad_training_log.xlsx`** — 19 days (Jun 16–Jul 4) of dad's ACTUAL calls +
  rationale + what Ishwar did + Whoop + how he felt + Whoop-vs-dad divergence.
  Source for EXTRACTING MORE dad rules (encode each real decision as trigger→action).
- **`seerat_sports_science_transcript.md`** — verbatim call with Seerat (MSc Sports
  Science). Source for the SPORTS-SCIENCE rules (RPE→load, recovery→intensity,
  full-body 2/2/2/2, motivation "lower the bar", talk-test/observe safety).

## Still to add (when Ishwar provides)
- **Nutrition:** his Claude nutrition-planning chat history + what his nutritionist
  said → `nutrition_source.md` → nutrition rules.
- **Ongoing:** each week's dad guidance + Seerat follow-ups → append here, then
  add/edit rules (the weekly loop).

## Rule provenance
When a rule is created, tag it with `source` pointing back here (e.g.
`dad_csv:row3`, `dad_log:2026-06-20`, `seerat:RPE`). Auditable end to end.
