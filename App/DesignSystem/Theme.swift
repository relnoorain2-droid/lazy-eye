//
//  Theme.swift
//
//  Carries "are we in kids mode?" and "has the user reduced motion?" down the
//  view tree, so components can adapt without every call site passing flags.
//
//  docs/05-DESIGN-SYSTEM.md section 9.
//

import SwiftUI

// MARK: - Theme

struct Theme: Equatable, Sendable {
    var isKidsMode: Bool = false
    var isUnderFive: Bool = false

    /// SF Rounded in kids mode.
    var usesRoundedFont: Bool { isKidsMode }

    var cardRadius: CGFloat { isKidsMode ? Radius.cardKids : Radius.card }

    var minTouchTarget: CGFloat {
        isUnderFive ? Layout.minTouchTargetKids : Layout.minTouchTarget
    }

    static let adult = Theme()
    static let kids = Theme(isKidsMode: true)

    init(isKidsMode: Bool = false, isUnderFive: Bool = false) {
        self.isKidsMode = isKidsMode
        self.isUnderFive = isUnderFive
    }

    init(profile: Profile) {
        self.isKidsMode = profile.isKidsMode
        self.isUnderFive = profile.ageGroup == .underFive
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.adult
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    func theme(_ theme: Theme) -> some View {
        environment(\.theme, theme)
    }

    func theme(for profile: Profile) -> some View {
        environment(\.theme, Theme(profile: profile))
    }
}

// MARK: - Colour-scheme preference

extension SettingsStore.ThemePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: "Match device"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

// MARK: - Shared view modifiers

extension View {

    /// Standard screen background.
    func screenBackground() -> some View {
        background(Color.surfaceBase.ignoresSafeArea())
    }

    /// Constrains content width on iPad and centres it. Long measure is hard to
    /// read; a full-width 13" iPad line is about 140 characters.
    func readableContentWidth() -> some View {
        frame(maxWidth: Layout.maxContentWidth)
            .frame(maxWidth: .infinity)
    }

    /// Guarantees the minimum touch target without changing visual size.
    func minimumTouchTarget(_ size: CGFloat = Layout.minTouchTarget) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }

    /// Applies an animation only when Reduce Motion is off.
    func respectfulAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(RespectfulAnimation(animation: animation, value: value))
    }
}

private struct RespectfulAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Score qualifier
//
// Guideline 1.4.1: every surface showing a measured value must state that it is
// not a clinical measurement. Making it a modifier means it cannot be forgotten
// on a screen — and the compliance checklist can grep for it.
// docs/08-COMPLIANCE-LEGAL.md section 2.

extension View {
    /// Appends the mandatory "training score, not a clinical measurement" note.
    func scoreQualifier(alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: Spacing.xs) {
            self
            Text(AssessmentTest.scoreQualifier)
                .font(TypeScale.caption())
                .foregroundStyle(Color.textSecondary)
                .accessibilityLabel(AssessmentTest.scoreQualifier)
        }
    }
}
