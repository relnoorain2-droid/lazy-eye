# 08 — COMPLIANCE & LEGAL

The highest-risk part of this project. A health app with subscriptions and children touches four of
App Review's most aggressive guidelines simultaneously.

---

## 1. GUIDELINE-BY-GUIDELINE CHECKLIST

| Guideline | Risk | What we do |
|---|---|---|
| **1.1.6 Objectionable — false information** | Med | Every efficacy statement is tier-labelled and links to the study type. No invented statistics. No before/after "success stories". |
| **1.3 Kids Category** | Med | We **do not** opt into the Kids Category in v1.0 — it forbids most third-party links and complicates subscriptions. We support children through Kids **mode** with a 4+ age rating. Revisit in v1.1. |
| **1.4.1 Physical harm / medical** | **HIGH** | See §2 and §3 below. |
| **2.1 App completeness** | Med | Review account not needed (no login). Demo notes explain the anaglyph glasses. Ship a "Reviewer Mode" toggle in review notes that unlocks Pro so the reviewer sees everything. |
| **2.3.1 Hidden features** | Med | Reviewer Mode must be documented in the review notes, not hidden. |
| **2.5.1 Private APIs** | Low | None used. |
| **3.1.1 / 3.1.2 IAP & subscriptions** | **HIGH** | Full checklist in `07` §5. |
| **4.2 Minimum functionality** | Low | 32 exercises, assessment, analytics — well clear. |
| **5.1.1 Data collection & storage** | Med | No account, no collection. Health-adjacent data stays on device. Privacy policy required and provided. |
| **5.1.1(ix) Health research** | Low | We conduct no research and collect no data — say so explicitly in review notes. |
| **5.1.2 Data use & sharing** | Low | Nothing shared. HealthKit data (v1.1) never leaves the device and is never used for advertising — the HealthKit rules are strict and absolute here. |
| **5.1.4 Kids** | **HIGH** | No behavioural advertising, no third-party analytics, parent gate on purchases and settings, no external links outside the parent gate. |
| **5.2.1 / 5.2.5 IP** | Med | Do not use "Luminopia", "CureSight", "AmblyoPlay", "Vivid Vision" anywhere. Do not use the reference app's screenshots, copy, or name styling. Sloan letters and Landolt C are public-domain optotypes — fine. |

---

## 2. THE 1.4.1 PROBLEM, STATED PLAINLY

Apple's text: *"Medical apps that could provide inaccurate data or information, or that could be used
for diagnosing or treating patients may be reviewed with greater scrutiny… Apps must clearly disclose
data and methodology to support accuracy claims relating to health measurements, and if the level of
accuracy or methodology cannot be validated, the app will be rejected… Apps should remind users to
check with a doctor in addition to using the app and before making medical decisions."*

Developers report 1.4.1 rejections **even for explicitly wellness-framed apps.** Framing alone is not a
defence. Three things have to be true simultaneously:

1. **No treatment claims anywhere** — app name, subtitle, keywords, description, screenshots, in-app
   copy, or the AI coach's output.
2. **Our measurements are never presented as clinical measurements.** The acuity check is labelled
   *"training score — not a clinical eye test"* every single place it appears, including on the chart
   axis and in the exported PDF.
3. **The app actively directs users to professional care** — in onboarding, in Settings, and
   automatically via the plateau escalation rule.

---

## 3. LANGUAGE RULES — BANNED AND APPROVED

### Banned everywhere (metadata, UI, coach output, screenshots)

```
treat · treats · treatment · therapy · therapeutic · cure · cures · heal · fix
diagnose · diagnosis · diagnostic · screen for · test for
medical · clinical · clinically proven · doctor-recommended · FDA · prescription
improve your vision · improve your eyesight · restore vision · correct lazy eye
straighten your eye · replace patching · alternative to patching
guaranteed · proven results · X% improvement
```

Two exceptions, and only these: the phrase *"not a medical device"* and *"not a substitute for
professional medical care"* in disclaimers, and the neutral **noun** "amblyopia"/"lazy eye" used to
describe **who the app is for** (e.g. "designed for people with amblyopia") — never what it does to it.

### Approved vocabulary

```
visual training · vision exercises · eye training · guided practice
binocular training · contrast-balanced exercises · anti-suppression exercises
training score · practice session · adherence · progress
supports your practice · designed for people with amblyopia
based on published research into binocular visual training
```

### The rewrite pattern

