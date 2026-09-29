import SwiftUI

enum WatchTheme {
    static let accent = Color(red: 1.00, green: 0.42, blue: 0.24)      // lane-light orange, as on the phone
    static let secondAccent = Color(red: 0.45, green: 0.36, blue: 0.98) // ball violet
}

struct ContentView: View {
    @State private var tracker = ShotTracker()
    @AppStorage("armLength") private var armLength = SwingAnalysis.defaultArmLength

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    LastShotView(shot: tracker.lastShot)

                    HStack(spacing: 6) {
                        StatPill(title: "Shots", value: "\(tracker.shots.count)")
                        StatPill(title: "Avg", value: mph(tracker.averageSpeed))
                        StatPill(title: "Top", value: mph(tracker.topSpeed))
                    }

                    status

                    #if DEBUG
                    if tracker.state == .tracking {
                        Button("Simulate shot", systemImage: "wand.and.stars") { tracker.simulateShot() }
                            .buttonStyle(.glass)
                    }
                    #endif

                    if !tracker.shots.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This session").font(.caption2).foregroundStyle(.secondary)
                            ForEach(Array(tracker.shots.enumerated().reversed()), id: \.offset) { index, shot in
                                HStack {
                                    Text("\(index + 1)").foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(mph(shot.releaseSpeedMPH)) mph").bold()
                                    Text("\(Int(shot.wristRotationRPM.rounded())) rpm")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.footnote.monospacedDigit())
                            }
                        }
                        .padding(10)
                        .glassEffect(in: .rect(cornerRadius: 14))
                    }

                    NavigationLink {
                        ArmLengthView(armLength: $armLength)
                    } label: {
                        Label("Arm length \(armLength, format: .number.precision(.fractionLength(2))) m", systemImage: "ruler")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Bowling")
            .containerBackground(WatchTheme.accent.gradient.opacity(0.35), for: .navigation)
        }
        .tint(WatchTheme.accent)
        .fontDesign(.rounded)
        .task {
            tracker.armLength = armLength
            await tracker.start()
        }
        .onChange(of: armLength) { _, new in tracker.armLength = new }
    }

    @ViewBuilder private var status: some View {
        switch tracker.state {
        case .tracking:
            if !tracker.motionSupported {
                Text("Motion sensors aren't available on this device.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("End", systemImage: "stop.fill", role: .destructive) { Task { await tracker.stop() } }
                .buttonStyle(.glass)
                .controlSize(.small)
        case .starting:
            ProgressView("Starting…")
        case .idle, .failed:
            if case .failed(let message) = tracker.state {
                Text(message).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("Start Session", systemImage: "figure.bowling") { Task { await tracker.start() } }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
    }

    private func mph(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–"
    }
}

private struct LastShotView: View {
    let shot: ShotMetrics?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(shot.map { $0.releaseSpeedMPH.formatted(.number.precision(.fractionLength(1))) } ?? "--.-")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("mph").font(.headline).foregroundStyle(WatchTheme.accent)
            }
            Text(shot.map { "\(Int($0.wristRotationRPM.rounded())) rpm wrist" } ?? "Waiting for a shot")
                .font(.footnote)
                .foregroundStyle(WatchTheme.secondAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .glassEffect(in: .rect(cornerRadius: 18))
        .animation(.snappy, value: shot)
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .glassEffect(in: .capsule)
    }
}

private struct ArmLengthView: View {
    @Binding var armLength: Double

    var body: some View {
        VStack(spacing: 8) {
            Text("\(armLength, format: .number.precision(.fractionLength(2))) m")
                .font(.title2.bold().monospacedDigit())
            Slider(value: $armLength, in: 0.55...0.85, step: 0.01)
            Text("Shoulder to palm. Used to turn arm swing into ball speed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .navigationTitle("Arm Length")
    }
}
