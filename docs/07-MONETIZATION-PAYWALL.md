# 07 — MONETIZATION & PAYWALL

StoreKit 2, direct, **no RevenueCat**. Three auto-renewing subscriptions in one group.

---

## 1. PRODUCTS

**FINAL — locked in `DECISIONS.md`, 2026-08-06.**

| Product ID | Display name | Duration | Price (USD) | Per week |
|---|---|---|---|---|
| `com.amblyo.app.pro.weekly` | Amblyo Pro — Weekly | 1 week | **$2.99** | $2.99 |
| `com.amblyo.app.pro.monthly` | Amblyo Pro — Monthly | 1 month | **$9.99** | ≈$2.31 |
| `com.amblyo.app.pro.yearly` | Amblyo Pro — Yearly | 1 year | **$29.99** | ≈$0.58 |

Subscription group: `amblyo_pro` (one group, three levels — required for correct upgrade/downgrade
proration and for `SubscriptionStoreView`). Group ranking: yearly = level 1, monthly = 2, weekly = 3.

---

## 2. PRICING RATIONALE & ECONOMICS

Annualised, the final ladder looks like this:

| Plan | Cost per year | Cost per week | Discount vs weekly |
|---|---|---|---|
| Weekly | $155.48 | $2.99 | — |
| Monthly | $119.88 | $2.31 | 23% |
| Yearly | **$29.99** | **$0.58** | **81%** |

This is a healthy ladder. Yearly is 5.2× cheaper than weekly — a normal, defensible "save 81%"
story rather than the 15.6× gap the original $9.99/yr created, which read as a bait ladder to a
reviewer. Each step down is a visible, proportionate discount.

**Revenue per yearly subscriber:**

| | Commission | Net to you |
|---|---|---|
| Standard | 30% | **$21.00** |
| **App Store Small Business Program** | **15%** | **$25.49** |

**Enrol in the App Store Small Business Program.** If your proceeds are under $1M/year you pay 15%
instead of 30% — that is an extra $4.49 on every yearly subscription for filling in one form in App
Store Connect. Enrolment is not automatic; you must apply, and it takes effect the month after
approval. Do this in Phase 0, before you have revenue to lose.

**Sanity check on positioning:** $29.99/year still undercuts AmblyoPlay by roughly an order of
magnitude and is well below the impulse threshold for a parent. It is not a cheap-looking price for a
serious health app, which matters — under-pricing a medical-category app signals low quality.

**Free trial: 7 days, yearly plan only.** At $29.99 the trial genuinely helps conversion (unlike at
$9.99, where the price was already below the decision threshold). Configure it as an introductory
offer in App Store Connect, never in code, and disclose it per §5 — trial disclosure is the single
most common 3.1.2 rejection in 2026.

**Prices are effectively permanent.** You can raise them later, but existing subscribers keep their
old price unless they explicitly consent, and Apple's price-increase consent flow is a churn event.
Get this right now.

---

## 3. FREE VS PRO

