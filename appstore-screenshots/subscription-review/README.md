# SUBSCRIPTION REVIEW SCREENSHOT

This is **not** a marketing screenshot. It goes in a different place and it has
different rules.

## Where it goes

App Store Connect → **Subscriptions** → open each subscription →
**Review Information** → *Screenshot*.

**Upload the same image to all three.** Weekly, monthly and yearly all appear on
this one paywall, so one screenshot documents all of them. There is no
requirement that each product gets a different picture.

## Which file

| File | Use |
|---|---|
| `paywall-review.png` | **Upload this one.** Same capture, with the `◀ TestFlight` marker replaced by a neutral status bar. |
| `paywall-original.png` | The untouched capture, kept so you can see exactly what was changed. |

**Only the status bar was edited.** The prices, the button, the plan list and the
auto-renew paragraph are exactly as the app drew them. Retouching a purchase
screen for App Review is misrepresenting the flow being reviewed — a much worse
problem than an unflattering screenshot.

## What Apple is actually checking here

Not the design. They are checking that the paywall discloses, before purchase:

- the subscription **name and what it unlocks** — "Every exercise", "Your full
  history", "Up to 5 people" ✓
- the **price and duration** of each option — $29.99/year, $9.99/month,
  $2.99/7 days ✓
- that it **auto-renews**, and how to cancel — the paragraph at the bottom ✓
- **Restore Purchases**, visible without buying anything ✓ (Guideline 3.1.1)

All four are present in this capture. That is why it is usable as it stands.

## Two flaws, and why I did not "fix" them

**1. The Subscribe button is greyed with a spinner.**
It was captured mid-purchase-attempt, so the button is in its disabled loading
state. A reviewer sees a purchase screen whose main button looks dead.

**2. The headline is scrolled under the toolbar.**
"Unlock the full programme" sits half-hidden behind the *Not now* pill, which
reads as a layout fault rather than a scroll position.

Both are fixable in thirty seconds by re-capturing, and **not** fixable in an
image editor without lying about what the app does.

## The better version, if you have a minute

On the new TestFlight build:

1. Open the app → **Train** → tap any locked exercise, or Profile → **See plans**.
2. **Scroll the sheet to the very top** so "Unlock the full programme" is fully
   visible.
3. Do **not** tap Subscribe. Just make sure a plan is selected so the button is
   dark and active.
4. Screenshot.
5. Drop it in this folder as `paywall-original.png` and re-run:

   ```
   python3 -c "import sys; sys.path.insert(0,'scripts'); import importlib.util; \
   spec=importlib.util.spec_from_file_location('mk','scripts/make_screenshots.py'); \
   mk=importlib.util.module_from_spec(spec); spec.loader.exec_module(mk); \
   from PIL import Image; \
   mk.clean_status_bar(Image.open('appstore-screenshots/subscription-review/paywall-original.png').convert('RGB'),150) \
   .save('appstore-screenshots/subscription-review/paywall-review.png')"
   ```

The current file will pass. A clean one just looks like a product rather than a
build.
