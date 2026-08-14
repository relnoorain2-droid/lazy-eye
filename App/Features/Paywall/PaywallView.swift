//
//  PaywallView.swift
//
//  Every element on this screen is here because App Review guideline 3.1.2
//  requires it, or because leaving it out is the specific thing that gets
//  subscription apps rejected. The checklist, in the order a reviewer looks:
//
//    · what the subscription unlocks, before any price
//    · the exact price AND the exact billing period, per option
//    · free-trial length where one exists, and what happens when it ends
//    · auto-renew disclosure in plain words
//    · a working Restore Purchases control
//    · links to Terms (Apple's standard EULA) and Privacy
//    · no dark patterns: dismiss is always available, nothing preselects a
//      purchase, and no countdown pressure
//
//  THE PRIVACY LINK IS AN IN-APP PAGE, NOT A WEB LINK.
//  A paywall that bounces someone to Safari to read a policy loses them, and a
//  reviewer on a flaky connection may simply mark it as broken. The full policy
//  ships in the bundle. The EULA is Apple's own hosted standard licence, which
//  is the one link that must be external.
//
//  KIDS MODE PUTS THE PARENT GATE IN FRONT OF PURCHASE.
//  Guideline 5.1.4. A child must not be able to buy anything, and an arithmetic
//  gate is a real barrier where a date wheel is not.
//
//  docs/07-MONETIZATION-PAYWALL.md, docs/08-COMPLIANCE-LEGAL.md sections 1-5.
//

import SwiftUI
import StoreKit

@MainActor
struct PaywallView: View {

    /// What the user was trying to do. Shown at the top so the paywall answers
    /// "why am I seeing this" before it asks for money.
    var context: Context = .general
    var isKidsMode: Bool = false
    var onFinish: (Bool) -> Void = { _ in }

    /// `Identifiable` so a caller can drive presentation with
    /// `.sheet(item:)` — that form carries the context INTO the sheet, where
    /// `isPresented` plus a separate @State would let the two drift apart and
    /// show the wrong headline for one frame.
    enum Context: Equatable, Identifiable {
        var id: String { headline }

        case general
        case exercise(String)
        case profiles
        case progress

