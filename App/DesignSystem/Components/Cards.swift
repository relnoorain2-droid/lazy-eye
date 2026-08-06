//
//  Cards.swift
//
//  AmblyoCard, MetricTile, StreakRing.
//  docs/05-DESIGN-SYSTEM.md section 5.
//

import SwiftUI

// MARK: - Card

struct AmblyoCard<Content: View>: View {
    var accent: Color?
    @ViewBuilder var content: () -> Content

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            if let accent {
                Rectangle()
                    .fill(accent)
                    .frame(width: 4)
                    .accessibilityHidden(true)
            }
            content()
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                .strokeBorder(Color.separatorLine, lineWidth: 1)
        )
    }
}

// MARK: - Metric tile

struct MetricTile: View {

    enum Direction { case better, worse, unchanged, unknown }

    let title: String
    let value: String
    var unit: String?
    var delta: String?
    var direction: Direction = .unknown
    /// Set false for tiles that don't show a measured score (streaks, minutes).
    var needsScoreQualifier: Bool = true

    @Environment(\.theme) private var theme

    var body: some View {
        AmblyoCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(value)
                        .font(TypeScale.metric(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textPrimary)
                    if let unit {
                        Text(unit)
                            .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if let delta {
                    Label(delta, systemImage: directionIcon)
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(directionColor)
                        .labelStyle(.titleAndIcon)
                }

                // Guideline 1.4.1 — every measured value carries this.
                if needsScoreQualifier {
                    Text(AssessmentTest.scoreQualifier)
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, Spacing.xs)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var directionIcon: String {
        switch direction {
        case .better: "arrow.up.right"
        case .worse: "arrow.down.right"
        case .unchanged: "equal"
        case .unknown: "questionmark"
        }
    }

    private var directionColor: Color {
        switch direction {
        case .better: .success
        case .worse: .caution
        case .unchanged, .unknown: .textSecondary
        }
    }

    private var accessibilityDescription: String {
        var parts = [title, value]
        if let unit { parts.append(unit) }
        if let delta { parts.append(delta) }
        if needsScoreQualifier { parts.append(AssessmentTest.scoreQualifier) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Streak ring

struct StreakRing: View {
    let days: Int
    var goal: Int = 7

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(days) / Double(goal))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.separatorLine, lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.brandSecondary,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(days)")
                    .font(TypeScale.title(rounded: theme.usesRoundedFont).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                Text(days == 1 ? "day" : "days")
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(width: 96, height: 96)
        .animation(reduceMotion ? nil : Motion.gentle, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current streak")
        .accessibilityValue("\(days) \(days == 1 ? "day" : "days")")
    }
}

// MARK: - Previews

#Preview("Cards") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            MetricTile(title: "Balance", value: "0.46", delta: "+0.04 this month", direction: .better)
            MetricTile(title: "Detail", value: "0.40", unit: "logMAR", delta: "No clear change yet", direction: .unchanged)
            MetricTile(title: "Practice", value: "18", unit: "min today", needsScoreQualifier: false)
            AmblyoCard(accent: Track.dichoptic.tint) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Stack Drop").font(TypeScale.headline())
                    Text("Binocular · 5 min").font(TypeScale.callout()).foregroundStyle(Color.textSecondary)
                }
            }
            StreakRing(days: 5)
        }
        .padding()
    }
    .screenBackground()
}
