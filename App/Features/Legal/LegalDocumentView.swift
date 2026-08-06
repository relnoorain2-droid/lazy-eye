//
//  LegalDocumentView.swift
//
//  Renders the bundled legal and evidence Markdown.
//
//  In-app screens, NOT web views. Two reasons: your requirement that the paywall
//  link to internal pages, and Guideline 5.1.4 — external links in a
//  kids-adjacent app are a liability. The public copies at the support site are
//  separate and exist only for App Store Connect metadata.
//
//  docs/08-COMPLIANCE-LEGAL.md sections 4 and 5.
//

import SwiftUI

// MARK: - Document catalogue

enum LegalDocument: String, CaseIterable, Identifiable {
    case medicalDisclaimer = "medical-disclaimer"
    case privacyPolicy = "privacy-policy"
    case subscriptionTerms = "subscription-terms"
    case evidenceAndMethods = "evidence-and-methods"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .medicalDisclaimer: "Important — please read"
        case .privacyPolicy: "Privacy Policy"
        case .subscriptionTerms: "Subscription Terms"
        case .evidenceAndMethods: "Evidence and Methods"
        }
    }

    /// Short label for links and buttons.
    var linkTitle: String {
        switch self {
        case .medicalDisclaimer: "Medical disclaimer"
        case .privacyPolicy: "Privacy Policy"
        case .subscriptionTerms: "Subscription Terms"
        case .evidenceAndMethods: "Evidence and methods"
        }
    }

    var systemImage: String {
        switch self {
        case .medicalDisclaimer: "cross.case"
        case .privacyPolicy: "hand.raised"
        case .subscriptionTerms: "creditcard"
        case .evidenceAndMethods: "text.book.closed"
        }
    }

    var fileName: String { rawValue }

    /// Subdirectory in the bundle. Kept in sync with App/Resources/Legal.
    static let bundleSubdirectory = "Legal"
}

// MARK: - Loader

enum LegalDocumentLoader {

    /// Loads the Markdown, or a clear fallback if the resource is missing.
    /// A legal screen must never render blank — a reviewer tapping "Privacy
    /// Policy" and getting an empty page is a guaranteed rejection.
    static func markdown(for document: LegalDocument) -> String {
        if let url = Bundle.main.url(forResource: document.fileName,
                                     withExtension: "md",
                                     subdirectory: LegalDocument.bundleSubdirectory),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        if let url = Bundle.main.url(forResource: document.fileName, withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        assertionFailure("Missing bundled document: \(document.fileName).md")
        return fallback(for: document)
    }

    private static func fallback(for document: LegalDocument) -> String {
        """
        # \(document.title)

        This document could not be loaded. Please contact support and we will
        send it to you directly.
        """
    }
}

// MARK: - View

struct LegalDocumentView: View {
    let document: LegalDocument
    /// When set, shows an acknowledgement button instead of plain reading.
    var onAcknowledge: (() -> Void)?

    @State private var blocks: [MarkdownBlock] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(blocks) { block in
                    block.view
                }

                if let onAcknowledge {
                    AmblyoButton(title: "I understand") {
                        onAcknowledge()
                        dismiss()
                    }
                    .padding(.top, Spacing.lg)
                }
            }
            .padding()
            .readableContentWidth()
        }
        .screenBackground()
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            blocks = MarkdownBlock.parse(LegalDocumentLoader.markdown(for: document))
        }
    }
}

// MARK: - Minimal Markdown renderer
//
// SwiftUI's AttributedString(markdown:) handles inline styling but ignores
// headings and lists, which is most of the structure in these documents. This
// is a deliberately small block parser: headings, bullets, paragraphs, rules.
// No third-party dependency for four document types.

struct MarkdownBlock: Identifiable {
    enum Kind {
        case h1(String), h2(String), h3(String)
        case paragraph(AttributedString)
        case bullet(AttributedString)
        case rule
    }

    let id = UUID()
    let kind: Kind

