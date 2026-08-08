//
//  CalibrationStepView.swift
//
//  The screen-size and viewing-distance calibration. This is the step that makes
//  every stimulus in the app a real angular size instead of a pixel count, and it
//  is the largest single quality gap between this app and the competition - the
//  reference app draws its targets in raw points, so the "same" exercise is four
//  times harder on a 13-inch iPad than on an iPhone SE.
//
//  THREE WAYS TO GET THE SCREEN SIZE, IN ORDER OF PREFERENCE
//
//  1. DEVICE LOOKUP - exact for every model in the table, zero user effort.
//     Fails on unreleased models, and is wrong under Display Zoom.
//
//  2. CARD CHECK - the user matches an ISO/IEC 7810 ID-1 card (every bank card,
//     driving licence and insurance card on Earth: 85.60 x 53.98 mm) against an
//     on-screen outline. Exact on any device, including one we have never heard
//     of, and it survives Display Zoom because it measures the actual points.
//     BUT IT DOES NOT FIT EVERYWHERE. A card's SHORT edge is 5.398 cm; an
//     iPhone SE display is 4.98 cm wide and 8.85 cm tall. At true size the card
//     will not fit in either orientation. So this option is offered only when
//     the geometry allows it, which the view checks rather than assumes.
//
//  3. DIAGONAL - the user states the screen diagonal in inches, which everyone
//     can find, and we combine it with the point resolution the OS reports.
//     Always available, always correct if the number is right.
//
//  docs/04-ARCHITECTURE.md section 4, docs/01-RESEARCH-BRIEF.md section 4.
//

import SwiftUI

@MainActor
struct CalibrationStepView: View {

    @Binding var draft: OnboardingDraft