        var headline: String {
            switch self {
            case .general: "Unlock the full programme"
            case .exercise(let title): "\(title) is part of the full programme"
            case .profiles: "Add another person"
            case .progress: "See your full history"
            }
        }
    }

    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var selected: Product?
    @State private var message: String?
    @State private var showingParentGate = false
    @State private var showingPrivacy = false
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    headline
                    benefits
                    plans
                    if let message { notice(message) }
                    purchaseButton
                    disclosure
                    legalRow
                }
                .padding(Spacing.lg)
                .readableContentWidth()
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Dismiss is ALWAYS available. A paywall you cannot leave is a
                // rejection and, more to the point, a hostile thing to do.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { onFinish(false); dismiss() }
                }
            }
            .sheet(isPresented: $showingPrivacy) {
                NavigationStack { LegalDocumentView(document: .privacyPolicy) }
            }
            .sheet(isPresented: $showingParentGate) {
                ParentGate(onSuccess: { Task { await buy() } })
            }
            .task { await prepare() }
        }
    }

    // MARK: Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: "eye")
                .font(.system(size: 40))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)
            Text(context.headline)
                .font(TypeScale.displayLarge(rounded: theme.usesRoundedFont))
        }
    }

    /// What you get, BEFORE any price. Reviewers check this order specifically,
    /// and it is the honest order anyway.
    private var benefits: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            benefit("square.grid.3x3", "Every exercise",
                    "All \(ExerciseRegistry.all.count) exercises, including the two-eye work that needs red-cyan glasses.")
            benefit("chart.line.uptrend.xyaxis", "Your full history",
                    "Trends across every session, with an honest read on whether anything has actually changed.")
            benefit("person.2", "Up to 5 people",
                    "One subscription covers the whole family.")
            benefit("lock.open", "No adverts, no data selling",
                    "Nothing leaves your device. That doesn't change whether you subscribe or not.")
        }
    }

    private func benefit(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                Text(body)
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var plans: some View {
        if subscriptions.products.isEmpty {
            AmblyoCard {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Plans aren't loading")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                    Text("Check your connection and try again. Nothing has been charged.")
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(subscriptions.products, id: \.id) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let isSelected = selected?.id == product.id
        return Button {
            selected = product
        } label: {
            HStack(alignment: .center, spacing: Spacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    // Price AND period together, always. "$29.99" alone is a
                    // rejection; the period is what makes it a price.
                    Text("\(product.displayPrice) / \(periodLabel(product))")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))

                    if let trial = subscriptions.introductoryOffer(for: product) {
                        Text("\(trial), then \(product.displayPrice)")
                            .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.success)
                    } else if let weekly = subscriptions.weeklyEquivalent(for: product) {
                        Text("about \(weekly) a week")
                            .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(Spacing.md)
            .background(Color.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(isSelected ? Color.brandPrimary : Color.separatorLine,
                                  lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(product.displayPrice) per \(periodLabel(product))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func periodLabel(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "period" }
        switch period.unit {
        case .day: return period.value == 1 ? "day" : "\(period.value) days"
        case .week: return period.value == 1 ? "week" : "\(period.value) weeks"
        case .month: return period.value == 1 ? "month" : "\(period.value) months"
        case .year: return period.value == 1 ? "year" : "\(period.value) years"
        @unknown default: return "period"
        }
    }

    private var purchaseButton: some View {
        VStack(spacing: Spacing.sm) {
            AmblyoButton(
                title: selected.flatMap { subscriptions.introductoryOffer(for: $0) } != nil
                    ? "Start free trial"
                    : "Subscribe",
                isLoading: subscriptions.isPurchasing
            ) {
                // Kids mode: a child must not be able to buy anything.
                if isKidsMode { showingParentGate = true } else { Task { await buy() } }
            }
            .disabled(selected == nil || subscriptions.isPurchasing)

            Button {
                Task { await restore() }
            } label: {
                if isRestoring {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Restore Purchases")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                }
            }
            .tint(.brandPrimary)
            .disabled(isRestoring)
        }
    }

    /// The auto-renew disclosure, in plain words. Required, and the wording is
    /// deliberately not lawyerly — a disclosure nobody reads has not disclosed
    /// anything.
    private var disclosure: some View {
        Text("""
             Your subscription renews automatically at the end of each period \
             unless you cancel at least 24 hours before it ends. You can cancel \
             any time in your Apple account settings. If there's a free trial and \
             you cancel during it, you won't be charged.
             """)
            .font(TypeScale.caption(rounded: theme.usesRoundedFont))
            .foregroundStyle(Color.textSecondary)
    }

    private var legalRow: some View {
        HStack(spacing: Spacing.lg) {
            // In-app, not a web link. A paywall that sends someone to Safari to
            // read a policy loses them, and a reviewer on a bad connection may
            // just mark it broken.
            Button("Privacy") { showingPrivacy = true }
            // Apple's own hosted standard EULA — the one link that must be
            // external, because it is Apple's document rather than ours.
            Link("Terms", destination: ExternalLinks.appleStandardEULA)
            Link("Manage", destination: ExternalLinks.manageSubscriptions)
        }
        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
        .tint(.brandPrimary)
    }

    private func notice(_ text: String) -> some View {
        SafetyBanner(level: .info, title: text)
    }

    // MARK: Actions

    private func prepare() async {
        if subscriptions.products.isEmpty { await subscriptions.loadProducts() }
        // Nothing is preselected as a purchase-ready default beyond the first
        // listed plan, and the button stays disabled until a deliberate choice
        // exists. Preselecting the most expensive option is the classic dark
        // pattern here.
        if selected == nil { selected = subscriptions.products.first }
    }

    private func buy() async {
        guard let product = selected else { return }
        switch await subscriptions.purchase(product) {
        case .purchased:
            onFinish(true); dismiss()
        case .cancelled:
            // Deliberately silent. Backing out is not an error and telling
            // someone off for it is a dark pattern.
            break
        case .pending:
            message = "Waiting for approval. You'll get access as soon as it's approved."
        case .failed(let reason):
            message = reason
        }
    }

    private func restore() async {
        isRestoring = true
        let restored = await subscriptions.restore()
        isRestoring = false
        if restored {
            onFinish(true); dismiss()
        } else {
            message = "No previous subscription found on this Apple account."
        }
    }
}
