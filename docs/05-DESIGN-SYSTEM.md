# 05 — DESIGN SYSTEM

The reference app looks like a 2012 Flash game: hex-pattern background, orange lozenge buttons,
outlined display font, pure black-and-white stimuli. We go the opposite direction: **calm, clinical,
warm.** Think a well-designed sleep or meditation app that happens to be about eyes — because the
emotional job here is reassurance (`14` R3, R5), not excitement.

---

## 1. BRAND

| | |
|---|---|
| **Feeling** | Calm competence. Unhurried. Quietly scientific. |
| **Anti-references** | Neon gamified fitness apps · cartoon medical clip-art · "hacker" dark-mode dashboards |
| **References** | Apple Health, Oura, Headspace's restraint (not its illustration style), Things 3's typography |
| **Motion** | Slow, eased, purposeful. Nothing bounces. Nothing flashes. |
| **Voice** | Second person, plain English, no hype, no medical jargon without a gloss. "Your balance score went from 0.42 to 0.51 this week." Never "Amazing! You crushed it! 🎉" |

---

## 2. COLOUR TOKENS

Defined in `DesignSystem/Tokens.swift` as `Color` extensions backed by an asset catalog with
light/dark variants. **Never hardcode a hex in a view.**

### Core palette

| Token | Light | Dark | Use |
|---|---|---|---|
| `brandPrimary` | `#2D6A6E` deep teal | `#4FA5A9` | Primary actions, active tab |
| `brandSecondary` | `#E8B44A` warm amber | `#F0C468` | Streaks, rewards, highlights |
| `brandAccent` | `#7C6BB5` muted violet | `#9A8AD1` | Dichoptic track identity |
| `surfaceBase` | `#FBFAF7` warm off-white | `#121417` | Screen background |
| `surfaceRaised` | `#FFFFFF` | `#1C1F24` | Cards |
| `surfaceSunken` | `#F1EFE9` | `#0C0E10` | Grouped list background |
| `textPrimary` | `#1A1D21` | `#F2F3F5` | |
| `textSecondary` | `#5C6470` | `#9AA3AE` | |
| `separator` | `#E3E0D9` | `#2A2E34` | |
| `success` | `#2F7D52` | `#4CA877` | |
| `caution` | `#B5701F` | `#DE9A44` | Fatigue, breaks, caps |
| `critical` | `#A63A3A` | `#D96060` | Contraindications, escalation |

### Track identity

| Track | Colour | Icon |
|---|---|---|
| Monocular | `brandPrimary` teal | `eye` |
| Dichoptic | `brandAccent` violet | `eyeglasses` |
| Games | `brandSecondary` amber | `gamecontroller` |
| Assessment | neutral graphite | `chart.line.uptrend.xyaxis` |

### Stimulus colours — **hard rules, not preferences**

- Stimulus rendering ignores the theme entirely. Backgrounds during an exercise are **mid-grey
  (`#808080`, ~50% luminance)**, not black and not white. Mid-grey is required so a Gabor can modulate
  symmetrically around it — a black background makes negative contrast impossible and is why the
  reference app's stimuli are psychophysically meaningless.
- Anaglyph channels are **pure**: red layer `(1,0,0)`, cyan layer `(0,1,1)`, fusion elements
  `(1,1,1)`. No tinting, no gradients, no shadows on stimuli.
- Chrome around a running exercise dims to 20% opacity after 3 s of no interaction.

---

## 3. TYPOGRAPHY

SF Pro throughout — system font means free Dynamic Type, free localisation, zero bundle weight.
`SF Rounded` **only** in Kids mode.

| Style | Size / weight | Use |
|---|---|---|
| `displayLarge` | 34 pt Bold, rounded in kids mode | Onboarding headlines, paywall headline |
| `title` | 28 pt Semibold | Screen titles |
| `headline` | 20 pt Semibold | Card titles |
| `body` | 17 pt Regular | Everything |
| `callout` | 16 pt Regular | Secondary explanation |
| `caption` | 13 pt Regular | Evidence badges, disclaimers, legal |
| `metric` | 44 pt Semibold, **monospaced digits** | Score numerals, timers |

**Dynamic Type must scale to AX5 on every screen.** No fixed-height containers around text.
Legal and disclaimer text is `caption` but must remain ≥ 11 pt effective and pass 4.5:1 contrast —
Apple rejects paywalls whose terms are visually de-emphasised (`07` §5).

---

## 4. SPACING, RADIUS, ELEVATION

4-pt grid: `xs 4 · sm 8 · md 16 · lg 24 · xl 32 · xxl 48`.
Radius: `card 20 · button 14 · chip 10 · sheet 28`.
Elevation: shadows only on floating action elements — `y 4, blur 16, black 6%`. Cards use a 1 pt
`separator` border, not a shadow.

---

## 5. COMPONENTS (`DesignSystem/Components/`)

