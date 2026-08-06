# 11 — SCREENSHOTS & APP PREVIEW

The reference app's screenshots are raw, uncaptioned in-game frames — a black dot field with a green
dot, on a phone. They communicate nothing. **Captioned, framed screenshots are the single highest-ROI
conversion asset on the product page**, and the first two are what most users actually see.

---

## 1. REQUIRED SIZES (2026)

You must upload at least one set per device class your app supports. Apple scales down from the
largest, so **produce two sets only**:

| Device class | Pixels (portrait) | Required? |
|---|---|---|
| **iPhone 6.9"** | **1320 × 2868** | Yes — the primary iPhone size. If absent, 6.5" is required instead. |
| **iPad 13"** | **2064 × 2752** | **Yes — mandatory because our app runs on iPad.** |

Landscape variants are the transposed dimensions. 1–10 screenshots per device class per locale.
JPEG or PNG, RGB, no alpha.

**Because we are iPad-first, upload the iPad set first and make it the strongest.** Apple shows the
iPad set to iPad users, which is our primary audience.

---

## 2. THE 8 SCREENSHOTS — ORDER AND COPY

Order matters enormously: on the App Store search results page only the **first 1–3** are visible
without tapping through.

| # | Frame | Caption (large, top) | Subcaption (small) |
|---|---|---|---|
| **1** | Dichoptic exercise mid-session — red and cyan elements clearly visible, with a small red-cyan glasses illustration inset | **Both eyes. One task.** | Contrast-balanced exercises you can't finish with one eye |
| **2** | Progress screen with 4 metric tiles and a real trend chart | **See what actually changed.** | Four measures, checked every week — with honest results |
| **3** | Train library on iPad, three track sections, evidence badges visible | **32 exercises. Every one has a reason.** | Tap any badge to see the research behind it |
| **4** | Kids mode reward map with the mascot and a child-friendly game | **Made for kids who hate patching.** | Rewards, a 20-minute cap, and a parent gate |
| **5** | Session summary with the one-sentence coach line | **Adapts after every single answer.** | Laboratory-grade staircase difficulty, on your device |
| **6** | Privacy screen / Settings, "Data Not Collected" prominent | **No account. No servers. No tracking.** | Everything stays on your iPad |
| **7** | Calibration screen showing distance + screen size | **Calibrated to your screen and your distance.** | So a one-degree target really is one degree |
| **8** | Learn article open — "Lazy eye or crossed eye?" | **Understand what you're training.** | Twelve plain-English articles, written from the research |

**Caption rules:**

- SF Pro Display Bold, ~72 pt at 1320 px width (scale for iPad), `textPrimary` on `surfaceBase`
- Caption occupies the top ~22% of the frame; the device screenshot sits below in a subtle device frame
- Maximum 5 words in the headline
- **Run every caption through `08` §3.** "Both eyes. One task." is safe. "Fix your lazy eye" is a
  rejection.
- Localise captions per market, at minimum for `es`, `pt-BR`, `hi`

---

## 3. HOW TO PRODUCE THEM WITHOUT A MAC

Two paths. Do both — path A gets you real pixels, path B gets you polish.

### Path A — capture on the CI runner (real screenshots, automated)

`fastlane snapshot` runs UI tests on simulators and captures screens. It runs on the GitHub Actions
macOS runner, so no Mac is needed.

```ruby
# fastlane/Snapfile
devices([
  "iPhone 17 Pro Max",
  "iPad Pro 13-inch (M4)"
])
languages(["en-US"])
scheme("AmblyoUITests")
output_directory("./fastlane/screenshots")
clear_previous_screenshots(true)
```

```swift
// AmblyoUITests/ScreenshotTests.swift
func testCaptureAll() {
    let app = XCUIApplication()
    setupSnapshot(app)
    app.launchArguments += ["-uitest-seed-demo-data", "-uitest-unlock-pro"]
    app.launch()
    // …navigate…
    snapshot("01_dichoptic")
    snapshot("02_progress")
    // …
}
```

`-uitest-seed-demo-data` populates a realistic 12-week history so the charts look real instead of
empty. Build this seeder in Phase 2; you will use it constantly.

### Path B — frame and caption on Windows

`fastlane frameit` needs a Mac-ish environment, so instead use a Python compositor that runs on your PC:

```
scripts/make_screenshots.py
  ├─ reads  fastlane/screenshots/*.png      (raw captures from Path A)
  ├─ reads  docs/screenshot-captions.json   (the table in §2)
  └─ writes Assets/Screenshots/{device}/{01..08}.png
```

It draws the background, the caption text, a rounded-rect device bezel, and pastes the capture inside.
Pillow only. Deterministic and re-runnable when copy changes — which it will, repeatedly.

If you'd rather not code it: **Screenshots Pro**, **Previewed**, **AppScreens**, or **Figma** with a
device-frame kit all work fine from a browser on Windows. The Python route is preferred because it
regenerates all 16 images (8 × 2 device classes) in seconds after every copy tweak.

---

## 4. APP PREVIEW VIDEO (optional but high-value)

15–30 s, up to 3 per device class, same resolutions as the screenshots.

**Storyboard (22 s):**

| Time | Shot |
|---|---|
| 0–3 s | Icon animates: two circles slide together, centre blooms white |
| 3–7 s | Hands put on red-cyan glasses; iPad shows a dichoptic exercise |
| 7–12 s | Fast cuts: three different exercises, each with its evidence badge visible |
| 12–16 s | Progress chart draws itself; the weekly numbers update |
| 16–20 s | Kids mode: a child taps balloons, the reward map fills |
| 20–22 s | Icon + "Amblyo — Lazy Eye Training" |

**Rules:** no audio required (must work muted — most previews autoplay silent), no device frames or
hands *inside* the captured footage (only real app UI), no price claims, no medical claims, all footage
must be actual app content. Capture with the simulator recorder on CI or QuickTime-equivalent via
`xcrun simctl io booted recordVideo`.

---

## 5. CHECKLIST

- [ ] iPad 13" set: 8 screenshots at 2064 × 2752
- [ ] iPhone 6.9" set: 8 screenshots at 1320 × 2868
- [ ] Screenshot 1 is the dichoptic frame — the differentiator, not a menu
- [ ] No screenshot shows a menu, a settings list, or an empty state
- [ ] Every caption passes the `08` §3 language lint
- [ ] Charts contain realistic seeded data, never zeros
- [ ] No alpha channel; RGB; correct exact pixel dimensions
- [ ] Localised captions for wave-1 and wave-2 locales
- [ ] Custom Product Page variants produced (parents set, adults set — see `09` §7)
