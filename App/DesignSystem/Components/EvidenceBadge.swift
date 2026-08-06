//
//  EvidenceBadge.swift
//
//  The tier badge on every exercise, and the sheet behind it.
//
//  This is a compliance component as much as a design one. Guideline 1.4.1
//  requires disclosed methodology; this is where we disclose it. And every
//  Tier A/B sheet must end with the boundary sentence — "those studies tested
//  other products, not this app" — which is what keeps a citation from becoming
//  a borrowed efficacy claim.
//
//  docs/08-COMPLIANCE-LEGAL.md section 3A, docs/01-RESEARCH-BRIEF.md section 2.
//

import SwiftUI

struct EvidenceBadge: View {
    let tier: EvidenceTier
    var compact: Bool = false

    @State private var showingSheet = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(tier.rawValue)
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont).weight(.bold))
                if !compact {
                    Text(tier.headline)
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                }
                Image(systemName: "info.circle")
                    .font(.caption2)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .foregroundStyle(tier.tint)
            .background(tier.tint.opacity(0.12))
            .clipShape(Capsule())
            .minimumTouchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Evidence level \(tier.rawValue): \(tier.headline)")
        .accessibilityHint("Shows what research supports this type of exercise")
        .sheet(isPresented: $showingSheet) {
            EvidenceSheet(tier: tier)
        }
    }
}

// MARK: - Sheet

struct EvidenceSheet: View {
    let tier: EvidenceTier
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {

                    HStack(spacing: Spacing.sm) {
                        Text(tier.rawValue)
                            .font(TypeScale.displayLarge())
                            .foregroundStyle(tier.tint)
                        VStack(alignment: .leading) {
                            Text(tier.headline).font(TypeScale.headline())
                            Text("Evidence level").font(TypeScale.caption())
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    Text(tier.explanation)
                        .font(TypeScale.body())
                        .foregroundStyle(Color.textPrimary)

                    Divider()

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("What this means")
                            .font(TypeScale.headline())
                        ForEach(EvidenceTier.allCases, id: \.self) { level in
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Text(level.rawValue)
                                    .font(TypeScale.body().weight(.bold))
                                    .foregroundStyle(level.tint)
                                    .frame(width: 20, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(level.headline)
                                        .font(TypeScale.body().weight(.medium))
                                    Text(level.shortDescription)
                                        .font(TypeScale.callout())
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                            .opacity(level == tier ? 1 : 0.6)
                        }
                    }

                    Divider()

                    // The boundary. Never remove this.
                    Text(Self.boundaryNote)
                        .font(TypeScale.callout())
                        .foregroundStyle(Color.textSecondary)

                    NavigationLink {
                        LegalDocumentView(document: .evidenceAndMethods)
                    } label: {
                        Label("Full references and methods", systemImage: "text.book.closed")
                    }
                }
                .padding()
                .readableContentWidth()
            }
            .screenBackground()
            .navigationTitle("Why this exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // claims-lint:disable-next-line
    static let boundaryNote = """
        Amblyo is a training app. It is not a medical device and it is not a \
        substitute for care from a qualified eye care professional. Research \
        described here studied other products and other methods — Amblyo itself \
        was not studied.
        """
}

extension EvidenceTier {
    var shortDescription: String {
        switch self {
        case .a: "Randomised controlled trials in people with amblyopia."
        case .b: "Perceptual learning studies, mostly in adults."
        case .c: "Used in optometric practice; limited published evidence in amblyopia."
        }
    }
}

// MARK: - Preview

#Preview("Evidence badges") {
    VStack(alignment: .leading, spacing: Spacing.md) {
        ForEach(EvidenceTier.allCases, id: \.self) { EvidenceBadge(tier: $0) }
        Divider()
        ForEach(EvidenceTier.allCases, id: \.self) { EvidenceBadge(tier: $0, compact: true) }
    }
    .padding()
    .screenBackground()
}