| ❌ Never | ✅ Instead |
|---|---|
| "Treats lazy eye at home" | "At-home visual training exercises for people with lazy eye" |
| "Clinically proven to improve vision" | "Built on published research into binocular visual training" |
| "Improve your visual acuity by 2 lines" | "Track your training scores week by week" |
| "Better than patching" | "Designed to complement the plan your eye doctor gave you" |
| "Diagnose your lazy eye" | "Not a diagnostic tool — see an eye care professional" |

**Enforcement:** add a CI step (`scripts/lint_claims.py`) that greps the banned list across
`App/Resources/`, `fastlane/metadata/`, and all Swift string literals, and **fails the build** on a hit.
This is the single cheapest insurance policy in the project.

---

## 3A. REFERENCES & METHODOLOGY DISCLOSURE

**Your instruction: "use reference if you feel any part related to medical — with reference it gets
approved."** That is half right, and the half that's wrong is expensive. Here is the accurate version.

### What citations DO buy you

Guideline 1.4.1 says: *"Apps must clearly disclose data and methodology to support accuracy claims
relating to health measurements, and if the level of accuracy or methodology cannot be validated, the
app will be rejected."*

That is a **methodology disclosure requirement**, and it is exactly what citations satisfy. When we
say "this exercise uses a 3-down/1-up adaptive staircase converging on the 79.4% correct point" and
cite the psychophysics literature, we have disclosed our methodology and it is validatable. A reviewer
can see we are not making numbers up. **This materially improves approval odds**, and it is why every
exercise ships an `EvidenceBadge` and every score screen links to `evidence-and-methods.md`.

### What citations DO NOT buy you

A citation about **Luminopia's** results is evidence about **Luminopia**, not about Amblyo. Apple's
reviewers understand this distinction, and the rejection language for it is blunt. So:

| ❌ Citing this does not let you say | Why |
|---|---|
| "Clinically proven to improve vision (Holmes et al., 2021)" | The study tested a different, FDA-cleared product. Our app was not in it. |
| "Studies show 2 lines of improvement" | Implies our app produces that result. It's an efficacy claim wearing a lab coat. |
| "Research-backed treatment for amblyopia" | "Treatment" is banned regardless of what follows it. |
| "Based on FDA-cleared technology" | We are not cleared and cannot borrow someone else's clearance. Using "FDA" at all invites a request for documentation we do not have. |

**The rule: cite the METHOD, never borrow the OUTCOME.**

| ✅ Safe, citation-supported phrasing |
|---|
| "Contrast-rebalanced binocular viewing — the approach studied in Kelly et al. (2016) and Holmes et al. (2021) — presents a different image to each eye." |
| "Difficulty is set using a 3-down/1-up adaptive staircase, a standard psychophysical method (Levitt, 1971)." |
| "Orientation-discrimination training with Gabor patches has been studied in adults with amblyopia (Polat et al., 2004)." |
| "This exercise type is supported by randomised controlled trials in children with amblyopia. Those trials tested purpose-built medical devices, not this app." ← **the last sentence is what makes it safe** |

**Every Tier A and Tier B evidence sheet in the app must end with that disclaimer sentence.** It is
the single most important sentence in the compliance strategy: it gives the user the honest context,
and it shows the reviewer we understand the boundary rather than skirting it.

### Where references appear

| Location | Form |
|---|---|
| `EvidenceBadge` tap sheet | 1–3 citations for that exercise type + the boundary sentence |
| `Learn/evidence-and-methods.md` | Full reference list, every source from `01-RESEARCH-BRIEF.md`, grouped by tier, with a plain-English "what this study actually showed / what it does not show about this app" line under each |
| Progress screen footer | "How these scores are calculated" → methodology + citation |
| App Review notes | A short reference list (see the addition to §8 below) |
| Support website `/evidence` | Public mirror of `evidence-and-methods.md` |

### Citation format in-app

Plain, readable, no hyperlinks (offline app, and external links in a kids-adjacent app are a 5.1.4
risk). Author, year, journal, study type:

> Holmes JM et al. (2021). *Effect of a Binocular iPad Game vs Part-time Patching in Children Aged 5
> to 12 Years With Amblyopia.* JAMA Ophthalmology. **Randomised controlled trial.**
> *What it showed:* a binocular iPad game and part-time patching were compared in children.
> *What it does not show:* anything about Amblyo. Amblyo was not studied.

### ⚠️ The trap to avoid