| Component | Notes |
|---|---|
| `AmblyoButton` | `.primary` filled, `.secondary` tinted, `.tertiary` plain, `.destructive`. Min 50 pt tall, min 44×44 pt hit area. Never uses an icon alone without a label. |
| `AmblyoCard` | Standard container. Optional header, footer, and leading track colour bar. |
| `EvidenceBadge` | Tier A/B/C pill. Tappable → sheet explaining what that tier means and citing the study type. (`14` R5) |
| `MetricTile` | Big number + label + delta arrow + sparkline. |
| `StreakRing` | Progress ring, 7-day. Uses `brandSecondary`. Respects Reduce Motion (no rotation animation). |
| `SafetyBanner` | `.caution` / `.critical` variants. Used for fatigue, breaks, contraindications, escalation. Never dismissible when `.critical`. |
| `MuteControl` | **Always visible in the session nav bar.** Single tap toggles all audio. (`14` R1, R2) |
| `FatigueButton` | Always visible in the session nav bar. Ends the session. (`14` R4) |
| `GlassesPrompt` | "Put your red-cyan glasses on" pre-session card with an illustration and a 3-second live test pattern. |
| `PaywallPlanRow` | Price + period + per-week equivalent + badge. Spec'd exactly in `07` §5. |
| `ParentGate` | Arithmetic challenge (e.g. "7 × 8"), not a birthday picker. Guards settings, paywall, and cap overrides in Kids mode. |
| `ArticleView` | Renders bundled Markdown with Dynamic Type and VoiceOver headings. |

---

## 6. LAYOUT — iPAD FIRST

This is the difference between "an iPhone app that runs on iPad" and an iPad app.

| Context | Structure |
|---|---|
| **iPad regular width** (≥ 1024 pt) | `NavigationSplitView`: sidebar (Today/Train/Progress/Learn/Profile) + detail. Content column max 760 pt, centred, with generous gutters. Two-column card grids on Train and Progress. |
| **iPad compact / Slide Over / Stage Manager narrow** | Collapses to `TabView`. Must be tested at 320 pt wide. |
| **iPhone** | `TabView`, single column. |
| **Session runner (all devices)** | Full-screen, edge-to-edge, no navigation chrome except the mute and fatigue controls in a floating capsule top-right. Status bar hidden. `.persistentSystemOverlays(.hidden)`. Home indicator dimmed. |

**iPad specifics that must actually be implemented:**

- Stage Manager and multi-window: exercises **pause automatically** when the window is not key.
  Psychophysical data from a background window is garbage.
- External display: mirror-only; show a "training works best on the iPad screen" notice, since
  calibration is per-device.
- Apple Pencil: hover preview on `m.tracing`, pressure ignored.
- Hardware keyboard: full shortcuts (Space = pause, Esc = end, ←/→ = 2AFC responses). Adults
  responding on a keyboard produce far cleaner reaction times.
- Portrait and landscape both fully supported — no orientation locks anywhere except the session
  runner, which locks to whatever orientation the session started in (rotating mid-trial invalidates
  angular calibration).

---

## 7. AUDIO — THE MOST IMPORTANT SECTION IN THIS DOCUMENT

The reference app's single worst-reviewed feature (`14` R1, R2). Non-negotiable rules:

1. **Every audio channel defaults to OFF on first install.** Music, sound effects, and voice guidance
   are three independent toggles.
2. A **master mute** appears in the session nav bar at all times, one tap, no confirmation.
3. The setting applies **immediately**, mid-sound. No restart, no "will take effect next session".
4. `AVAudioSession` category `.ambient` with `mixWithOthers` — the hardware silent switch silences the
   app, and the user's own music keeps playing. (Users training for 20 minutes want their own audio.)
5. First launch shows a single card: *"Sounds are off. Turn them on?"* with Yes / No. The user is
   never made to hunt for the setting.
6. Haptics are a separate toggle, also default off for under-13 profiles.
7. **No audio at all is required for any exercise to function.** `g.rhythmTap` ships a visual-only
   mode as its default.

---

## 8. ACCESSIBILITY (`14` R12)

- VoiceOver labels + hints on every interactive element; exercise views expose a text description of
  the current stimulus state.
- Dynamic Type to AX5 on every non-stimulus screen.
- Reduce Motion: all decorative animation removed; exercise motion is functional and stays, but the
  Motion Field and pursuit exercises show a "contains sustained motion" note.
- Reduce Transparency and Increase Contrast honoured.
- **Colour-vision handling:** the anaglyph calibration includes a red/cyan discrimination check. If it
  fails, the user is routed to the monocular track with a plain, non-judgemental explanation — the
  dichoptic track is hidden rather than shown-and-locked.
- Minimum touch target 44×44 pt; 60×60 pt in Under-5 mode.
- Full keyboard navigation on iPad.

---

## 9. KIDS SKIN

Applied when `profile.isKidsMode` is true. **Not a different app — a theme plus three behaviours.**

- SF Rounded, +2 pt sizes, radius 24, brighter `brandSecondary` accents.
- A mascot ("Otto the owl" — owls have famously good vision; placeholder name, confirm in Phase 11)
  appears only at session start and end, never during an exercise.
- Reward map: sessions unlock nodes on a path. **No loot boxes, no currency, no streak-loss anxiety
  mechanics, no timers counting down on screen.** A child should not feel they are failing.
- Parent gate on: Settings, Paywall, session-cap override, profile deletion, data export.
- Session end is celebratory but quiet — a filled ring and one sentence, no confetti explosion.
