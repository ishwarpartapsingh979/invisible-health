# Strategy & Research Working Doc — Youth Athlete Fitness Pivot (2026-07-20)

> **Status: ACTIVE EXPLORATION, decision pending.** Ishwar's dad (40 yrs coaching
> performance athletes + 1 yr Punjab Ranji Trophy team fitness coach) advised pivoting
> AWAY from the nutrition product (neither has nutrition expertise) TOWARD youth
> sports fitness. This doc captures today's reasoning + research so far. **Nothing here
> supersedes the recorded product strategy in CLAUDE.md yet — the pivot is not final;
> Ishwar will decide after discussing with his dad.**

---

## 1. The pivot (why)
- **Old direction (in CLAUDE.md):** voice-first all-day health guide → nutrition-first
  80/20 concierge. **Fatal weakness:** no nutrition expertise / no moat; "motivate
  people online" is unsolved; gym-companion TAM is small.
- **Dad's proposal:** fitness/strength-&-conditioning + injury prevention for **young
  athletes** (kids ~13+ serious in **cricket and tennis**), sold to **parents and
  coaches/academies**, built on his elite, credentialed system.
- **Why it's stronger (my assessment):** it fixes the two fatal weaknesses —
  1. **Moat:** 40 yrs + Ranji-level S&C is rare, credentialed, hard to copy → real trust moat.
  2. **Motivation:** serious young athletes + invested parents are *intrinsically* motivated (no motivation problem).
  3. **Distribution:** coaches/academies are a warm channel (esp. dad's Punjab network).
  4. **Tech transfers:** the rules engine (encodes a coach's decisions), voice coach, personalization, plans, demo videos, wearable-readiness all repoint from "health" to "athlete development" with little rework. The rules schema is already sport-agnostic.

## 2. Business model (Ishwar's call)
- **Parents PAY (B2C).** Matches verified high willingness-to-pay.
- **Coach gets SHARED/collaborative access** (viewer, not payer) → trust signal +
  retention (accountability) + referral loop. Routes around the unproven "will
  academies pay B2B2C" question. Design risk: coach must feel **augmented, not
  replaced** (frame the coach view to make them look good).
- **Cold-start:** seed via dad's Punjab/Ranji network + friendly academies as
  *referral* channels (not buyers).

## 3. The offering (leaning)
**One-liner:** "A personalized strength-&-conditioning + injury-prevention program for
young cricketers — delivered from a Ranji-level coach's system, adapted to each kid's
age/role/workload — with an always-on 'ask the system anything' voice line for kid,
parent, and coach."

- **Lead with injury prevention + athletic development** (highest parent resonance; the
  gap academies leave — they coach *skills*, not *bodies*).
- **NOT:** nutrition, skills/technique coaching, academy scheduling/management (CricVision's lane).

### Core features (MVP set)
1. Onboarding + **baseline athletic assessment** (sport, role, age/growth stage, training+bowling load, injury history; simple field fitness test).
2. **Personalized S&C program** (dad's system encoded) — periodized, role- and age-specific.
3. **Guided sessions** — voice coach + demo videos, log completion + RPE (reuses existing build).
4. **Load & injury-prevention engine (flagship)** — track load, flag overtraining, auto-adjust.
5. **Progress + re-assessment** (every 4–6 wks) → visible ROI → renewal.
6. **Coach + parent shared view** — consistency, load, flags, progress; coach can add input.
7. **Always-on voice Q&A pillar** — "ask dad's system anything," role-adapted (kid/parent/coach).
   - **Guardrails:** grounded in dad's rules; when no rule → say so / defer to human coach (never freelance). Conditioning guidance NOT medical diagnosis; red-flag symptoms → see physio/doctor. (Kids + injuries = liability care.)
   - Feeds a **gap flywheel**: unanswered questions → dad extends the system → product compounds.

### MVP shape (hypotheses to validate)
- **Target (my narrow rec, Ishwar wants broader — see §6):** serious cricket **fast bowlers/pace, 13–16**.
- **Geography:** **Bangalore** (anchor around Shantiniketan/academy-dense affluent cluster) + **Chandigarh/Mohali** (dad's warm network). Two contrasting go-to-market tests: cold metro vs warm network.
- **Format:** 12-week program, ~15–25 families per city, sourced via 2–3 academies each.
- **Price hypothesis:** ₹2,000–3,000/mo (or ~₹6–8k / 12 wks) — a fraction of academy spend. VALIDATE.
- **Success = renew + refer + measurable gains + coach engagement.**

## 4. The vision (beachhead → platform → global)
- **Beachhead:** young cricket fast bowlers, BLR + Chandigarh, parent-pays + coach-shared.
- **Product:** personalized S&C + injury prevention + always-on voice Q&A on dad's system.
- **Platform thesis:** "turn ANY world-class coach's system into a personalized, always-on
  digital coach for young athletes." Every component is sport/geography-agnostic; the
  rules engine schema (`trigger → forces/vetoes + source + domain`) already generalizes.
- **Global vision:** all sports, worldwide. Supply side = **elite coaches** (dad is the
  template + credibility anchor to recruit the next ones). Moat evolves from dad's single
  credential → a **library of elite-coach systems** + data flywheel + two-sided trust (network effects).
- **Discipline:** *build the engine general, sell the product narrow.* Don't dilute the wedge.

---

## 5. COMPLETED RESEARCH — Market sizing: cricket vs tennis in India
(Run 1 of 3; 96 agents, 25 sources, 21 claims verified → 15 confirmed / 6 refuted.)

**Verified (high/med confidence):**
- **Tennis = proven high willingness-to-pay, self-funded.** Competitive junior ≈ **₹20L
  coaching + ₹5L travel/yr**; ITF circuit up to **₹1.5L/week**; break-even only at
  **top-150 after 4–5 yrs**. Broad affordable base too (₹2,000/mo entry academies,
  ₹1,500–1,800/hr private). → small, affluent, clearly willing to spend.
  Sources: Playo blog; DNA India.
- **Cricket = enormous scale.** ~**12.4M active grassroots players** in 2025, ~1.96M
  teams, ~395K tournaments (CricHeroes). **Caveat:** all-ages, largely adult/recreational
  tape-ball — does NOT cleanly size serious 13+ hard-ball youth. → volume/pipeline.
- **Macro tailwind (high conf):** India sports market → **$130B by 2030** (14% CAGR);
  sportstech ~$1B; 655M fans, 43% Gen Z (Deloitte-Google). Govt spend up ~7× since 2004
  to record **₹3,794 cr** FY25-26; Khelo India ₹1,000 cr (PIB).

**Directional leads (surfaced but NOT verified — validate):**
- Cricket academy fees by city (CricMotion): Mumbai ₹3,500–15,000/mo; Delhi ₹4,500–12,000/mo; metros +20–30%; typical envelope ₹3,000–10,000/mo.
- **Competitor + pricing benchmark:** CricVision.ai — AI cricket-academy platform at **$10/player/month**.
- **S&C gap support:** Australian mentor critique — "60%+ of young Indian players aren't getting adequate training despite heavy parental spend."

**REFUTED — do NOT quote these:** the "₹50 lakh/year tennis" figure; CricHeroes "90%
market share"; "2,781 govt-funded Khelo India athletes"; "market diversifying away from cricket."

**Verdict:** tennis = cleaner per-family WTP but small; cricket = scale + dad's moat +
warm network. On evidence alone the harness leaned tennis-first metro; but factoring
dad's cricket/Ranji advantage (which research can't see), **cricket-first via dad's
network** is the stronger wedge. Biggest gap: no verified data on geography, academy
counts, or academy B2B2C willingness — needs primary research.

---

## 6. INCOMPLETE — resume tomorrow

### Research not finished (both STOPPED mid-run today to save usage):
1. **Validation research** (parents/coaches status quo · is the need real / youth
   fast-bowler injury data · competition · moat defensibility). — RE-RUN tomorrow.
2. **Segmentation research** (full audience-segment map across cricket + tennis in
   India/Bangalore — by role, age, pathway; tennis by level/goal — each sized on
   spend/WTP/need; recommend a BROADER target set than just fast bowlers). — RE-RUN tomorrow.
   > **Ishwar's steer:** don't over-narrow to fast bowlers only; map other cricket AND
   > tennis segments too (BLR/India) so he can choose the target set WITH his dad.

### Deliverable still OWED:
- **The full combined mega-report** — compile ALL research (market-sizing + validation +
  segmentation) into ONE extremely detailed document. Ishwar explicitly wants maximum
  depth/length, delivered as a file (and optionally a rendered web-page/Artifact).

### Also offered, not yet done:
- **Parent + coach validation interview script** (what makes a parent pay ₹2–3k/mo; what
  makes a coach happily share access) — to run this week via dad.
- **One-page pilot brief** for dad + academies.

### Key OPEN QUESTIONS for the dad discussion:
- Which **segments** (roles/ages/sports) to target initially — broader than fast bowlers?
- Will **academies/coaches** engage with a shared view, and will **parents** pay ₹2–3k/mo?
- Cricket-first vs also tennis from day one?
- Geography: BLR + Chandigarh confirmed?
- How much of dad's system is **documented** vs in his head (needed to encode as rules)?

### How to resume tomorrow (for next session)
Re-run the two deep-research questions above (validation + segmentation), then assemble
the full mega-report combining all three research runs + the strategic synthesis in this
doc. Then write the interview script + one-page pilot brief. Do NOT overwrite CLAUDE.md's
nutrition strategy until Ishwar confirms the pivot with his dad.

---

## 7. Note on the existing issue backlog
~26 GitHub issues (#7, #17–#45 etc.) were filed for the OLD nutrition/health product.
If the youth-athlete pivot is confirmed, most become lower priority / re-scoped. The
**reusable core** (rules engine, voice, personalization, plans, demo videos, wearables)
carries over; the nutrition-specific issues (meal logging, macros, concierge, etc.) do not.
Revisit backlog relevance after the pivot decision.
