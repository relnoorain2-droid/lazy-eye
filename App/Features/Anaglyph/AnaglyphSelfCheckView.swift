//
//  AnaglyphSelfCheckView.swift
//
//  A ten-second "is this actually working?" screen.
//
//  WHY THIS EXISTS
//  The compositor's maths is verified; whether real red-cyan glasses on a real
//  panel separate cleanly is a physical fact, and nobody on this project has
//  looked through a pair. Rather than ship that uncertainty silently, the app
//  hands the check to whoever DOES have glasses and makes the answer
//  unambiguous in seconds.
//
//  It serves three audiences at once:
//    1. A user whose exercises look wrong — one screen tells them whether their
//       glasses are the problem.
//    2. App Review, who must be able to evaluate a dichoptic app without owning
//       red-cyan glasses. That is what the no-glasses preview is for, and
//       docs/08-COMPLIANCE-LEGAL.md section 8 requires it.
//    3. Us — if separation is broken, the first report will say exactly which
//       half failed rather than "the exercise feels odd".
//
//  THE TEST ITSELF
//  Two panels. The left carries a shape only the amblyopic eye should see; the
//  right, one only the fellow eye should see. Close one eye, then the other. If
//  each panel shows a shape through one lens and nothing through the other,
//  separation works. Naming the shape is a stronger check than "can you see
//  something" — a faint ghost is visible, but not identifiable.
//

import SwiftUI

@MainActor
struct AnaglyphSelfCheckView: View {

    /// Optional on purpose. Someone who has not calibrated yet is exactly the
    /// person most likely to open this screen, and constructing a throwaway
    /// `@Model` just to satisfy a non-optional would insert an empty row into
    /// the store.
    let calibration: CalibrationProfile?
    var onDone: () -> Void = {}

    @State private var previewWithoutGlasses = false
    @State private var amblyopicShape = 0
    @State private var fellowShape = 1
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    /// Four shapes, chosen to be unmistakable from each other even at low
    /// contrast — a ghost is visible, but only a real image is nameable.
    /// Internal rather than private so the tests read the real list. A shape set
    /// with a duplicate in it would quietly make the check unfalsifiable.
    static let shapes = ["triangle.fill", "square.fill",
                         "circle.fill", "star.fill"]
    static let shapeNames = ["Triangle", "Square", "Circle", "Star"]

    private var compositor: AnaglyphCompositor {
        if let calibration { AnaglyphCompositor(calibration: calibration) }
        else { AnaglyphCompositor() }
    }

    private var isCalibrated: Bool { calibration?.isAnaglyphCalibrated == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    instructions
                    panels
                    controls
                    verdict
                }
                .padding(Spacing.lg)
                .readableContentWidth()
            }
            .screenBackground()
            .navigationTitle("Check your glasses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(); dismiss() }
                }
            }
            .onAppear(perform: randomise)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("With your glasses on, cover one eye at a time and look at both squares.")
                .font(TypeScale.body(rounded: theme.usesRoundedFont))
            Text("""
                 Each square should show a clear shape through ONE eye and almost \
                 nothing through the other. If you can name both shapes with the \
                 same eye, the separation is not working.
                 """)
                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var panels: some View {
        HStack(spacing: Spacing.md) {
            panel(shapeIndex: amblyopicShape, forAmblyopicEye: true, label: "Left square")
            panel(shapeIndex: fellowShape, forAmblyopicEye: false, label: "Right square")
        }
    }

    private func panel(shapeIndex: Int, forAmblyopicEye: Bool,
                       label: String) -> some View {
        // In preview mode both layers are drawn to all channels, so the shapes
        // are plainly visible without glasses. That is the App Review path, and
        // it is labelled so nobody mistakes it for the real stimulus.
        let background = previewWithoutGlasses
            ? Color(white: AnaglyphCompositor.layerMidpoint)
            : colour(amblyopic: 0.5, fellow: 0.5)

        let foreground = previewWithoutGlasses
            ? Color.textPrimary
            : (forAmblyopicEye
               ? colour(amblyopic: 1.0, fellow: 0.5)
               : colour(amblyopic: 0.5, fellow: 1.0))

        return ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(background)
            Image(systemName: Self.shapes[shapeIndex])
                .font(.system(size: 56))
                .foregroundStyle(foreground)
        }
        .frame(height: 150)
        .accessibilityLabel("\(label): \(Self.shapeNames[shapeIndex])")
    }

    private func colour(amblyopic: Double, fellow: Double) -> Color {
        let pixel = compositor.composite(amblyopic: amblyopic, fellow: fellow)
        return Color(red: pixel.red, green: pixel.green, blue: pixel.blue)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: $previewWithoutGlasses) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show without glasses")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    Text("For anyone reviewing the app who doesn't have a pair. This is not how the exercise really looks.")
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .tint(.brandPrimary)

            AmblyoButton(title: "Show different shapes", systemImage: "shuffle",
                         style: .tertiary) { randomise() }
        }
    }

    @ViewBuilder
    private var verdict: some View {
        let cross = compositor.crossModulationIntoFellowEye()

        AmblyoCard(accent: isCalibrated ? Color.success : Color.caution) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(isCalibrated
                     ? "Your glasses are set up"
                     : "Glasses not set up yet")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))

                // The honest number, in the user's terms rather than ours.
                Text(String(format: "Predicted bleed between eyes: about %.1f%%. Under 2%% is good.",
                            cross * 100))
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)

                Text("""
                     If the shapes don't separate for you, the two-eye exercises \
                     won't measure anything useful — run the glasses setup again, \
                     or try a different pair.
                     """)
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func randomise() {
        var indices = Array(Self.shapes.indices).shuffled()
        amblyopicShape = indices.removeFirst()
        fellowShape = indices.removeFirst()
    }
}