Do not let the citations tempt you into stronger marketing language than the app copy allows. The
description, subtitle, keywords, and screenshots stay under §3's banned-word rules **even though** you
have references. References live in the app's evidence sheets and on your website — **not in App Store
metadata**, where a citation next to a price reads as a medical claim to a reviewer scanning quickly.

---

## 4. IN-APP LEGAL SCREENS (`App/Features/Legal/`)

Bundled Markdown rendered by `ArticleView`. No web views, no external links from the paywall (your
requirement, and also a 5.1.4 kids benefit).

| File | Reachable from |
|---|---|
| `medical-disclaimer.md` | Onboarding step 2 (must be acknowledged) · Settings · footer of Progress |
| `privacy-policy.md` | Paywall · Settings · onboarding |
| `eula.md` | Paywall · Settings |
| `evidence-and-methods.md` | Every EvidenceBadge · Learn |

### `medical-disclaimer.md` — full text, ship as-is

```markdown
# Important — please read

**Amblyo is a visual training app. It is not a medical device, and it is not a
medical treatment.**

Amblyo does not diagnose, treat, cure, or prevent any condition. The exercises
in this app are practice activities based on published research into binocular
visual training. They are not a substitute for care from a qualified eye care
professional.

**Before you start**

- See an optometrist or ophthalmologist for a proper eye examination.
- If you have been prescribed glasses or contact lenses, wear them.
- If you have been given a treatment plan — including patching — follow it.
  Use Amblyo alongside that plan, not instead of it.
- Do not cover or patch a child's eye without professional guidance. Covering
  the wrong eye can cause harm.

**Amblyo is not suitable for you if you have**

- Macular degeneration, glaucoma, or other retinal or optic nerve disease
- Had eye surgery in the last three months
- New or worsening double vision
- Sudden or recent loss of vision
- Photosensitive epilepsy or a history of seizures triggered by visual patterns

**Stop and rest if** your eyes feel tired, sore, or strained, or if you get a
headache. Eye strain is a signal to stop — not a sign that the exercise is
working.

**The scores in this app are training scores, not clinical measurements.** They
are useful for tracking your own practice over time. They cannot tell you what
your real visual acuity is, and they cannot replace an eye examination.

**See an eye care professional** if your vision changes, if you have any concern
about your eyes, or before making any decision about your eye care.
```

### `privacy-policy.md` — outline (write the full text in Phase 10)

1. Who we are, contact email
2. **What we collect: nothing.** No account, no email, no analytics, no advertising identifiers
3. What stays on your device: profiles, sessions, trial results, assessment results, settings
4. HealthKit (v1.1): read with permission, never leaves the device, never used for advertising, never shared
5. Purchases: handled by Apple; we receive no payment details; Apple's own privacy policy applies
6. Children: no data collected from anyone, including children; no behavioural advertising
7. Your controls: export all data, delete all data, delete a profile
8. Changes to this policy; effective date
9. Contact

### `eula.md`

Use **Apple's Standard EULA** unless you have a specific reason not to — link it in App Store Connect
and reproduce it in-app. If you write a custom one, it must be at least as protective of the user as
Apple's, and Apple must be able to see it at the metadata URL. A custom EULA must cover: licence grant,
subscription terms and auto-renewal, no medical advice / assumption of risk, limitation of liability,
governing law, termination, contact.

---

## 5. EXTERNAL PAGES YOU MUST HOST (for App Store Connect metadata)

Your paywall uses in-app screens — but App Store Connect **separately requires public URLs**. Two
pages, on any host (Google Sites is fine, as you planned):

| Field | Page | Must contain |
|---|---|---|
| Privacy Policy URL | `.../privacy` | Same content as `privacy-policy.md`, plus a last-updated date and a contact email |
| Terms of Use (EULA) URL | `.../terms` | The EULA, plus the auto-renewal disclosure |
| Support URL | `.../support` | Contact email, an FAQ, a "how to cancel" section, and the medical disclaimer |
| Marketing URL (optional) | `.../` | Landing page |

Both privacy and terms URLs must be **live and reachable before you submit** — dead links are an
instant metadata rejection. Put the medical disclaimer on the support page too; a reviewer investigating
1.4.1 will look there.

---

## 6. APP PRIVACY ("nutrition label") ANSWERS

Target for v1.0: **"Data Not Collected."** To keep that true:

- No third-party SDKs of any kind
- No `IDFA`, no `ATTrackingManager`
- No crash reporting beyond Apple's opt-in system diagnostics
- No network calls other than StoreKit
- If you add CloudKit sync in v1.1, the answer becomes "Health & Fitness — linked to you — App
  Functionality." That is acceptable, but it is a real change; update the label deliberately.

