//
//  BalanceField.swift
//
//  The animated two-eye dot field, extracted so D5 and the Check-in show the
//  same stimulus rather than two that resemble each other.
//
//  WHY THIS ONE OWNS ITS OWN STATE AND THE STEREOGRAM FIELD DOES NOT.
//  A stereogram is a still image: hand it a pair and it draws. This is a
//  kinematogram — the dots MOVE, and the measurement is about coherent motion,
//  so the view has to hold the dots, the two generators and the frame clock
//  across redraws. Putting that state in the caller would mean every caller
//  reimplementing the animation loop, which is precisely the duplication this
//  extraction exists to prevent.
//
//  TWO GENERATORS, NOT ONE, AND THAT IS LOAD-BEARING.
//  Sharing a generator between the signal and noise fields would correlate them,
//  and correlated noise is not noise — the task would measure something other
//  than motion coherence while looking exactly the same on screen.
//
//  docs/03-EXERCISE-CATALOG.md D5, docs/16-EXERCISE-STAGE-SPEC.md.
//

import SwiftUI

@MainActor
struct BalanceField: View {

    let signal: KinematogramParameters
    let noise: KinematogramParameters
    let calibration: CalibrationProfile
    /// Seeds come from the trial, so the same trial always produces the same
    /// field — a session can be replayed exactly when someone reports a bad one.
    let signalSeed: UInt64
    let noiseSeed: UInt64

    @State private var signalDots: [KinematogramDot] = []
    @State private var noiseDots: [KinematogramDot] = []
    @State private var signalGenerator = SeededGenerator(seed: 1)
    @State private var noiseGenerator = SeededGenerator(seed: 2)
    @State private var lastFrame: Date = .distantPast

    private var compositor: AnaglyphCompositor {
        AnaglyphCompositor(calibration: calibration)
    }

    /// The compositor's midpoint, not black or grey. Compositing assumes both
    /// layers sit around that midpoint; a different background would shift the
    /// effective contrast of every dot and the crosstalk cancellation would be
    /// tuned against the wrong reference.
    private var backgroundColour: Color {
        let pixel = compositor.composite(amblyopic: 0.5, fellow: 0.5)
        return Color(red: pixel.red, green: pixel.green, blue: pixel.blue)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, _ in
                advanceIfNeeded(to: timeline.date)
                draw(in: context)
            }
            .frame(width: signal.fieldPoints, height: signal.fieldPoints)
        }
        .background(backgroundColour)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityLabel("Two-eye dot field")
        .onAppear(perform: reset)
        .onChange(of: signalSeed) { _, _ in reset() }
    }

    private func reset() {
        signalGenerator = SeededGenerator(seed: signalSeed)
        noiseGenerator = SeededGenerator(seed: noiseSeed)
        signalDots = KinematogramGenerator.makeDots(signal, generator: &signalGenerator)
        noiseDots = KinematogramGenerator.makeDots(noise, generator: &noiseGenerator)
        lastFrame = .distantPast
    }

    private func advanceIfNeeded(to date: Date) {
        guard date.timeIntervalSince(lastFrame) >= 1.0 / 70.0 else { return }
        lastFrame = date
        KinematogramGenerator.advance(&signalDots, parameters: signal,
                                      generator: &signalGenerator)
        KinematogramGenerator.advance(&noiseDots, parameters: noise,
                                      generator: &noiseGenerator)
    }

    private func draw(in context: GraphicsContext) {
        let compositor = self.compositor

        // Each field is drawn with the OTHER eye's layer at the midpoint, so a
        // dot only ever brightens the eye it belongs to. Drawing both eyes' dots
        // in one pass with both layers active would let a signal dot and a noise
        // dot land on the same pixel and produce a colour neither eye can read.
        let signalPixel = compositor.composite(
            amblyopic: 0.5 + 0.5 * signal.contrast, fellow: 0.5)
        let noisePixel = compositor.composite(
            amblyopic: 0.5, fellow: 0.5 + 0.5 * noise.contrast)

        let signalColour = Color(red: signalPixel.red,
                                 green: signalPixel.green,
                                 blue: signalPixel.blue)
        let noiseColour = Color(red: noisePixel.red,
                                green: noisePixel.green,
                                blue: noisePixel.blue)

        for dot in noiseDots {
            let d = noise.dotDiameterPoints
            context.fill(Path(ellipseIn: CGRect(x: dot.x - d / 2, y: dot.y - d / 2,
                                                width: d, height: d)),
                         with: .color(noiseColour))
        }
        for dot in signalDots {
            let d = signal.dotDiameterPoints
            context.fill(Path(ellipseIn: CGRect(x: dot.x - d / 2, y: dot.y - d / 2,
                                                width: d, height: d)),
                         with: .color(signalColour))
        }
    }
}
