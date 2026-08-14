//
//  PaywallAndGlassesTests.swift
//
//  StoreKit's `Product` cannot be constructed in a unit test — it only comes
//  from the App Store or a StoreKit configuration file — so the parts of the
//  paywall that CAN be tested without one are tested here, and the rest is
//  covered by the StoreKit-configuration UI test.
//
//  What is worth pinning without a Product:
//    · every paywall entry point produces a headline (an empty one is a blank
//      screen at the exact moment we ask for money)
//    · `Context` is Identifiable with stable ids, because `.sheet(item:)` uses
//      them and a colliding id shows the wrong sheet
//    · the purchase outcomes a caller must handle stay exhaustive
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Paywall")
struct PaywallTests {

    private static let contexts: [PaywallView.Context] = [
        .general, .exercise("Landolt Rings"), .profiles, .progress,
    ]

    @Test("every entry point has a headline")
    func everyContextHasAHeadline() {
        for context in Self.contexts {
            #expect(!context.headline.isEmpty,
                    "\(context) would render a blank paywall header")
        }
    }

    @Test("the exercise context names the exercise the user tapped")
    func exerciseContextNamesTheExercise() {
        let context = PaywallView.Context.exercise("Vernier Offset")
        #expect(context.headline.contains("Vernier Offset"),
                "answering \"why am I seeing this\" is the whole point of the context")
    }

    @Test("contexts have distinct ids")
    func contextIDsAreDistinct() {
        let ids = Self.contexts.map(\.id)
        #expect(Set(ids).count == ids.count,
                "sheet(item:) keys on id — a collision shows the wrong sheet")
    }

    @Test("the id is stable across equal values")
    func contextIDIsStable() {
        #expect(PaywallView.Context.exercise("A").id == PaywallView.Context.exercise("A").id)
        #expect(PaywallView.Context.exercise("A").id != PaywallView.Context.exercise("B").id)
    }

    @Test("no headline makes a claim about what the subscription will do for you")
    func headlinesMakeNoClaims() {
        for context in Self.contexts {
            let lowered = context.headline.lowercased()
            for phrase in ["improve", "cure", "fix", "restore", "better vision"] {
                #expect(!lowered.contains(phrase),
                        "\"\(phrase)\" in a paywall headline is a claim tied to payment")
            }
        }
    }

    @Test("a cancelled purchase is distinguishable from a failed one")
    func outcomesAreDistinct() {
        // The paywall must stay silent on cancellation and speak on failure.
        // Collapsing the two is how apps end up telling people off for changing
        // their mind.
        #expect(SubscriptionManager.PurchaseOutcome.cancelled
                != SubscriptionManager.PurchaseOutcome.failed("x"))
        #expect(SubscriptionManager.PurchaseOutcome.pending
                != SubscriptionManager.PurchaseOutcome.purchased)
        #expect(SubscriptionManager.PurchaseOutcome.failed("a")
                != SubscriptionManager.PurchaseOutcome.failed("b"))
    }

    @Test("entitlement states that grant access are exactly the ones intended")
    func entitlementGrantsAreCorrect() {
        #expect(EntitlementStatus.pro(expires: nil).isPro)
        #expect(EntitlementStatus.inGracePeriod(expires: nil).isPro,
                "a failed payment in its grace window keeps access — Apple's rules, and the decent thing")
        #expect(EntitlementStatus.inBillingRetry.isPro)
        #expect(!EntitlementStatus.free.isPro)
        #expect(!EntitlementStatus.unknown.isPro,
                "unknown must never grant access, or a launch before StoreKit answers unlocks the app")
    }

    @Test("the three product ids are distinct and correctly prefixed")
    func productIDsAreWellFormed() {
        #expect(Set(ProductID.all).count == 3)
        #expect(ProductID.all.allSatisfy { $0.hasPrefix("com.amblyo.app.pro.") })
        #expect(ProductID.all.first == ProductID.yearly,
                "display order puts the best value first; the button stays disabled until a deliberate choice, so this is not a preselected upsell")
    }
}

@Suite("Glasses self-check")
struct AnaglyphSelfCheckTests {

    @Test("an uncalibrated profile still gets a usable compositor")
    func worksWithoutCalibration() {
        // The person most likely to open the self-check has not calibrated yet,
        // so a nil calibration must not produce a blank or crashing screen.
        let compositor = AnaglyphCompositor()
        let pixel = compositor.composite(amblyopic: 1.0, fellow: 0.5)
        #expect(pixel.red >= 0 && pixel.red <= 1)
        #expect(pixel.green >= 0 && pixel.green <= 1)
        #expect(pixel.blue >= 0 && pixel.blue <= 1)
    }

    @Test("the two panels are visibly different to the two eyes")
    func panelsDifferPerEye() {
        let compositor = AnaglyphCompositor(amblyopicFilter: .cyan,
                                            fellowEyeContrast: 0.2)
        let amblyopicPanel = compositor.composite(amblyopic: 1.0, fellow: 0.5)
        let fellowPanel = compositor.composite(amblyopic: 0.5, fellow: 1.0)
        #expect(amblyopicPanel != fellowPanel,
                "if both panels composite identically the check cannot tell anyone anything")
    }

    @Test("a perfect pair of glasses reports near-zero bleed")
    func perfectGlassesReportCleanly() {
        let compositor = AnaglyphCompositor(redLeakIntoCyan: 0, cyanLeakIntoRed: 0)
        #expect(compositor.crossModulationIntoFellowEye() < 0.001,
                "the verdict card shows this as a percentage; a clean pair must read as clean")
    }

    @Test("leaky glasses report bleed the user can act on")
    func leakyGlassesReportHonestly() {
        let leaky = AnaglyphCompositor(redLeakIntoCyan: 0.3, cyanLeakIntoRed: 0.3)
        let clean = AnaglyphCompositor(redLeakIntoCyan: 0, cyanLeakIntoRed: 0)
        #expect(leaky.crossModulationIntoFellowEye()
                > clean.crossModulationIntoFellowEye(),
                "a number that doesn't move with the glasses is decoration")
    }

    @Test("shapes offered by the check are all distinct")
    func shapesAreDistinct() {
        // Naming a shape is a stronger check than "can you see something", which
        // only works if the shapes cannot be confused with each other.
        let shapes = AnaglyphSelfCheckView.shapes
        let names = AnaglyphSelfCheckView.shapeNames
        #expect(Set(shapes).count == shapes.count, "a repeated symbol makes the check unfalsifiable")
        #expect(Set(names).count == names.count)
        #expect(shapes.count == names.count,
                "the accessibility label indexes into names with the shape's index")
        #expect(shapes.count >= 2, "the two panels draw two different shapes")
    }
}
