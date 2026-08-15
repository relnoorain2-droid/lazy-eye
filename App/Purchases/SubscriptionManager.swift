//
//  SubscriptionManager.swift
//
//  PHASE 1 SCAFFOLD. The transaction listener and entitlement refresh are real
//  and wired at launch — that ordering matters and is easy to get wrong later
//  (docs/07-MONETIZATION-PAYWALL.md section 4). Purchase flow, grace period,
//  billing retry, Ask-to-Buy and the paywall land in Phase 10.
//

import Foundation
import Observation
import StoreKit
import os

enum ProductID {
    // Team ID QAT93YWVSF. See docs/DECISIONS.md section 2.
    static let weekly  = "com.amblyo.app.pro.weekly"
    static let monthly = "com.amblyo.app.pro.monthly"
    static let yearly  = "com.amblyo.app.pro.yearly"

    static let all: [String] = [yearly, monthly, weekly]   // display order
}

enum EntitlementStatus: Equatable, Sendable {
    case unknown
    case free
    case pro(expires: Date?)
    case inGracePeriod(expires: Date?)
    case inBillingRetry

    var isPro: Bool {
        switch self {
        case .pro, .inGracePeriod, .inBillingRetry: true
        case .free, .unknown: false
        }
    }
}

@Observable
@MainActor
final class SubscriptionManager {

    private static let log = Logger(subsystem: "com.amblyo.app", category: "storekit")

    private(set) var products: [Product] = []
    private(set) var status: EntitlementStatus = .unknown

    private var updatesTask: Task<Void, Never>?

    /// MUST be called before the first UI frame. A purchase completed on another
    /// device, or an Ask-to-Buy approval from a parent, arrives through
    /// `Transaction.updates` — if nothing is listening it is missed.
    func start() async {
        updatesTask = listenForTransactions()
        // ENTITLEMENTS FIRST, PRODUCTS SECOND.
        //
        // These were the other way round, and `loadProducts` is a network call
        // that can take many seconds — or, on a cold TestFlight install behind a
        // sandbox sign-in prompt, effectively forever. Until it returned,
        // `status` stayed `.unknown` and Profile showed "Checking…" with no way
        // out. Whether the user is entitled is answered from the LOCAL receipt
        // and needs no network at all, so it has no business queueing behind a
        // product lookup.
        await refreshEntitlements()
        await loadProducts()
    }

    // NO deinit HERE, deliberately.
    //
    // `deinit` is nonisolated in Swift 6, so it cannot touch `updatesTask`,
    // which is @MainActor-isolated. The compiler is right to reject it.
    //
    // Cancelling is also unnecessary: this object is owned by the App struct
    // and lives exactly as long as the process. If it is ever deinitialised,
    // the app is terminating and the task dies with it. If a future refactor
    // gives this a shorter lifetime, call `stop()` explicitly.
    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = ProductID.all.compactMap { id in loaded.first { $0.id == id } }
            if products.isEmpty {
                // Almost always the Paid Applications agreement, not the code.
                // docs/12-CICD-NO-MAC.md section 6.
                Self.log.warning("No products returned. Check the Paid Applications agreement in App Store Connect.")
            }
        } catch {
            Self.log.error("Product load failed: \(error.localizedDescription)")
        }
    }

    func refreshEntitlements() async {
        if LaunchArguments.shouldUnlockPro {
            status = .pro(expires: nil)
            return
        }

        // `.unknown` is a STARTING state, never a resting one. If the loop below
        // throws, hangs or is cancelled, the status must still land somewhere
        // the UI can describe. Defaulting to `.free` is the safe direction: it
        // shows the paywall rather than granting access we could not verify.
        defer { if status == .unknown { status = .free } }

        var newStatus: EntitlementStatus = .free
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProductID.all.contains(transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            newStatus = .pro(expires: transaction.expirationDate)
        }
        status = newStatus
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()          // never skip this
                await self?.refreshEntitlements()
            }
        }
    }

    // MARK: - Purchasing

    enum PurchaseOutcome: Equatable, Sendable {
        case purchased
        /// The user backed out. NOT an error, and must never show one.
        case cancelled
        /// Ask to Buy: a parent has to approve. The purchase may complete
        /// minutes or days later, which is exactly why `Transaction.updates` is
        /// listened to from launch rather than only while the paywall is open.
        case pending
        case failed(String)
    }

    private(set) var isPurchasing = false

    func purchase(_ product: Product) async -> PurchaseOutcome {
        guard !isPurchasing else { return .cancelled }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    // A failed signature check means the receipt is not
                    // trustworthy. Granting access anyway is how apps get
                    // trivially pirated, so this is a refusal, not a warning.
                    Self.log.error("Unverified transaction for \(product.id, privacy: .public)")
                    return .failed("That purchase couldn't be verified.")
                }
                await transaction.finish()
                await refreshEntitlements()
                return .purchased

            case .userCancelled:
                return .cancelled

            case .pending:
                return .pending

            @unknown default:
                return .failed("Something unexpected happened.")
            }
        } catch {
            Self.log.error("Purchase failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Restore. Apple requires a visible restore control on any paywall, and a
    /// user who reinstalls must get their subscription back without paying
    /// twice — a 3.1.1 rejection otherwise.
    func restore() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            // A sync failure is often just a cancelled sign-in sheet, so it is
            // logged rather than surfaced. Entitlements are refreshed regardless
            // because the local receipt may already be sufficient.
            Self.log.info("AppStore.sync: \(error.localizedDescription)")
        }
        await refreshEntitlements()
        return status.isPro
    }

    // MARK: - Display helpers

    /// Price per week, for honest comparison across terms. Apple requires the
    /// price and period to be clear; showing "$29.99" next to "$2.99" without
    /// this makes the yearly plan look worse than it is.
    func weeklyEquivalent(for product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        let weeks: Decimal
        switch period.unit {
        case .day: weeks = Decimal(period.value) / 7
        case .week: weeks = Decimal(period.value)
        case .month: weeks = Decimal(period.value) * 52 / 12
        case .year: weeks = Decimal(period.value) * 52
        @unknown default: return nil
        }
        guard weeks > 0 else { return nil }
        let perWeek = product.price / weeks
        return product.priceFormatStyle.format(perWeek)
    }

    /// Free-trial length, if this product offers one.
    func introductoryOffer(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let unit: String
        switch offer.period.unit {
        case .day: unit = offer.period.value == 1 ? "day" : "days"
        case .week: unit = offer.period.value == 1 ? "week" : "weeks"
        case .month: unit = offer.period.value == 1 ? "month" : "months"
        case .year: unit = offer.period.value == 1 ? "year" : "years"
        @unknown default: return nil
        }
        return "\(offer.period.value) \(unit) free"
    }
}
