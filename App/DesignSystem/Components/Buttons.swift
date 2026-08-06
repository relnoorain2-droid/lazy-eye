//
//  Buttons.swift
//
//  docs/05-DESIGN-SYSTEM.md section 5.
//
//  Every button has a text label. Icon-only buttons are permitted in exactly two
//  places — the mute and fatigue controls in the session nav bar — and both carry
//  accessibility labels.
//

import SwiftUI

struct AmblyoButton: View {

    enum Style {
        case primary, secondary, tertiary, destructive
    }

    let title: String
    var systemImage: String?
    var style: Style = .primary
    var isLoading: Bool = false
    var fullWidth: Bool = true
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(TypeScale.body(rounded: theme.usesRoundedFont).weight(.semibold))
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: max(Layout.buttonHeight, theme.minTouchTarget))
            .padding(.horizontal, Spacing.lg)
            .foregroundStyle(foreground)
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    private var foreground: Color {
        switch style {
        case .primary: .white
        case .secondary: .brandPrimary
        case .tertiary: .textPrimary
        case .destructive: .white
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .primary: Color.brandPrimary
        case .secondary: Color.brandPrimary.opacity(0.12)
        case .tertiary: Color.clear
        case .destructive: Color.critical
        }
    }

    @ViewBuilder private var border: some View {
        if style == .tertiary {
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .strokeBorder(Color.separatorLine, lineWidth: 1)
        }
    }
}

/// Subtle press feedback. No bounce, no spring — this app is calm.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Buttons") {
    VStack(spacing: Spacing.md) {
        AmblyoButton(title: "Start today's session", systemImage: "play.fill") {}
        AmblyoButton(title: "Restore Purchases", style: .secondary) {}
        AmblyoButton(title: "Not now", style: .tertiary) {}
        AmblyoButton(title: "Delete all data", style: .destructive) {}
        AmblyoButton(title: "Loading", isLoading: true) {}
        AmblyoButton(title: "Disabled") {}.disabled(true)
    }
    .padding()
    .screenBackground()
}
