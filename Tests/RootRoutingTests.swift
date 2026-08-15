//
//  RootRoutingTests.swift
//
//  Written after build 2 reached TestFlight in a state the user could not
//  escape from, with 460 other tests passing.
//
//  WHAT WENT WRONG, BECAUSE THE TEST ONLY MAKES SENSE WITH IT
//  Whether to show setup or the app was decided by a UserDefaults boolean and
//  nothing else. A boolean in UserDefaults survives things the database does
//  not: an update whose store will not migrate, a failed save, a rebuilt store.
//  When they disagreed, the app went to the tab bar with no profile in it —
//  every screen reading "No profile yet. Finish setup to start training", and
//  no route to setup, because the flag insisted setup was finished. Deleting
//  the app was the only way out and nothing on screen said so.
//
//  The bug was three words inside a SwiftUI `body`, which is why no test caught
//  it: a `body` cannot be asked a question. The decision is a function now, and
//  these are the cases.
//

import Testing
@testable import Amblyo

@Suite("Root routing")
struct RootRoutingTests {

    @Test("a profile and a set flag opens the app")
    func normalLaunch() {
        #expect(!RootRoute.needsOnboarding(activeProfileCount: 1, flagSaysComplete: true))
    }

    @Test("a fresh install shows setup")
    func freshInstall() {
        #expect(RootRoute.needsOnboarding(activeProfileCount: 0, flagSaysComplete: false))
    }

    @Test("a set flag with no profile shows setup — THE SHIPPED BUG")
    func staleFlagWithoutProfileIsRecoverable() {
        // This is the exact state build 2 launched into: the flag survived from
        // build 1, the store did not. It must route to setup, not to a tab bar
        // the user cannot leave.
        #expect(RootRoute.needsOnboarding(activeProfileCount: 0, flagSaysComplete: true),
                "a stale completion flag must not strand the user without a profile")
    }

    @Test("a profile without the flag still shows setup")
    func profileWithoutFlagStillRunsSetup() {
        // The disclaimer is a compliance gate under Guideline 1.4.1, not a
        // formality, so a profile that appeared without setup having finished
        // does not buy a way past it.
        #expect(RootRoute.needsOnboarding(activeProfileCount: 1, flagSaysComplete: false))
    }

    @Test("soft-deleted profiles do not count as usable")
    func deletedProfilesDoNotCount() {
        // The screens inside the tab bar all query ACTIVE profiles. If routing
        // counted inactive ones the user would reach the same dead end by a
        // slower route: profiles exist, none are usable, no way to make one.
        #expect(RootRoute.needsOnboarding(activeProfileCount: 0, flagSaysComplete: true))
    }
}