**Privacy manifest (`PrivacyInfo.xcprivacy`)** is required. Declare: no tracking, no collected data
types, and required-reason API usage — you will need `NSPrivacyAccessedAPICategoryUserDefaults`
(reason `CA92.1`) and `NSPrivacyAccessedAPICategoryFileTimestamp` if you touch file dates.

---

## 7. AGE RATING

Answer the App Store Connect questionnaire as: no violence, no sexual content, no gambling, no
unrestricted web access, no user-generated content. Expected rating **4+**.

Do **not** claim "Made for Kids" in v1.0 (see §1, 1.3).

---

## 8. APP REVIEW NOTES — DRAFT (paste into App Store Connect)

```
Thank you for reviewing Amblyo.

WHAT THIS APP IS
Amblyo is a visual TRAINING app — a set of guided eye exercises for people who
have been diagnosed with amblyopia (lazy eye) by an eye care professional.

IT IS NOT A MEDICAL APP
- It does not diagnose, treat, cure, or prevent any condition.
- It makes no medical claims anywhere in the app or metadata.
- It contains no medical hardware integration.
- Onboarding step 2 requires the user to acknowledge a medical disclaimer that
  directs them to see an eye care professional and lists contraindications.
- All in-app scores are labelled "training score, not a clinical measurement."
- If a user shows no measured change over 8 weeks, the app automatically shows a
  non-dismissible card recommending they see an eye care professional.

PRIVACY
- No account, no sign-in, no analytics, no third-party SDKs.
- The app makes no network requests other than StoreKit.
- All data is stored locally and can be exported or deleted by the user.
- App Privacy label: Data Not Collected. This is accurate.

METHODOLOGY DISCLOSURE (Guideline 1.4.1)
Every exercise in the app carries an evidence badge. Tapping it shows the type
of published research that supports that category of exercise, in plain
English, together with an explicit statement that those studies tested other
products and not this app. The full reference list is in the app at
Learn > Evidence and Methods, and publicly at https://sites.google.com/view/amblyolazyeyetraining/evidence-and-methods.

Our adaptive difficulty uses a 3-down/1-up transformed staircase (Levitt, 1971),
a standard psychophysical method. The in-app "training scores" are threshold
estimates from that procedure. They are labelled throughout as training scores
and explicitly NOT as clinical measurements, because they are uncalibrated
against any clinical standard. We make no accuracy claim about them.

TO TEST THE FULL APP
Settings → About → tap the version number 5 times to enable Reviewer Mode,
which unlocks all subscription content without purchase.

ABOUT THE RED-CYAN GLASSES
The "Dichoptic" exercises are designed to be viewed with inexpensive red-cyan
anaglyph glasses. They are fully usable and testable without them — the app
detects that in calibration and offers a preview mode. All "Monocular"
exercises and all core functionality require no accessory.

SUBSCRIPTIONS
Auto-renewing subscriptions, weekly / monthly / yearly, in one group. The
paywall displays exact price and duration for each plan, a per-week
equivalent, the auto-renewal terms, how to cancel, Restore Purchases, and
in-app Terms of Use and Privacy Policy. A full exercise is playable before the
paywall is ever shown.

Contact: <your email>
```

---

## 9. PRE-SUBMISSION COMPLIANCE GATE (Phase 13)

- [ ] `scripts/lint_claims.py` passes on all Swift, all Markdown, and all fastlane metadata
- [ ] Medical disclaimer is acknowledged in onboarding and re-reachable from Settings
- [ ] Every score display carries the "training score" qualifier
- [ ] Contraindication list present and reachable
- [ ] Escalation rule verified with a simulated 8-week no-improvement history
- [ ] Paywall passes the `07` §5 checklist item by item, screenshotted as evidence
- [ ] Privacy, Terms, and Support URLs live and returning 200
- [ ] `PrivacyInfo.xcprivacy` present and accurate
- [ ] App Privacy questionnaire answered as Data Not Collected
- [ ] Age rating questionnaire completed
- [ ] Review notes pasted, Reviewer Mode verified working on a TestFlight build
- [ ] No competitor trademark appears in any metadata or asset
- [ ] `evidence-and-methods.md` complete, every Tier A/B sheet ends with the boundary sentence (§3A)
- [ ] No citation appears anywhere in App Store metadata (§3A, "the trap")
- [ ] `/evidence` page live on the support site
