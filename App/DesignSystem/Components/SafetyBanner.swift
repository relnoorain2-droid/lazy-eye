//
//  SafetyBanner.swift
//
//  Caution and critical messages: fatigue, breaks, daily caps, contraindications,
//  and the professional-referral escalation.
//
//  `.critical` banners are NOT dismissible. That is the point of them — the
//  8-week no-improvement referral card must not be swipe-away-able.
//
//  docs/04-ARCHITECTURE.md section 6, docs/05-DESIGN-SYSTEM.md section 5.
//

import SwiftUI

struct SafetyBanner: View {

    enum Level {
        case info, caution, critical

        var tint: Color {
            switch self {
            case .info: .brandPrimary
            case .caution: .caution
            case .critical: .critical
            }
        }

        var icon: String {
            switch self {
            case .info: "info.circle.fill"
            case .caution: "exclamationmark.triangle.fill"
            case .critical: "exclamationmark.octagon.fill"
            }
        }

        /// Critical messages can never be dismissed.
        var isDismissible: Bool { self != .critical }
    }

    let level: Level
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: level.icon)
                    .foregroundStyle(level.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(TypeScale.body(rounded: theme.usesRoundedFont).weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    if let message {
                        Text(message)
                            .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                if level.isDismissible, let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .minimumTouchTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }

            if let actionTitle, let action {
                AmblyoButton(title: actionTitle,
                             style: level == .critical ? .primary : .secondary,
                             fullWidth: false,
                             action: action)
            }
        }
        .padding(Spacing.md)
        .background(level.tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                .strokeBorder(level.tint.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Prebuilt safety messages
//
// Centralised so the wording is reviewed once and cannot drift. Every string
// here is checked against docs/08-COMPLIANCE-LEGAL.md section 3.

extension SafetyBanner {

    /// Shown after the user taps "My eyes feel tired".
    /// docs/14-REVIEW-COMPLAINTS-MATRIX.md R4 — the reference app told users that
    /// fatigue meant it was working. It does not, and we say the opposite.
    static func fatigue(onRest: @escaping () -> Void) -> SafetyBanner {
        SafetyBanner(
            level: .caution,
            title: "Let's stop there",
            message: "Tired eyes are a signal to rest, not a sign of progress. "
                   + "Look at something far away for a minute or two. "
                   + "You can come back later today or tomorrow.",
            actionTitle: "OK",
            action: onRest
        )
    }

    /// The 20-20-20 break.
    static func breakTime(onContinue: @escaping () -> Void) -> SafetyBanner {
        SafetyBanner(
            level: .info,
            title: "Time for a 20-second break",
            message: "Look at something about 6 metres away for 20 seconds. "
                   + "This is the 20-20-20 rule and it helps with eye strain.",
            actionTitle: "Done",
            action: onContinue
        )
    }

    /// Daily cap reached.
    static func dailyCap(minutes: Int) -> SafetyBanner {
        SafetyBanner(
            level: .caution,
            title: "That's today's practice done",
            message: "You've reached \(minutes) minutes for today. More isn't better — "
                   + "regular short sessions work better than long ones."
        )
    }

    /// The escalation rule: two 4-week blocks with no measurable change.
    /// Deliberately not dismissible.
    static func noImprovement(onLearnMore: @escaping () -> Void) -> SafetyBanner {
        SafetyBanner(
            level: .critical,
            title: "Time to check in with an eye care professional",
            // claims-lint:disable-next-line
            message: "Your training scores haven't changed much over the last eight weeks. "
                   + "That's worth discussing with an optometrist or ophthalmologist. "
                   + "They can check whether anything needs to change.",
            actionTitle: "What should I ask?",
            action: onLearnMore
        )
    }
}

// MARK: - Preview

#Preview("Safety banners") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            SafetyBanner.breakTime {}
            SafetyBanner.fatigue {}
            SafetyBanner.dailyCap(minutes: 20)
            SafetyBanner.noImprovement {}
            SafetyBanner(level: .caution, title: "Dismissible", message: "Has an x.", onDismiss: {})
        }
        .padding()
    }
    .screenBackground()
}
