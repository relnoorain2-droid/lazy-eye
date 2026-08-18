//
//  HowToSheet.swift
//
//  "How do I do this one?" — reachable from inside every exercise.
//
//  WHY IT IS BUILT FROM THE DESCRIPTOR RATHER THAN WRITTEN 32 TIMES.
//  Every exercise already declares, in one place, what the user does
//  (`summary`), what it trains (`targets`), whether it needs glasses
//  (`requiresAnaglyph`), what the staircase moves along, and how well supported
//  it is. Thirty-two hand-written help pages would say the same things in
//  slightly different words, drift from the exercises they describe, and give
//  the next person 32 files to update when the difficulty rule changes. Reading
//  the descriptor means the help cannot disagree with the exercise.
//
//  WHAT IS *NOT* AUTOMATIC, AND MATTERS MOST.
//  The paragraph explaining that getting things wrong is expected. New users
//  read a rising difficulty as failure and stop — the staircase is DESIGNED to
//  settle where they are right about four times in five, so about one answer in
//  five is meant to be wrong. Nobody infers that from a screen full of stripes,
//  and it is the single most useful sentence the app can say.
//

import SwiftUI

@MainActor
struct HowToSheet: View {

    let descriptor: ExerciseDescriptor

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    step(number: 1,
                         icon: "hand.tap",
                         title: "What to do",
                         body: descriptor.summary)

                    if descriptor.requiresAnaglyph {
                        step(number: 2,
                             icon: "eyeglasses",
                             title: "Put your red-cyan glasses on",
                             body: "This one shows each eye something different. Without the glasses it looks faint or doubled — that is correct, not a fault.")
                    }

                    step(number: descriptor.requiresAnaglyph ? 3 : 2,
                         icon: "arrow.up.arrow.down",
                         title: "It gets harder, on purpose",
                         body: "Three right answers make it harder, one wrong answer steps back. Within a couple of minutes it settles where you get about four out of five right — so roughly one answer in five is MEANT to be wrong. That is the exercise working, not you failing.")

                    step(number: descriptor.requiresAnaglyph ? 4 : 3,
                         icon: "questionmark.circle",
                         title: "Guessing is fine",
                         body: "Near your limit you will not be sure. Guess anyway — a guess still tells the app something, and refusing to answer tells it nothing.")

                    step(number: descriptor.requiresAnaglyph ? 5 : 4,
                         icon: "eye.trianglebadge.exclamationmark",
                         title: "Stop whenever you want",
                         body: "The eye button ends the session straight away and keeps everything you have done. Tired eyes measure badly, so stopping early is the right call, not a wasted session.")

                    Divider().overlay(Color.separatorLine)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("What this trains")
                            .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                        Text(descriptor.targets)
                            .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.textSecondary)
                        EvidenceBadge(tier: descriptor.evidenceTier)
                    }

                    Text(AssessmentTest.scoreQualifier)
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding()
                .readableContentWidth()
            }
            .screenBackground()
            .navigationTitle(descriptor.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func step(number: Int, icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                Text(body)
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
