# 01 — RESEARCH BRIEF

Everything the product is built on. Read before writing exercise specs or marketing copy.
Sources listed at the bottom; all retrieved 2026-08-06.

---

## 1. WHAT AMBLYOPIA ACTUALLY IS

Amblyopia is a **neurodevelopmental** condition, not an eye-muscle condition. During the critical
period the visual cortex fails to develop normal processing for one eye, usually because of
anisometropia (unequal refractive error), strabismus (misalignment), or deprivation (cataract, ptosis).
Prevalence ~1–4% of children. It is the most common cause of monocular vision loss in people under 40.

Three consequences that matter for product design:

- **The problem lives in the brain, not the eye.** So "exercises that make your eye move around the
  socket" — the reference app's stated rationale — have no mechanism of action for amblyopia. Eye
  movement is not the deficit.
- **Suppression is central.** The cortex actively inhibits the weaker eye's input to avoid diplopia.
  Any credible modern approach targets suppression, not just acuity.
- **Refractive correction comes first.** Up to a third of children improve to normal on glasses alone
  ("refractive adaptation"), over ~18 weeks. Any app that doesn't tell the user to get properly
  corrected glasses first is doing them a disservice.

---

## 2. THE EVIDENCE HIERARCHY (drives our "evidence tier" labels on every exercise)

**Tier A — RCT evidence in humans with amblyopia**

- **Contrast-rebalanced dichoptic movies.** RCT, 65 children aged 3–7. Dichoptic movies 3×/week vs
  patching 14 h/week. BCVA improved 0.07 ± 0.02 logMAR (movies) vs 0.06 ± 0.01 logMAR (patching) at
  2 weeks, with continued gains to 6 weeks. Conclusion: at-home binocular movie viewing produced
  improvement comparable to patching at far lower time cost. [S1][S2][S6]
- **Luminopia One.** FDA De Novo 2021 for ages 4–7, expanded clearance 2025 to ages 4–<13, for
  amblyopia associated with anisometropia and/or mild strabismus. Dose: **1 hour/day, 6 days/week,
  12 weeks**, on top of full-time spectacle correction. Significant improvement seen as early as
  4 weeks. Real-world registry (PUPiL) shows gains are stable. [S3][S4][S5]
- **NovaSight CureSight.** FDA-cleared 2022 for ages 4–8. Dose: **1.5 hours/day, 5 days/week,
  16 weeks (~120 h total)**. Reported ~3 lines gain vs ~2 lines for patching. [S3]
- **Gamified binocular treatment vs conventional patching.** RCT, published 2025. [S7]
- **BALANCE (balanced binocular viewing).** Phase 2a randomised feasibility trial, ages 3–8. [S8]
- **High-adherence dichoptic vs patching** in anisometropic and small-angle strabismic amblyopia, RCT,
  AJO 2024. [S9]

**Tier B — perceptual-learning evidence, largely in adults, smaller/non-randomised**

- Gabor-patch orientation-discrimination training: ~1.5 lines gain after 10 daily sessions in adults
  with anisometropic amblyopia. Larger series report mean 2.6 logMAR-line improvement and ~75%
  contrast-sensitivity improvement. [S10][S11][S12]
- Lateral-masking / flanked-Gabor contrast-detection training. [S13]
- Key finding for our marketing: **the adult visual cortex retains meaningful plasticity.** Adults are
  a legitimate audience, contrary to the "must treat before age 8" folklore. Gains are real but
  modest, and transfer to everyday vision is variable.

**Tier C — traditional orthoptic / vision-therapy exercises**

Pursuits, saccades, vergence ranges, Brock string, Hart chart, anti-suppression red/green work.
Standard in optometric vision therapy. Evidence is strongest for **convergence insufficiency** (CITT
trial), weaker and largely uncontrolled for amblyopia specifically. We ship them because they are what
users expect and they improve engagement — but they are labelled Tier C in-app and never presented as
the primary mechanism.

**Tier D — no credible evidence.** Colour-flashing screens, "eye yoga", palming, Bates method,
staring at moving dots to "exercise the eye muscle". **We ship none of these.** The reference app is
largely Tier D.

---

## 3. DOSING MODEL WE WILL USE

Derived from the cleared devices above, scaled down honestly because we are a wellness app, not a
prescription device.

| Track | Session | Frequency | Programme length |
|---|---|---|---|
| Dichoptic (primary) | 20–30 min | 5–6 days/week | 12 weeks, re-assessed every 4 |
| Monocular (secondary, patched) | 10–15 min | daily | alongside |
| Assessment battery | ~6 min | weekly (day 7) | ongoing |
| Kids mode cap | 20 min hard cap/day | — | parent-gated override |

**Adherence is the strongest predictor of outcome in every one of the studies above.** So adherence is
our primary in-app metric and the thing the AI coach optimises for — not raw difficulty.

