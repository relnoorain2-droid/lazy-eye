//
//  ParentGate.swift
//
//  Guards purchases, settings, cap overrides and profile deletion when a kids
//  profile is active.
//
//  It is an arithmetic challenge, not a birthday picker. A five-year-old can
//  tap through a date wheel; a five-year-old cannot multiply. Apple's own
//  guidance for kids-adjacent apps expects a genuine barrier, and this is the
//  standard pattern.
//
//  docs/05-DESIGN-SYSTEM.md section 5, docs/08-COMPLIANCE-LEGAL.md section 1 (5.1.4).
//

import SwiftUI

struct ParentGate: View {
    let onSuccess: () -> Void
    var onCancel: (() -> Void)?

    @State private var question = Question.random()
    @State private var entry = ""
    @State private var attempts = 0
    @State private var showError = false
    @FocusState private var focused: Bool

    @Environment(\.dismiss) private var dismiss

    private static let maxAttempts = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Spacer(minLength: 0)

                Image(systemName: "person.badge.shield.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.brandPrimary)
                    .accessibilityHidden(true)

                VStack(spacing: Spacing.sm) {
                    Text("Ask a grown-up")
                        .font(TypeScale.title())
                    Text("To continue, solve this.")
                        .font(TypeScale.callout())
                        .foregroundStyle(Color.textSecondary)
                }

                Text(question.prompt)
                    .font(TypeScale.metric())
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityLabel(question.accessibilityPrompt)

                TextField("Answer", text: $entry)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(TypeScale.title().monospacedDigit())
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .focused($focused)
                    .onSubmit(check)

                if showError {
                    Text(attemptsRemaining > 0
                         ? "Not quite. \(attemptsRemaining) \(attemptsRemaining == 1 ? "try" : "tries") left."
                         : "Let's try a different question.")
                        .font(TypeScale.callout())
                        .foregroundStyle(Color.critical)
                        .accessibilityAddTraits(.isStaticText)
                }

                AmblyoButton(title: "Continue", action: check)
                    .disabled(entry.isEmpty)

                Spacer(minLength: 0)
            }
            .padding()
            .readableContentWidth()
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel?()
                        dismiss()
                    }
                }
            }
            .onAppear { focused = true }
        }
        .interactiveDismissDisabled(false)
    }

    private var attemptsRemaining: Int { max(0, Self.maxAttempts - attempts) }

    private func check() {
        guard let value = Int(entry.trimmingCharacters(in: .whitespaces)) else {
            showError = true
            return
        }
        if value == question.answer {
            onSuccess()
            dismiss()
            return
        }
        attempts += 1
        showError = true
        entry = ""
        if attempts >= Self.maxAttempts {
            // New question rather than a lockout — a locked-out parent is a
            // support email, and the gate is a speed bump, not security.
            question = .random()
            attempts = 0
        }
    }
}

// MARK: - Question

extension ParentGate {
    struct Question: Equatable {
        let left: Int
        let right: Int

        var answer: Int { left * right }
        var prompt: String { "\(left) × \(right)" }
        var accessibilityPrompt: String { "What is \(left) times \(right)?" }

        /// Two-digit multiplication: trivial for an adult, out of reach for the
        /// under-12s this gate exists for.
        static func random() -> Question {
            Question(left: Int.random(in: 6...12), right: Int.random(in: 6...12))
        }
    }
}

// MARK: - Presentation helper

extension View {
    /// Presents a parent gate, running `action` only if it is passed.
    func parentGate(isPresented: Binding<Bool>, action: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            ParentGate(onSuccess: action)
        }
    }
}

// MARK: - Preview

#Preview("Parent gate") {
    ParentGate(onSuccess: {})
}