    @State private var didInitialise = false
    @State private var showCardCheck = false
    @State private var showDiagonalEntry = false
    @State private var showDistanceHelp = false

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            screenSizeSection
            Divider().overlay(Color.separatorLine)
            viewingDistanceSection
            summary
        }
        .onAppear(perform: initialiseIfNeeded)
        .fullScreenCover(isPresented: $showCardCheck) {
            CardCheckView(pointsPerCM: $draft.screenPointsPerCM,
                          userVerified: $draft.screenSizeUserVerified)
        }
        .sheet(isPresented: $showDiagonalEntry) {
            DiagonalEntryView(pointsPerCM: $draft.screenPointsPerCM,
                              userVerified: $draft.screenSizeUserVerified)
        }
        .sheet(isPresented: $showDistanceHelp) { distanceHelpSheet }
    }

    // MARK: Screen size

    private var screenSizeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Your screen")
                .font(TypeScale.headline(rounded: theme.usesRoundedFont))

            Text("""
                 The app needs to know how big your screen physically is, so an \
                 exercise is the same difficulty here as on any other device.
                 """)
                .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)

            AmblyoCard(accent: draft.screenSizeUserVerified ? .success : nil) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(sourceLabel)
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                    Text(sizeDescription)
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            if ScreenGeometry.shouldPromptCardCheck && !draft.screenSizeUserVerified {
                // Honest about uncertainty rather than presenting a guess as fact.
                SafetyBanner(
                    level: .caution,
                    title: "We don't recognise this device",
                    message: "Please check the size yourself, or exercise sizes will be approximate."
                )
            }

            if cardCheckFits {
                AmblyoButton(title: "Check with a bank card",
                             systemImage: "creditcard",
                             style: .secondary) { showCardCheck = true }
            }

            AmblyoButton(title: cardCheckFits ? "Enter screen size instead" : "Enter your screen size",
                         systemImage: "ruler",
                         style: cardCheckFits ? .tertiary : .secondary) { showDiagonalEntry = true }
        }
    }

    /// True when a full-size card outline would actually fit on this display.
    /// Checked against the real point resolution, not guessed from the idiom -
    /// an iPad in Slide Over has an iPhone-sized window.
    private var cardCheckFits: Bool {
        let ppcm = draft.screenPointsPerCM > 0
            ? draft.screenPointsPerCM
            : ScreenGeometry.currentPointsPerCM()
        guard ppcm > 0 else { return false }

        let (long, short) = ScreenGeometry.pointResolution()
        return ScreenGeometry.cardCheckFits(longAxisPoints: long,
                                            shortAxisPoints: short,
                                            atPointsPerCM: ppcm)
    }

    private var sourceLabel: String {
        if draft.screenSizeUserVerified { return "Measured by you" }
        return ScreenGeometry.shouldPromptCardCheck ? "Estimated" : "Detected automatically"
    }

    private var sizeDescription: String {
        guard draft.screenPointsPerCM > 0 else { return "Not set yet." }
        let inches = ScreenGeometry.diagonalInches(forPointsPerCM: draft.screenPointsPerCM)
        return String(format: "About a %.1f-inch display (%.0f points per centimetre).",
                      inches, draft.screenPointsPerCM)
    }

    // MARK: Viewing distance

    private var viewingDistanceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("How far away do you sit?")
                    .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                Spacer()
                Button { showDistanceHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Why viewing distance matters")
                .tint(.brandPrimary)
            }

            Text("Roughly eyes-to-screen when you're comfortable. An approximate answer is fine.")
                .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(String(Int(draft.viewingDistanceCM.rounded())))
                    .font(TypeScale.metric(rounded: theme.usesRoundedFont))
                Text("cm")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
                Text("· about \(Int((draft.viewingDistanceCM / 2.54).rounded())) inches")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }

            Slider(value: $draft.viewingDistanceCM,
                   in: ScreenGeometry.plausibleViewingDistanceCM,
                   step: 1)
                .tint(.brandPrimary)
                .accessibilityLabel("Viewing distance")
                .accessibilityValue("\(Int(draft.viewingDistanceCM)) centimetres")
        }
    }

    private var distanceHelpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("""
                         The size of something on screen isn't what your eye \
                         responds to - the angle it covers in your vision is. A \
                         target twice as far away has to be twice as big to look \
                         the same.
                         """)
                    Text("""
                         Knowing your distance lets the app hold that angle steady, \
                         so an exercise is the same difficulty on a phone in your \
                         hand as on an iPad on a table.
                         """)
                    Text("""
                         If you switch between holding the device and propping it \
                         up, pick whichever you do more. You can change it any time \
                         in Settings.
                         """)
                        .foregroundStyle(Color.textSecondary)
                }
                .font(TypeScale.body(rounded: theme.usesRoundedFont))
                .padding()
                .readableContentWidth()
            }
            .screenBackground()
            .navigationTitle("Viewing distance")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Summary

    @ViewBuilder
    private var summary: some View {
        if draft.isCalibrationUsable {
            AmblyoCard(accent: .success) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                        .foregroundStyle(Color.success)
                    Text(finestDetailSentence)
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    /// Concrete proof the calibration did something, in the user's own terms,
    /// using the exact maths the exercise engine will use.
    private var finestDetailSentence: String {
        let probe = CalibrationProfile(screenPointsPerCM: draft.screenPointsPerCM,
                                       viewingDistanceCM: draft.viewingDistanceCM)
        let cpd = probe.maxRenderableCyclesPerDegree
        guard cpd > 0 else { return "" }
        return String(format: "At this distance your screen can show detail down to about %.0f cycles per degree.", cpd)
    }

    // MARK: Setup

    private func initialiseIfNeeded() {
        guard !didInitialise else { return }
        didInitialise = true

        draft.deviceIdentifier = ScreenGeometry.deviceIdentifier()

        if draft.viewingDistanceCM <= 0 {
            draft.viewingDistanceCM = ScreenGeometry.suggestedViewingDistanceCM()
        }
        if draft.screenPointsPerCM <= 0 {
            let detected = ScreenGeometry.currentPointsPerCM()
            draft.screenPointsPerCM = ScreenGeometry.isPlausible(detected) ? detected : 0
        }
    }
}

// MARK: - Card check
//
// Full-screen and edge to edge, because the outline needs every available point
// and because a card held against a screen with a navigation bar on it is being
// compared against the wrong rectangle.

@MainActor
struct CardCheckView: View {

    @Binding var pointsPerCM: Double
    @Binding var userVerified: Bool

    @State private var cardLongPoints: Double = 0
    @State private var didInitialise = false

    @Environment(\.dismiss) private var dismiss

    private static let aspect = ScreenGeometry.referenceCardHeightCM
        / ScreenGeometry.referenceCardWidthCM

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size
            // Lay the card along whichever axis is longer, so the same code works
            // on a phone in portrait and an iPad in landscape.
            let isVertical = available.height > available.width
            let range = sliderRange(in: available, vertical: isVertical)

            ZStack {
                Color.surfaceBase.ignoresSafeArea()

                VStack(spacing: Spacing.lg) {
                    Text("Hold a bank card flat against the screen and drag until the outline matches it exactly.")
                        .font(TypeScale.callout())
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)

                    Spacer(minLength: 0)

                    outline(vertical: isVertical)

                    Spacer(minLength: 0)

                    Slider(value: $cardLongPoints, in: range, step: 0.5) {
                        Text("Card size")
                    } minimumValueLabel: {
                        Image(systemName: "minus").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "plus").accessibilityHidden(true)
                    }
                    .tint(.brandPrimary)
                    .accessibilityLabel("Card size")
                    .accessibilityValue(String(format: "%.0f points per centimetre",
                                               ScreenGeometry.pointsPerCM(fromCardWidthInPoints: cardLongPoints)))

                    HStack(spacing: Spacing.md) {
                        AmblyoButton(title: "Cancel", style: .tertiary) { dismiss() }
                        AmblyoButton(title: "That's a match") { commit() }
                    }
                }
                .padding(Spacing.lg)
            }
            .onAppear { initialise(in: available, vertical: isVertical) }
        }
    }

    private func outline(vertical: Bool) -> some View {
        let long = cardLongPoints
        let short = cardLongPoints * Self.aspect
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.brandPrimary, lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.brandPrimary.opacity(0.08))
            )
            .frame(width: vertical ? short : long,
                   height: vertical ? long : short)
            // No animation: the outline must track the drag exactly, or the user
            // is matching their card against a value that has not arrived yet.
            .animation(nil, value: cardLongPoints)
            .accessibilityHidden(true)
    }

    private func sliderRange(in size: CGSize, vertical: Bool) -> ClosedRange<Double> {
        let longAxis = Double(vertical ? size.height : size.width)
        let shortAxis = Double(vertical ? size.width : size.height)

        let low = ScreenGeometry.plausiblePointsPerCM.lowerBound
            * ScreenGeometry.referenceCardWidthCM
        let byDensity = ScreenGeometry.plausiblePointsPerCM.upperBound
            * ScreenGeometry.referenceCardWidthCM
        // Never let the slider produce an outline larger than the space it is
        // drawn in: a clipped rectangle silently reads as "too small" and the
        // user drags it further wrong.
        let byLongAxis = longAxis - 24
        let byShortAxis = (shortAxis - 24) / Self.aspect

        let high = min(byDensity, byLongAxis, byShortAxis)
        return low...max(low + 1, high)
    }

    private func initialise(in size: CGSize, vertical: Bool) {
        guard !didInitialise else { return }
        didInitialise = true

        let seed = pointsPerCM > 0 ? pointsPerCM : ScreenGeometry.currentPointsPerCM()
        let range = sliderRange(in: size, vertical: vertical)
        let wanted = ScreenGeometry.cardLongEdgePoints(atPointsPerCM: seed)
        cardLongPoints = min(max(wanted, range.lowerBound), range.upperBound)
    }

    private func commit() {
        let measured = ScreenGeometry.pointsPerCM(fromCardWidthInPoints: cardLongPoints)
        if ScreenGeometry.isPlausible(measured) {
            pointsPerCM = measured
            userVerified = true
        }
        dismiss()
    }
}