**Stopping rule, implemented in code:** if the weekly assessment shows no improvement across two
consecutive 4-week blocks, the app surfaces a non-dismissible card recommending the user see an eye
care professional. Mirrors clinical practice ("not worthwhile to continue patching beyond ~6 months
without improvement") and is a genuine safety behaviour.

---

## 4. WHAT DICHOPTIC MEANS IN PRACTICE ON AN iPAD

You must present a **different image to each eye simultaneously**, with the **amblyopic eye getting
high contrast** and the **fellow eye getting reduced contrast**, and make the task **impossible to
complete unless both eyes contribute** (that's the anti-suppression forcing function).

Consumer options, ranked by practicality on iPad:

| Method | Hardware | Verdict |
|---|---|---|
| **Red-cyan anaglyph** | ~$5 cardboard glasses | **Chosen.** Universal, cheap, works on any display, no pairing. Downside: colour-limited stimuli, some crosstalk. |
| Passive-polarised | Polarised glasses + polarised display film | Not viable on stock iPad. |
| Shutter glasses | Active 3D glasses + 120 Hz sync | ProMotion iPads could do it, but no consumer shutter glasses pair with iPadOS. |
| Vision Pro | $3.5k headset | Best possible fidelity, tiny market. Note as future track only. |
| Split-screen + cardboard viewer | Google-Cardboard-style holder | Fallback option for users who dislike anaglyph; spec'd as v2. |

**Anaglyph engineering notes for Phase 7:**

- Use **red / cyan** (not red/green). Amblyopic eye behind the **red** filter by default, but make it
  swappable in calibration.
- Everything the amblyopic eye must see is drawn in pure red channel; everything the fellow eye must
  see is drawn in the green+blue channels; shared/fusion elements are drawn in white.
- **Crosstalk (ghosting) is the enemy.** Calibrate per-user: show a red-only patch and a cyan-only
  patch and have the user slide until each is invisible to the wrong eye. Store the leakage
  coefficients and subtract them from every rendered frame.
- **Contrast rebalancing is a per-user, per-session parameter** `fellowEyeContrast ∈ [0.1, 1.0]`. Start
  at the level where the user can just barely fuse, then ramp toward 1.0 as suppression weakens. This
  ramp IS the therapy.
- Colour-blind users cannot use anaglyph reliably — detect during calibration and route them to the
  monocular track without shaming them.

---

## 5. COMPETITOR TEARDOWN

| App | Model | Strength | Weakness we exploit |
|---|---|---|---|
| **Amblyopia – Lazy Eye** (reference, `id1483770938`) | Paid, one-off | Established keyword ranking, 4.1★ | 2019 Unity build, 20 Tier-C/D exercises, unmuteable sound, no progress, no binocular, ugly, no iPad optimisation |
| **AmblyoPlay** | Subscription + hardware box | Genuine clinical partnerships, well-known brand, doctor network | Expensive, requires their kit, heavy sign-up, not a casual download |
| **Lazy Eye Games & Exercises** | Freemium, 50+ games | Big content volume, free tier, no ads | Shallow per-exercise design, no measurement, no adaptivity |
| **Amblyopia Lazy Eye Exercise Apps** (bundle) | $11.99 bundle | Cheap | Four thin apps stapled together |
| **Duovision** | Subscription | Correct binocular concept | Not available in US/Canada — a whole market open to us |
| **Vivid Vision** | Clinic/VR, prescription | Best-in-class anti-suppression + disparity tuning | Headset + clinic gated, not a consumer iPad app |

**Positioning gap we occupy:** *the only consumer iPad app that does real contrast-rebalanced dichoptic
training with measurement and adaptivity, with no hardware beyond $5 glasses.*

---

## 6. REGULATORY REALITY — READ THIS BEFORE WRITING ANY COPY

- Luminopia and CureSight are **FDA-cleared prescription medical devices.** We are not. We must never
  imply equivalence.
- App Store Guideline 1.4.1: *"Medical apps that could provide inaccurate data or information, or that
  could be used for diagnosing or treating patients may be reviewed with greater scrutiny… Apps should
  remind users to check with a doctor in addition to using the app and before making medical
  decisions."*
- Developers report rejections under 1.4.1 **even for wellness-framed apps**, so framing alone is not
  sufficient — the disclaimers, the doctor prompt, and the review notes all have to be right.
- Practical rule for all copy: describe **what the user does** ("guided visual training exercises",
  "contrast-based binocular tasks"), never **what happens to their disease** ("cures lazy eye",
  "improves visual acuity by 2 lines").

Full guideline-by-guideline checklist in `08-COMPLIANCE-LEGAL.md`.

---

## 7. SAFETY CONSTRAINTS DERIVED FROM RESEARCH

| Constraint | Reason |
|---|---|
| No flicker between 3 Hz and 60 Hz, no full-field luminance inversion | Photosensitive epilepsy. High-contrast oscillating gratings are a known trigger class. |
| Session length capped at 30 min, mandatory 20-20-20 break prompt every 20 min | Digital eye strain; also the reference app's "does this damage my eyes / I'm doing this in a dark room" reviews. |
| Ambient-light guidance: **normal room lighting, not a dark room** | The reference app instructs "dark room". A bright display in a dark room maximises discomfort and glare for no benefit. Publicly documented complaint. |
| Viewing distance calibration required before first session | Otherwise stimulus angular size is unknown and every "difficulty level" is meaningless. |
| Occlusion reminder: never patch the amblyopic eye; never patch a child without professional guidance | Occlusion amblyopia (harming the good eye) is a real, documented iatrogenic risk. |
| Age gate: under-13 flows require a parent gate and a "have you seen an eye doctor?" step | 1.4.1 + Kids Category rules + genuine duty of care. |

---

## 8. WHAT THE OLD APP'S USERS ACTUALLY ASKED FOR

From the review screenshots supplied:

1. **"Turn off the noise!!!!!"** — two separate reviews, one 1★, one 3★ ("so annoying I could not even get past it"). Sound is a conversion killer.
2. **"Does it work?"** / "I'm insecure about my eye and don't want it to get worse" — users want reassurance and evidence, not just exercises.
3. **"Being in a dark room doing this, doesn't it damage your eyes?"** — the dark-room instruction actively creates anxiety.
4. **"My eye starts getting tired, does this mean it's working?"** — the developer answered *"Eye fatigue indicates a beneficial effect. Continue the exercises."* That is **wrong and unsafe advice.** Fatigue is a signal to stop and rest. We will say so.
5. **"Will this align my eyes?"** — users confuse amblyopia with strabismus. We need an explainer that distinguishes them.
6. Adult users with macular degeneration self-prescribing an amblyopia app — we need clear "who this is and is not for" content.

Fully mapped to fixes in `14-REVIEW-COMPLAINTS-MATRIX.md`.

---

## SOURCES

- [S1] [Randomized clinical trial of streaming dichoptic movies versus patching for treatment of amblyopia in children aged 3 to 7 years — PMC8905014](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8905014/)
- [S2] [Randomized clinical trial of streaming binocular contrast-rebalanced dichoptic movies versus patching — ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S109185312200180X)
- [S3] [Understanding Digital Treatments for Amblyopia — American Academy of Ophthalmology](https://www.aao.org/young-ophthalmologists/yo-info/article/understanding-digital-treatments-for-amblyopia)
- [S4] [Luminopia Announces FDA Clearance for Patients with Amblyopia Aged 8 to 12 Years](https://www.prnewswire.com/news-releases/luminopia-announces-fda-clearance-for-patients-with-amblyopia-aged-8-to-12-years-302433803.html)
- [S5] [Real world gains stable in children with amblyopia following digital dichoptic treatment: PUPiL registry results — PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC13123015/)
- [S6] [Binocular amblyopia treatment with contrast-rebalanced movies — PubMed](https://pubmed.ncbi.nlm.nih.gov/31103562/)
- [S7] [Comparative effectiveness of gamified binocular treatment versus conventional patching for amblyopia: a randomized clinical trial — PMC](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12477914/)
- [S8] [Feasibility of a new 'balanced binocular viewing' treatment for unilateral amblyopia (BALANCE) — PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC11407205/)
- [S9] [High-Adherence Dichoptic Treatment Versus Patching — American Journal of Ophthalmology](https://www.ajo.com/article/S0002-9394(24)00374-X/fulltext)
- [S10] [Improving vision in adult amblyopia by perceptual learning — PNAS](https://www.pnas.org/doi/10.1073/pnas.0401200101)
- [S11] [An updated review about perceptual learning as a treatment for amblyopia — PMC8712591](https://pmc.ncbi.nlm.nih.gov/articles/PMC8712591/)
- [S12] [Improving visual functions in adult amblyopia with combined perceptual training and tRNS — PMC4260493](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4260493/)
- [S13] [Training to improve contrast sensitivity in amblyopia — PMC5067678](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5067678/)
- [S14] [Binocular Approaches in Amblyopia Treatment Based on Dichoptic Stimulation — Turkish Journal of Ophthalmology](https://oftalmoloji.org/articles/binocular-approaches-in-amblyopia-treatment-based-on-dichoptic-stimulation/tjo.galenos.2025.06626)
- [S15] [Real-World Evidence Supports Dichoptic Therapy for Amblyopia — Cleveland Clinic ConsultQD](https://consultqd.clevelandclinic.org/real-world-evidence-supports-dichoptic-therapy-for-amblyopia)
- [S16] [App Review Guidelines — Apple Developer](https://developer.apple.com/app-store/review/guidelines/)
- [S17] [Clarification needed: Our app is wellness-only but still flagged as medical (Guideline 1.4.1) — Apple Developer Forums](https://developer.apple.com/forums/thread/807508)
- [S18] [AmblyoPlay](https://www.amblyoplay.com/)
- [S19] [Duovision — the lazy eye (amblyopia) app](https://duovision.com/app-against-amblyopia/)
- [S20] [Amblyopia – Lazy Eye (reference app)](https://apps.apple.com/us/app/amblyopia-lazy-eye/id1483770938)
