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
        await loadProducts()
        await refreshEntitlements()
    }

    deinit { updatesTask?.cancel() }

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
}