    @ViewBuilder var view: some View {
        switch kind {
        case .h1(let text):
            Text(text)
                .font(TypeScale.title())
                .foregroundStyle(Color.textPrimary)
                .padding(.top, Spacing.sm)
                .accessibilityAddTraits(.isHeader)
        case .h2(let text):
            Text(text)
                .font(TypeScale.headline())
                .foregroundStyle(Color.textPrimary)
                .padding(.top, Spacing.sm)
                .accessibilityAddTraits(.isHeader)
        case .h3(let text):
            Text(text)
                .font(TypeScale.body().weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(text)
                .font(TypeScale.body())
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("•").foregroundStyle(Color.brandPrimary)
                Text(text)
                    .font(TypeScale.body())
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .rule:
            Divider()
        }
    }

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.joined(separator: " ")
            blocks.append(MarkdownBlock(kind: .paragraph(styled(joined))))
            paragraph.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Skip HTML comments, including the claims-lint markers.
            if line.hasPrefix("<!--") { continue }

            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("### ") {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .h3(String(line.dropFirst(4)))))
            } else if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .h2(String(line.dropFirst(3)))))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .h1(String(line.dropFirst(2)))))
            } else if line == "---" || line == "***" {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .rule))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .bullet(styled(String(line.dropFirst(2))))))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }

    /// Inline bold/italic via AttributedString, falling back to plain text.
    private static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

// MARK: - Reusable legal links row
//
// Used on the paywall and in Settings. Guideline 3.1.2 requires both of these
// to be reachable from the paywall, so they travel together.

struct LegalLinksRow: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            // Terms of Use = Apple's Standard EULA. We do not write our own.
            // See ExternalLinks.appleStandardEULA for why.
            Link(destination: ExternalLinks.appleStandardEULA) {
                Text("Terms of Use (EULA)")
            }

            Text("·").foregroundStyle(Color.textSecondary)

            // Privacy Policy stays an in-app screen, per the product decision.
            NavigationLink {
                LegalDocumentView(document: .privacyPolicy)
            } label: {
                Text(LegalDocument.privacyPolicy.linkTitle)
            }
        }
        .font(TypeScale.caption())
        .foregroundStyle(Color.textSecondary)
        .minimumTouchTarget()
    }
}

// MARK: - External links
//
// The only outbound URLs in the app. Everything else is a bundled screen.

enum ExternalLinks {

    /// Apple's Standard End User Licence Agreement.
    ///
    /// WHY WE USE APPLE'S RATHER THAN OUR OWN:
    /// Apple publishes a standard EULA that applies by default to every app
    /// unless the developer supplies a custom one. A custom EULA must be at
    /// least as protective of the user as Apple's, and if it is not, App Review
    /// rejects it — so writing one buys nothing and adds risk.
    ///
    /// Note what the Standard EULA does NOT cover: auto-renewal terms. Apple
    /// requires those separately, in the app description AND on the paywall.
    /// That is what `LegalDocument.subscriptionTerms` is for — it is a
    /// disclosure screen, not a licence agreement.
    static let appleStandardEULA = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!

    static let privacyPolicy = URL(
        string: "https://sites.google.com/view/amblyolazyeyetraining/privacy-policy"
    )!

    static let evidenceAndMethods = URL(
        string: "https://sites.google.com/view/amblyolazyeyetraining/evidence-and-methods"
    )!

    static let support = URL(
        string: "https://sites.google.com/view/amblyolazyeyetraining/support"
    )!

    static let supportEmail = "ksbpstech@gmail.com"

    /// Opens the system subscription management screen. Required by 3.1.2 so
    /// the user always has an obvious cancellation path.
    static let manageSubscriptions = URL(
        string: "https://apps.apple.com/account/subscriptions"
    )!
}

// MARK: - Preview

#Preview("Medical disclaimer") {
    NavigationStack {
        LegalDocumentView(document: .medicalDisclaimer, onAcknowledge: {})
    }
}
