//
//  LetterStimuli.swift
//
//  Renders the M6 crowded-letter triplet.
//
//  WHY CORE TEXT AND NOT A SwiftUI Text VIEW
//  The letter's HEIGHT has to be an exact angular size, and SwiftUI font sizing
//  is specified in points of em-box, not cap height — the relationship between
//  the two depends on the typeface's internal metrics. Measuring the glyph and
//  scaling to a target cap height is the only way to get "this letter subtends
//  0.5 logMAR" to be true rather than approximately true.
//
//  docs/03-EXERCISE-CATALOG.md M6.
//

import CoreGraphics
import CoreText
import Foundation

enum LetterGenerator {

    /// Draws the target flanked by two letters, on mid-grey.
    static func makeImage(_ p: CrowdedLettersParameters,
                          scale: Double = 2.0) -> CGImage? {
        let width = Int((p.canvasWidth * scale).rounded())
        let height = Int((p.canvasHeight * scale).rounded())
        guard width > 8, height > 8, width <= 4096, height <= 4096 else { return nil }

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(true)

        let ink = 0.5 - 0.5 * p.contrast
        let targetCapHeight = p.letterHeightPoints * scale

        // A monospaced face keeps every letter the same advance width, so the
        // spacing under test is the spacing that was asked for rather than
        // whatever the typeface's kerning decided.
        let probeSize: CGFloat = 100
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, probeSize, nil)
        let capHeightAtProbe = CTFontGetCapHeight(font)
        guard capHeightAtProbe > 0 else { return nil }

        // Scale so cap height lands exactly on the angular target.
        let pointSize = probeSize * (CGFloat(targetCapHeight) / capHeightAtProbe)
        let sized = CTFontCreateWithName("Menlo-Bold" as CFString, pointSize, nil)

        let centreX = Double(width) / 2
        let centreY = Double(height) / 2
        let spacing = p.spacingPoints * scale

        func draw(_ character: String, atX x: Double) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: sized,
                .foregroundColor: CGColor(gray: CGFloat(ink), alpha: 1)
            ]
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: character, attributes: attributes))
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

            // Centre the glyph on (x, centreY) using its actual INK bounds, not
            // its typographic origin. Letters have different side bearings, so
            // positioning by origin leaves the target visibly off-centre and the
            // two flankers no longer equidistant — which would mean the spacing
            // being measured is not the spacing that was requested.
            context.textPosition = CGPoint(
                x: x - Double(bounds.origin.x) - Double(bounds.width) / 2,
                y: centreY - Double(bounds.origin.y) - Double(bounds.height) / 2
            )
            CTLineDraw(line, context)
        }

        if let left = p.flankers.first { draw(left, atX: centreX - spacing) }
        if let right = p.flankers.dropFirst().first { draw(right, atX: centreX + spacing) }
        draw(p.target, atX: centreX)

        return context.makeImage()
    }
}