// MARK: - Diagonal entry
//
// The universal fallback. Works on every device including the ones a card cannot
// fit on, and is exact when the stated number is right.

@MainActor
struct DiagonalEntryView: View {

    @Binding var pointsPerCM: Double
    @Binding var userVerified: Bool

    @State private var inches: Double = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("""
                     Enter the screen size from your device's specifications - the \
                     number in "6.1-inch display". It's on the box, in Settings, \
                     or on Apple's website.
                     """)
                    .font(TypeScale.callout())
                    .foregroundStyle(Color.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(String(format: "%.1f", inches))
                        .font(TypeScale.metric())
                    Text("inches")
                        .font(TypeScale.callout())
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)

                Slider(value: $inches,
                       in: ScreenGeometry.plausibleDiagonalInches,
                       step: 0.1)
                    .tint(.brandPrimary)
                    .accessibilityLabel("Screen diagonal")
                    .accessibilityValue(String(format: "%.1f inches", inches))

                if !isResultPlausible {
                    SafetyBanner(
                        level: .caution,
                        title: "That doesn't look right",
                        message: "That size doesn't match this device's resolution. Please check the number."
                    )
                }

                Spacer()

                AmblyoButton(title: "Save") { commit() }
                    .disabled(!isResultPlausible)
            }
            .padding()
            .readableContentWidth()
            .screenBackground()
            .navigationTitle("Screen size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: seed)
        }
        .presentationDetents([.large])
    }

    private var resultingPointsPerCM: Double {
        ScreenGeometry.pointsPerCM(fromDiagonalInches: inches)
    }

    private var isResultPlausible: Bool {
        ScreenGeometry.isPlausible(resultingPointsPerCM)
    }

    private func seed() {
        guard inches == 0 else { return }
        let source = pointsPerCM > 0 ? pointsPerCM : ScreenGeometry.currentPointsPerCM()
        let guess = ScreenGeometry.diagonalInches(forPointsPerCM: source)
        inches = ScreenGeometry.plausibleDiagonalInches.contains(guess) ? guess : 6.1
    }

    private func commit() {
        guard isResultPlausible else { return }
        pointsPerCM = resultingPointsPerCM
        userVerified = true
        dismiss()
    }
}
