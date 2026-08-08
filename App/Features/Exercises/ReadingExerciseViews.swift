//
//  ReadingExerciseViews.swift
//
//  M11 Letter Rows and M14 Reading Ladder.
//
//  Both are sequential rather than single-response, and both use the shared
//  `ExerciseScaffold` so the fatigue button and break card are identical to
//  every other exercise.
//

import SwiftUI

// MARK: - M11 · Letter Rows

@MainActor
struct HartChartView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = HartChartExercise()

    @State private var chart: HartChart?
    @State private var position = 0
    @State private var answered = false

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "textformat.abc",
            instructions: "One row will be highlighted. Tap its letters in order, left to right. One wrong tap ends the row.",
            onFinish: onFinish
        ) {
            content
        }
        .onChange(of: runner.currentTrial?.id) { _, _ in beginTrial() }
    }

    @ViewBuilder
    private var content: some View {
        if let chart {
            VStack(spacing: Spacing.lg) {
                Text("Tap letter \(position + 1) of \(chart.sequence.count)")
                    .font(TypeScale.callout())
                    .foregroundStyle(Color.textSecondary)

                VStack(spacing: 0) {
                    ForEach(0..<chart.rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<chart.columns, id: \.self) { column in
                                cell(row: row, column: column, chart: chart)
                            }
                        }
                    }
                }

                if case .feedback(let correct) = runner.phase {
                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(correct ? Color.success : Color.textSecondary)
                }
            }
            .padding(.bottom, 90)
        }
    }

    private func cell(row: Int, column: Int, chart: HartChart) -> some View {
        let index = row * chart.columns + column
        let isInSequence = chart.sequence.contains(index)
        let isNext = chart.sequence.indices.contains(position)
            && chart.sequence[position] == index
        let isDone = chart.sequence.prefix(position).contains(index)

        return Text(chart.letters.indices.contains(index) ? chart.letters[index] : "")
            .font(.system(size: chart.letterHeightPoints, weight: .semibold,
                          design: .monospaced))
            .foregroundStyle(isDone ? Color.textSecondary : Color.textPrimary)
            .frame(width: chart.cellPoints, height: chart.cellPoints)
            .background(
                // Only the ROW is highlighted, not the next letter — highlighting
                // the target would turn a tracking task into a tapping task.
                isInSequence ? Color.brandPrimary.opacity(isDone ? 0.10 : 0.18)
                             : Color.clear
            )
            .contentShape(Rectangle())
            .onTapGesture { tap(index: index, isNext: isNext, chart: chart) }
            .accessibilityLabel(chart.letters.indices.contains(index) ? chart.letters[index] : "")
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else { chart = nil; return }
        var generator = SeededGenerator(seed: UInt64(trial.payload.value("seed")))
        chart = exercise.chart(for: trial, calibration: calibration, generator: &generator)
        position = 0
        answered = false
    }

    private func tap(index: Int, isNext: Bool, chart: HartChart) {
        guard runner.phase.acceptsResponses, !answered else { return }

        guard isNext else {
            // One wrong tap ends the row. A forgiving version would let people
            // hunt, which measures search rather than sustained tracking.
            answered = true
            runner.respond(answer: 1)
            return
        }

        position += 1
        if position >= chart.sequence.count {
            answered = true
            runner.respond(answer: 0)
        }
    }
}

// MARK: - M14 · Reading Ladder

@MainActor
struct ReadingLadderView: View {

    let runner: SessionRunner
    let calibration: CalibrationProfile
    var onFinish: (EndReason) -> Void = { _ in }

    private let exercise = ReadingLadderExercise()

    private enum Stage { case reading, question }

    @State private var stage: Stage = .reading
    @State private var passage: ReadingPassage?
    @State private var fontSize: Double = 20
    @State private var startedReadingAt: Date = .now

    var body: some View {
        ExerciseScaffold(
            runner: runner,
            icon: "text.book.closed",
            instructions: "Read the passage at your normal pace, then answer one question about it. The print gets smaller as you go.",
            onFinish: onFinish
        ) {
            content
        }
        .onChange(of: runner.currentTrial?.id) { _, _ in beginTrial() }
    }

    @ViewBuilder
    private var content: some View {
        if let passage {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    switch stage {
                    case .reading:
                        Text(passage.text)
                            .font(.system(size: fontSize))
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Reading passage")

                        AmblyoButton(title: "I've read it", systemImage: "checkmark") {
                            stage = .question
                        }

                    case .question:
                        // The passage is HIDDEN at question time. Leaving it on
                        // screen would turn a reading test into a lookup test,
                        // and the whole point of the question is to prove the
                        // text was actually taken in rather than scanned past.
                        Text(passage.question)
                            .font(TypeScale.headline())

                        ForEach(Array(passage.options.enumerated()), id: \.offset) { index, option in
                            Button {
                                answer(index)
                            } label: {
                                Text(option)
                                    .font(TypeScale.body())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(Spacing.md)
                                    .background(Color.surfaceRaised)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.button,
                                                                style: .continuous))
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel(option)
                        }
                    }

                    if case .feedback(let correct) = runner.phase {
                        Label(correct ? "Correct" : "Not that one",
                              systemImage: correct ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(correct ? Color.success : Color.textSecondary)
                    }
                }
                .padding(Spacing.lg)
                .padding(.bottom, 90)
                .readableContentWidth()
            }
        }
    }

    private func beginTrial() {
        guard let trial = runner.currentTrial else { passage = nil; return }
        passage = exercise.passage(for: trial)
        fontSize = exercise.fontPointSize(for: trial, calibration: calibration)
        stage = .reading
        startedReadingAt = .now
    }

    private func answer(_ index: Int) {
        guard runner.phase.acceptsResponses else { return }
        runner.respond(answer: index)
    }
}