| | Free | Pro |
|---|---|---|
| Onboarding, calibration, safety, Learn articles | ✅ | ✅ |
| Anaglyph calibration | ✅ | ✅ |
| Exercises | **4** (1 monocular, 1 dichoptic, 2 games) | All 32 |
| Daily session length | 10 min | Unlimited (within safety caps) |
| Adaptive difficulty | ✅ (it's a safety feature, never paywalled) | ✅ |
| Weekly assessment | 1 of 4 sub-tests | All 4 |
| Progress history | Last 7 days | Full history + trends |
| AI coach | ❌ | ✅ |
| Multiple profiles | 1 | 5 |
| PDF report export | ❌ | ✅ (v1.1) |
| Ads | none, ever | none, ever |

**The free tier must be genuinely usable.** A reviewer who cannot reach any real content before a
paywall is the most common 3.1.2 rejection cause. One full free exercise runs *before* the paywall is
ever shown (`02` §5).

**Free trial:** 7 days on the yearly plan only, via an introductory offer configured in App Store
Connect (not in code). See §5 for the disclosure this obligates you to.

---

## 4. IMPLEMENTATION PLAN (`App/Purchases/`)

```swift
@Observable @MainActor
final class SubscriptionManager {
    private(set) var products: [Product] = []
    private(set) var status: EntitlementStatus = .unknown   // unknown | free | pro(expires:) | inGracePeriod | inBillingRetry
    private var updatesTask: Task<Void, Never>?

    func start() async {
        updatesTask = listenForTransactions()      // MUST start at app launch, before any UI
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        products = (try? await Product.products(for: ProductID.all)) ?? []
    }

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()             // ALWAYS finish, or it replays forever
            await refreshEntitlements()
            return true
        case .userCancelled, .pending: return false
        @unknown default: return false
        }
    }

    func restore() async throws {
        try await AppStore.sync()                  // wire to an explicit "Restore Purchases" button
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var newStatus: EntitlementStatus = .free
        for await result in Transaction.currentEntitlements {
            guard let t = try? checkVerified(result),
                  ProductID.all.contains(t.productID) else { continue }
            if t.revocationDate == nil { newStatus = .pro(expires: t.expirationDate) }
        }
        // Subscription.Status gives grace period / billing retry — surface these,
        // don't just cut the user off mid-programme.
        status = newStatus
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let t = try? await self?.checkVerified(update) else { continue }
                await t.finish()
                await self?.refreshEntitlements()
            }
        }
    }
}
```

**Non-obvious things that will bite you:**

- `Transaction.updates` **must** be listening before the first UI appears, or an Ask-to-Buy approval or
  a purchase made on another device arrives while nobody is listening.
- Always call `transaction.finish()`. Unfinished transactions are re-delivered forever.
- Handle **grace period** and **billing retry** — a parent's card expiring mid-programme should show a
  fix-payment banner, not an abrupt lockout. This directly prevents 1★ reviews.
- Handle `revocationDate != nil` (refunds) by dropping entitlement immediately.
- **Ask to Buy** (Family Sharing, children) returns `.pending`. Show "waiting for a parent to approve",
  not an error. This matters enormously for a children's health app.
- Product IDs are hardcoded here for v1.0 simplicity. Apple's own guidance prefers a remote list — but
  a remote list means a network call and breaks our "no network" privacy claim. **Keep them local**,
  and accept that adding a product needs an app update.
- Test everything with the **StoreKit Testing framework** and a local `.storekit` file: purchase,
  restore, expiry, refund, grace period, billing retry, Ask to Buy, and interrupted purchase.
- Enable **App Store Server Notifications V2** in App Store Connect even with no server — you can point
  it at a free endpoint later; having the config in place early avoids a migration.

---

## 5. PAYWALL SPEC — GUIDELINE 3.1.2 CHECKLIST

Apple treats 3.1.2 as a catch-all for paywall design. In 2026 they began rejecting toggle-based
free-trial designs and any flow where price, term, or auto-renewal is unclear. **Every item below is
mandatory and must be visible without scrolling on an iPhone SE.**

### Must be on the paywall screen itself

- [ ] App/service name ("Amblyo Pro")
- [ ] Each plan's **exact price and exact duration** — "$5.99 per month", not "just $5.99"
- [ ] A **per-week equivalent** under every plan (mitigates the §2 anomaly)
- [ ] Explicit sentence: **"Subscriptions renew automatically until cancelled."**
- [ ] Explicit sentence: **"Cancel any time in your Apple Account settings, at least 24 hours before the period ends."**
- [ ] If a trial exists: **length, what happens at the end, and the price that will be charged**, in the same visual weight as the trial offer — never behind a toggle
- [ ] **"Restore Purchases"** button, always visible, never hidden in a menu
- [ ] **"Terms of Use (EULA)"** link → opens the in-app EULA screen
- [ ] **"Privacy Policy"** link → opens the in-app Privacy screen
- [ ] A visible, obvious **close/dismiss control** (an X of at least 44×44 pt, in the top-left, present
      from the first frame — no delayed appearance, no tiny grey X). Delayed or hidden dismiss controls
      are a documented rejection cause.
- [ ] No countdown timers, fake scarcity, or pre-checked upsells
- [ ] Yearly preselected; weekly never preselected

### Must also be true

- [ ] The same disclosure text appears in the **App Store description** (Apple requires the auto-renew
      terms in metadata as well as in-app)
- [ ] Functional **Terms of Use (EULA)** and **Privacy Policy** URLs in App Store Connect metadata —
      these must be real public web pages, separate from the in-app screens (`08` §5)
- [ ] The paywall renders correctly at AX5 Dynamic Type — the legal text must not be truncated
- [ ] Works in dark mode, iPad split view, and 320 pt width
- [ ] `SubscriptionStoreView` may be used, but a **custom paywall is recommended** here so you control
      the per-week equivalents and disclosure layout precisely

### Paywall layout (top → bottom)

```
[X]                                              Restore Purchases
              🧿  Amblyo Pro
        All 32 exercises · full progress history
              · on-device AI coach

   [ Yearly    $29.99/year    ≈$0.58/week   SAVE 81% ]  ← preselected
   [ Monthly    $9.99/month   ≈$2.31/week            ]
   [ Weekly     $2.99/week     $2.99/week            ]

   Start with 7 days free, then $29.99 per year.
   ↑ only shown when Yearly is selected, in body text
     size — never behind a toggle, never smaller than
     the price above it

           [   Try 7 Days Free   ]     ← label changes to
                                          "Subscribe" for
                                          weekly/monthly

   Subscriptions renew automatically until cancelled.
   Cancel any time in your Apple Account settings at least
   24 hours before the current period ends.

        Terms of Use (EULA)  ·  Privacy Policy
```

**Trial disclosure rules (2026 rejection hotspot).** Apple began rejecting toggle-based trial designs
in early 2026. Therefore: the trial length, the price charged after it, and the billing date must all
appear as **plain body text on the paywall itself**, at the same or larger size than the marketing
copy, visible without scrolling and without any interaction. No "Free Trial ⬤" switch. No trial
details revealed only after tapping. The CTA may say "Try 7 Days Free" only if "then $29.99 per year"
is adjacent and equally legible.

### Where the paywall appears

1. After the first free sample exercise in onboarding (dismissible)
2. On tapping a Pro exercise (dismissible)
3. Profile → Subscription (always reachable)

**Never** on cold launch. Never more than once per session. Never behind the parent gate in a way that
blocks a child from an already-purchased feature.

---

## 6. APP STORE CONNECT SETUP CHECKLIST

- [ ] Create subscription group `amblyo_pro`
- [ ] Create the three products with the IDs above; set group ranking yearly > monthly > weekly
- [ ] Localised display name and description for each product (shown in the Apple purchase sheet)
- [ ] A **review screenshot** for each product (App Review checks these; missing ones cause a
      "Metadata Rejected")
- [ ] Introductory offer: 7-day free trial, **yearly product only**
- [ ] **Apply to the App Store Small Business Program** (15% instead of 30% commission under $1M/yr) — Business → Small Business Program in App Store Connect. Not automatic.
- [ ] Set the **Subscription Terms** and confirm the auto-renew language in the app description
- [ ] Paid Applications agreement signed and banking/tax complete — **products stay in "Missing
      Metadata" and never load in a build until this is done.** This is the #1 "my products return
      an empty array" cause.
- [ ] Enable App Store Server Notifications V2
- [ ] Configure Family Sharing (**recommended on** — parents with two affected children)
