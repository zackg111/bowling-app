import SwiftUI
import SwiftData
import PhotosUI

/// First launch: who you are and your profile. Makes (or picks) your bowler,
/// marks it "This is me", and sets up the profile friends find you by.
struct OnboardingView: View {
    enum Step { case welcome, restore, pickBowler, aboutYou }

    /// Called once setup is finished or skipped.
    var onFinish: () -> Void

    @Environment(SocialService.self) private var social
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Bowler> { $0.isActive }, sort: \Bowler.name) private var bowlers: [Bowler]
    @Query(sort: \Night.date, order: .reverse) private var nights: [Night]
    @State private var step: Step
    /// The bowler already in the league who is you. Nil makes a new one.
    @State private var chosen: Bowler?
    @State private var name = ""
    @State private var averageText = ""
    @State private var center = ""
    @State private var photo: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var saving = false
    @State private var error: String?

    /// `restoring` starts by bringing back a league already in this iCloud account.
    init(restoring: Bool = false, onFinish: @escaping () -> Void = {}) {
        self.onFinish = onFinish
        _step = State(initialValue: restoring ? .restore : .welcome)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .restore: RestoreView { restored($0) }
                case .pickBowler: pickBowler
                case .aboutYou: aboutYou
                }
            }
            .laneBackground()
            .animation(.snappy, value: step)
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .navigation) {
                        Button("Back", systemImage: "chevron.left") { goBack() }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish() }
                }
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: photoItem) {
            Task {
                if let data = try? await photoItem?.loadTransferable(type: Data.self) {
                    photo = AvatarPicker.downscaled(data)
                }
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "figure.bowling")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(28)
                .glassEffect(in: .circle)
            VStack(spacing: 8) {
                Text("Welcome to Bowling League")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Set up your profile to get started.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("chart.xyaxis.line", "Your stats", "Strikes, spares, pin leaves and your average, night by night.")
                feature("person.2.fill", "Friends", "Follow friends, compare stats and rank against them each month.")
                feature("circle.circle", "Your arsenal", "Track your balls and how you bowl with each one.")
            }
            .padding(20)
            .glassEffect(in: .rect(cornerRadius: 24))
            Spacer()
            VStack(spacing: 12) {
                Button { start() } label: {
                    Text("Get Started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button { step = .restore } label: {
                    Label("Restore from iCloud", systemImage: "icloud.and.arrow.down").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .padding(24)
    }

    private func feature(_ systemImage: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var pickBowler: some View {
        List {
            Section {
                ForEach(bowlers) { bowler in
                    Button { pick(bowler) } label: {
                        HStack(spacing: 12) {
                            AvatarView(bowler: bowler, size: 40)
                            Text(bowler.name).font(.headline)
                            Spacer()
                            Text("\(bowler.average)").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Are you already in this league?")
            } footer: {
                Text("Pick yourself so your nights count in your stats.")
            }
            Section {
                Button("I'm Not in the List", systemImage: "person.badge.plus") { pick(nil) }
            }
        }
        .navigationTitle("Which One Is You?")
    }

    private var aboutYou: some View {
        // The picker's label is built off the main actor, so it gets a copy.
        let preview = AvatarView(name: name, photoData: photo, size: 110)
        return Form {
            Section {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    preview
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill").padding(8).glassEffect()
                        }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                TextField("Your name", text: $name)
                    .textContentType(.name)
                TextField("Your average (leave blank if you don't know)", text: $averageText)
                    .keyboardType(.numberPad)
                HomeCenterField(center: $center)
            } footer: {
                Text(footer)
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Continue Without a Profile") { finish() }
                }
            }
            Section {
                Button { Task { await save() } } label: {
                    HStack {
                        Spacer()
                        if saving { ProgressView() } else { Text("Finish").bold() }
                        Spacer()
                    }
                }
                .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("About You")
    }

    private var footer: String {
        switch social.status {
        case .noAccount:
            "You're not signed in to iCloud, so friends can't find you yet. Your stats still work on this phone. Sign in under Settings and set up your profile later from Profile."
        case .failed:
            "iCloud isn't reachable right now. Your stats still work, and you can finish your profile later from Profile."
        default:
            "Friends find you by name and see your stats and the nights you've bowled. Your league's other bowlers stay private."
        }
    }

    // MARK: Actions

    private func start() {
        if let me = bowlers.first(where: \.isPrimary) {
            pick(me)
        } else if bowlers.isEmpty {
            pick(nil)
        } else {
            step = .pickBowler
        }
    }

    private func pick(_ bowler: Bowler?) {
        chosen = bowler
        name = social.me?.name ?? bowler?.name ?? ""
        averageText = bowler.map { $0.average > 0 ? "\($0.average)" : "" } ?? ""
        center = bowler.map(\.homeCenter).flatMap { $0.isEmpty ? nil : $0 }
            ?? social.me?.center ?? nights.first(where: { !$0.location.isEmpty })?.location ?? ""
        photo = bowler?.photoData ?? social.me?.photo
        step = .aboutYou
    }

    private func goBack() {
        let alreadyMe = bowlers.contains(where: \.isPrimary)
        step = step == .aboutYou && !bowlers.isEmpty && !alreadyMe ? .pickBowler : .welcome
    }

    private func restored(_ outcome: RestoreView.Outcome) {
        switch outcome {
        case .restored:
            // Back with "This is me", but no profile for friends yet: finish that.
            if social.status == .needsProfile, let me = bowlers.first(where: \.isPrimary) {
                pick(me)
            } else {
                finish()
            }
        case .restoredWithoutMe:
            if bowlers.isEmpty { finish() } else { step = .pickBowler }
        case .nothingFound:
            start()
        case .skipped:
            finish()
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let average = Int(averageText.filter(\.isWholeNumber))

        let bowler: Bowler
        if let chosen {
            bowler = chosen
        } else {
            bowler = Bowler(name: trimmed, average: average ?? 0)
            context.insert(bowler)
        }
        bowler.name = trimmed
        if let average { bowler.average = min(average, GameSheet.perfectGame) }
        bowler.photoData = photo
        bowler.homeCenter = center.trimmingCharacters(in: .whitespaces)
        bowler.makePrimary(in: context)
        try? context.save()

        // iCloud may still be finding the account on first launch.
        if social.status == .checking { await social.refresh() }
        guard social.status == .ready || social.status == .needsProfile else {
            finish()
            return
        }
        do {
            try await social.saveProfile(from: bowler)
            await social.shareLeague(from: context)
            finish()
        } catch {
            self.error = "Couldn't save your profile: \(error.localizedDescription)"
        }
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}
