//
//  LearnView.swift
//
//  The honest-explanation tab.
//
//  WHY A HEALTH-ADJACENT APP NEEDS THIS
//  Everything here exists because the alternative is worse. An app that trains
//  vision and explains nothing invites the user to fill the gap themselves, and
//  what they fill it with is usually a promise the app never made. Guideline
//  1.4.1 cares about that, but so should we: someone who understands that
//  perceptual learning is task-specific and slow will keep going for the twelve
//  weeks it might take, and will also go to an optometrist when they should.
//
//  THE ARTICLES ARE IN CODE, NOT FETCHED.
//  No network, no CMS, nothing to go stale behind an app update. It also means
//  the claims linter reads every word of this content on every commit, which is
//  the only reliable way to keep an app like this from slowly acquiring medical
//  claims one well-meaning edit at a time.
//
//  docs/08-COMPLIANCE-LEGAL.md sections 2 and 6, docs/09-CONTENT-COPY.md.
//

import SwiftUI

@MainActor
struct LearnView: View {

    @Environment(\.theme) private var theme
    @State private var openArticle: LearnArticle?
    @State private var openDocument: LegalDocument?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {

                Text("What this app does, and what it can't")
                    .font(TypeScale.displayLarge(rounded: theme.usesRoundedFont))

                // The disclaimer sits at the TOP of the learning tab rather than
                // buried at the bottom, because the person most likely to read
                // this tab is the person forming expectations right now.
                AmblyoCard(accent: Color.caution) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        // claims-lint:disable-next-line
                        Text("This is training, not medical care")
                            .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                        Text("Amblyo is an exercise app. It doesn't replace an eye examination, glasses, patching, or anything else an optometrist or ophthalmologist recommends.")
                            .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.textSecondary)
                        Button("Read the full note") { openDocument = .medicalDisclaimer }
                            .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                            .tint(.brandPrimary)
                    }
                }

                ForEach(LearnArticle.all) { article in
                    Button { openArticle = article } label: { row(article) }
                        .buttonStyle(PressableButtonStyle())
                }

                Text("Reference")
                    .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                    .padding(.top, Spacing.md)

                ForEach([LegalDocument.evidenceAndMethods, .medicalDisclaimer,
                         .privacyPolicy, .subscriptionTerms], id: \.self) { document in
                    Button { openDocument = document } label: { documentRow(document) }
                        .buttonStyle(PressableButtonStyle())
                }
            }
            .padding()
            .readableContentWidth()
        }
        .screenBackground()
        .navigationTitle("Learn")
        .sheet(item: $openArticle) { article in
            NavigationStack { LearnArticleView(article: article) }
        }
        .sheet(item: $openDocument) { document in
            NavigationStack { LegalDocumentView(document: document) }
        }
    }

    private func row(_ article: LearnArticle) -> some View {
        AmblyoCard(accent: article.tint) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: article.systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(article.tint)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(article.title)
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(article.blurb)
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func documentRow(_ document: LegalDocument) -> some View {
        AmblyoCard {
            HStack(spacing: Spacing.md) {
                Image(systemName: document.systemImage)
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                Text(document.linkTitle)
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Article model

/// An article is a title and an ordered list of blocks. Structured rather than
/// one long string so the renderer can style headings and bullets without a
/// Markdown parse at read time, and so a test can walk every paragraph.
struct LearnArticle: Identifiable, Sendable, Equatable {

    enum Block: Sendable, Equatable {
        case heading(String)
        case paragraph(String)
        case bullet(String)
        /// A statement about evidence strength, rendered with its tier badge so
        /// the strength is visible rather than asserted in prose.
        case evidence(EvidenceTier, String)
    }

    let id: String
    let title: String
    let blurb: String
    let systemImage: String
    let blocks: [Block]

    var tint: Color {
        switch id {
        case "safety": .caution
        case "evidence": .brandSecondary
        default: .brandPrimary
        }
    }

    /// Every sentence the app says about how vision training works, in one place
    /// the claims linter can read.
    static let all: [LearnArticle] = [
        howItWorks, whyItsSlow, evidence, whoItHelps, safety, glasses, faq,
    ]

    static let howItWorks = LearnArticle(
        id: "how-it-works",
        title: "How the exercises work",
        blurb: "Why tapping at faint shapes is the point",
        systemImage: "eye",
        blocks: [
            .paragraph("Amblyopia isn't usually a problem with the eye itself. The eye works; the brain has learned to lean on the other one. That's why glasses alone often don't finish the job — and why the exercises here are about giving the weaker eye difficult, interesting work rather than just looking through it."),
            .heading("Difficulty that follows you"),
            .paragraph("Every exercise runs a staircase. Answer correctly three times and it gets harder; get one wrong and it steps back. Within a couple of minutes it settles at the level where you're right about four times in five."),
            .paragraph("That's deliberate. Work that's too easy trains nothing, and work that's too hard is just guessing. The point where you're getting roughly one in five wrong is uncomfortable, and it's the level where the visual system actually adapts."),
            .heading("Why it looks so plain"),
            .paragraph("The stripes, gaps and offsets aren't placeholder art. They're the stimuli the underlying research used, and they're plain because a busy picture gives your brain other things to look at. The measurement only means something if the shape is the only thing on screen."),
            .heading("Why we measure your screen"),
            .paragraph("A gap that's 1 mm wide on a phone held 30 cm away isn't the same task as 1 mm on an iPad at 60 cm. The calibration step converts everything into angular size, so the difficulty you reach on one device means the same thing on another."),
        ])

    static let whyItsSlow = LearnArticle(
        id: "why-slow",
        title: "Why progress is slow",
        blurb: "Weeks, not days — and what that looks like",
        systemImage: "hourglass",
        blocks: [
            .paragraph("Perceptual learning is slow and stubbornly specific. Improvement on one task often transfers only partly to another, and it accumulates over weeks of short sessions rather than hours of long ones."),
            .heading("What the Progress tab will and won't tell you"),
            .paragraph("It won't draw a line until there's enough data to support one. Eight practice days for an exercise is the minimum before a direction is claimed, and even then the app says \"no clear change yet\" when the numbers don't separate from noise."),
            .paragraph("That's less encouraging than a rising graph. It's also the only version of the graph worth having: a line fitted to four noisy points will point wherever the last point happened to fall."),
            .heading("Short and often beats long and occasional"),
            .paragraph("Ten to twenty minutes most days is the pattern the research uses. The app caps session length for that reason, and the cap is lower for children."),
            .heading("If nothing changes"),
            .paragraph("After two blocks of four weeks with no movement, the app will say so and suggest seeing an eye care professional. It won't quietly keep going and hope."),
        ])

    static let evidence = LearnArticle(
        id: "evidence",
        title: "What the evidence actually says",
        blurb: "Which exercises are well supported, and which aren't",
        systemImage: "text.book.closed",
        blocks: [
            .paragraph("Not every exercise here rests on the same amount of research, so each one carries a badge saying which. Tapping the badge anywhere in the app explains what that tier means."),
            .evidence(.a, "Top tier: repeatedly tested in controlled studies with amblyopic participants, with measured improvements in the trained task."),
            .evidence(.b, "Middle tier: supported by smaller studies, or by studies in people without amblyopia, and plausible from what's known about the visual system."),
            .evidence(.c, "Third tier: built on the same principles but not directly tested. Included because it targets something the well-supported exercises don't, and labelled honestly."),
            .heading("What none of them claim"),
            .paragraph("No exercise in this app has been shown to restore normal vision, and no app can promise that. Getting better at a trained task is a real result, and it is not the same as no longer having amblyopia."),
            .heading("Where the studies are"),
            .paragraph("The Evidence and Methods document lists the sources behind each tier, along with the specific limitation that keeps some of them out of the top tier."),
        ])

    static let whoItHelps = LearnArticle(
        id: "who",
        title: "Who this can help",
        blurb: "Adults, children, and when to see someone",
        systemImage: "person.2",
        blocks: [
            .heading("Adults"),
            .paragraph("The old rule that nothing can change after childhood has softened considerably. Adults do improve on trained visual tasks. It tends to be slower, and it doesn't undo the underlying wiring."),
            .heading("Children"),
            .paragraph("Children generally respond faster, and they're also the group most likely to be under active care. Anything an optometrist has prescribed — glasses, patching, drops — comes first; this app fits around it, not instead of it."),
            .heading("Before you start"),
            .bullet("Have an eye examination first, especially if you've never been assessed."),
            .bullet("Wear your usual glasses or contact lenses for every session."),
            .bullet("If a doctor has given you a patching or drops schedule, keep to it."),
            .heading("See a professional if"),
            .bullet("Vision changes suddenly, or you see flashes, floaters or a shadow."),
            .bullet("You get double vision that wasn't there before."),
            .bullet("There's eye pain, redness, or a headache that doesn't settle."),
            .bullet("Two months of consistent practice show no change at all."),
        ])

    static let safety = LearnArticle(
        id: "safety",
        title: "Comfort and safety",
        blurb: "Breaks, eye strain, and the limits built in",
        systemImage: "hand.raised",
        blocks: [
            .paragraph("Close visual work is tiring, and tired eyes make worse measurements as well as being unpleasant. The app has several limits it won't let you past."),
            .bullet("Sessions are capped, and shorter for younger age groups."),
            .bullet("Breaks are offered part-way through, and \"my eyes feel tired\" ends a session immediately without losing your progress."),
            .bullet("Nothing flickers faster than 3 Hz, and no exercise inverts the whole screen's brightness. That's for anyone photosensitive."),
            .heading("The 20-20-20 habit"),
            .paragraph("Between sessions, looking at something around 20 feet away for 20 seconds every 20 minutes of close work is a reasonable habit. It won't change your amblyopia; it does help with strain."),
            .heading("Stop if"),
            .paragraph("You get a headache, your eyes ache, or things start looking doubled. Come back another day — nothing is lost by stopping, and pushing on makes the next measurement less useful anyway."),
        ])

    static let glasses = LearnArticle(
        id: "glasses",
        title: "About the red-cyan glasses",
        blurb: "What the two-eye exercises need, and why",
        systemImage: "eyeglasses",
        blocks: [
            .paragraph("Most of the app needs nothing but your screen. A separate group of exercises — the two-eye ones — needs a cheap pair of red-cyan anaglyph glasses, the kind sold for 3D comics."),
            .heading("Why they're needed"),
            .paragraph("A red filter over one eye and a cyan filter over the other lets the screen send a different image to each eye. That's what makes it possible to give the weaker eye a clear image and the stronger eye a faint one, so both are used at once instead of one being ignored."),
            .heading("What to buy"),
            .bullet("Plain red-cyan paper or plastic anaglyph glasses. A few pounds or dollars a pair."),
            .bullet("Red on one side, cyan (blue-green) on the other. Not red-green, and not polarised or shuttered 3D cinema glasses — those won't work."),
            .bullet("Either way round is fine; the setup step asks which eye has which colour."),
            .heading("Checking they work"),
            .paragraph("After setup there's a ten-second check: two squares, each showing a shape only one eye should see. If you can name both shapes with the same eye, the separation isn't working and the two-eye exercises won't measure anything useful."),
            .heading("If you don't have a pair"),
            .paragraph("Everything else works without them. The two-eye exercises stay hidden until setup is done rather than sitting there greyed out."),
        ])

    static let faq = LearnArticle(
        id: "faq",
        title: "Common questions",
        blurb: "Devices, glasses, children, subscriptions",
        systemImage: "questionmark.circle",
        blocks: [
            .heading("Can I use this instead of patching?"),
            .paragraph("No. If patching has been prescribed, keep to it. Ask your optometrist how, or whether, to fit this alongside."),
            .heading("Which device is best?"),
            .paragraph("A larger screen is better, so an iPad if you have one. Everything works on a phone; a few exercises simply can't present their hardest levels on a small screen, and the app quietly limits those rather than pretending."),
            .heading("Do I need to wear my glasses?"),
            .paragraph("Yes — your usual correction, every session. Training an uncorrected blur measures the blur, not the amblyopia."),
            .heading("Why does it ask me to hold the phone at a set distance?"),
            .paragraph("Because difficulty is an angle, not a number of pixels. Holding it closer makes everything easier and the numbers stop comparing to yesterday's."),
            .heading("My child gets bored."),
            .paragraph("Short is fine. Five useful minutes beats a fought-over twenty, and the daily cap for children is deliberately low."),
            .heading("What happens if I cancel?"),
            .paragraph("Your history stays on the device and the free exercises keep working. Nothing is deleted, and nothing is uploaded — there's no account and no server."),
        ])
}

// MARK: - Article renderer

@MainActor
struct LearnArticleView: View {
    let article: LearnArticle

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .padding()
            .readableContentWidth()
        }
        .screenBackground()
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func view(for block: LearnArticle.Block) -> some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                .padding(.top, Spacing.sm)
        case .paragraph(let text):
            Text(text)
                .font(TypeScale.body(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textPrimary)
        case .bullet(let text):
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text("•").accessibilityHidden(true)
                Text(text).font(TypeScale.body(rounded: theme.usesRoundedFont))
            }
        case .evidence(let tier, let text):
            AmblyoCard(accent: tier.tint) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    EvidenceBadge(tier: tier)
                    Text(text)
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}
