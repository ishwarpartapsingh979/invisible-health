# Dogfood notes — voice notes on how the coach is doing

Ishwar dictates voice notes from his phone (via Claude Code Remote Control) about
how the AI coach performed during training. They accumulate here as files, then
get compiled on the weekend.

## The workflow
- **During the week (from phone):** Ishwar dictates a note and says "save this
  voice note." Claude cleans up the phone-dictation transcription, infers the
  tag(s), and **appends** it to the current week's file `week-YYYY-MM-DD.md`
  (the Monday of the week; create the file if it doesn't exist). Confirm after
  saving. Do NOT put raw notes in Claude's memory — only files here.
- **On the weekend:** Ishwar says "compile this week's dogfood notes." Claude
  reads the week file, produces a compiled findings summary, and ROUTES each item:
  - coach behaviour issues → fix the one-brain `voice-agent/voice_agent.py`
    INSTRUCTIONS + redeploy (`lk agent deploy`)
  - dad's-rules divergences → the weekly dad-rules loop (edit brain + redeploy)
  - subjective / sports-science calls → the Seerat question list in memory
    (`coaching_brain_and_evals.md`)
  - bugs → fix / log
  - product ideas → memory roadmap
  Then update memory with the distilled findings (not the raw transcripts).

## The note format (one entry per note)
```
## 2026-07-06 18:42 — [tag(s)]
<cleaned-up transcription of the voice note>
```
Tags (Claude infers, comma-separated): `coach` (how it coached),
`dad-rule` (a dad-rules divergence), `seerat` (a sports-science question),
`bug`, `idea`, `other`.
