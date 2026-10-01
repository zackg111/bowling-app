import SwiftUI
import MapKit
import CoreLocation

/// Where you are, found once. Asks for location access the first time.
@Observable
final class NearbyLocator {
    enum State: Equatable {
        case idle, locating, found, denied, unavailable
    }

    private(set) var state: State = .idle
    private(set) var location: CLLocation?

    func locate() async {
        guard state == .idle || state == .unavailable else { return }
        state = .locating
        // Holding a session while updates run is what asks for permission.
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let found = update.location {
                    location = found
                    state = .found
                    return
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    state = .denied
                    return
                }
            }
        } catch {
            state = .unavailable
        }
    }
}

/// A bowling center from Apple Maps.
struct BowlingCenter: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    /// Meters from you, when your location is known.
    let distance: CLLocationDistance?

    init(_ item: MKMapItem, from location: CLLocation?) {
        name = item.name ?? "Bowling center"
        address = item.address?.shortAddress ?? item.addressRepresentations?.cityWithContext ?? ""
        distance = location.map { item.location.distance(from: $0) }
        id = "\(name)|\(item.location.coordinate.latitude),\(item.location.coordinate.longitude)"
    }
}

/// Picks a home bowling center: the ones nearest you first, or search by name.
struct BowlingCenterPicker: View {
    @Binding var center: String
    @Environment(\.dismiss) private var dismiss
    @State private var locator = NearbyLocator()
    @State private var query = ""
    @State private var results: [BowlingCenter] = []
    @State private var searching = false
    @State private var error: String?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                if locator.state == .denied {
                    Section {
                        Label("Location is off for Bowling League, so centers near you can't be shown. Search by name, or turn it on in Settings.",
                              systemImage: "location.slash")
                            .font(.callout)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: url)
                        }
                    }
                }

                Section {
                    if results.isEmpty {
                        if searching || locator.state == .locating {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(trimmedQuery.isEmpty ? "Finding centers near you…" : "Searching…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if !trimmedQuery.isEmpty || locator.location != nil {
                            Text("No bowling centers found.").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(results) { place in
                        Button { choose(place.name) } label: { row(place) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text(trimmedQuery.isEmpty ? "Near you" : "Bowling centers")
                }

                if !trimmedQuery.isEmpty {
                    Section {
                        Button("Use “\(trimmedQuery)”", systemImage: "pencil") { choose(trimmedQuery) }
                    } footer: {
                        Text("Not listed? Use the name as you typed it.")
                    }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .laneBackground()
            .navigationTitle("Home Center")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search bowling centers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !center.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") { choose("") }
                    }
                }
            }
            .task { await locator.locate() }
            // Search again as you type (after a pause) and once your location comes in.
            .task(id: "\(trimmedQuery)|\(locator.location != nil)") {
                if !trimmedQuery.isEmpty {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                }
                await search()
            }
        }
    }

    private func row(_ place: BowlingCenter) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.bowling")
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .glassEffect(in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.headline)
                if !place.address.isEmpty {
                    Text(place.address).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let distance = place.distance {
                Text(Measurement(value: distance, unit: UnitLength.meters),
                     format: .measurement(width: .abbreviated, usage: .road))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if place.name == center {
                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
            }
        }
        .contentShape(.rect)
    }

    private func search() async {
        let location = locator.location
        let text = trimmedQuery
        guard !text.isEmpty || location != nil else {
            results = []
            return
        }
        searching = true
        defer { searching = false }
        let bowling = MKPointOfInterestFilter(including: [.bowling])
        do {
            let response: MKLocalSearch.Response
            if text.isEmpty, let location {
                // No search yet: bowling centers within about 25 miles.
                let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 40_000)
                request.pointOfInterestFilter = bowling
                response = try await MKLocalSearch(request: request).start()
            } else {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = text
                request.resultTypes = .pointOfInterest
                request.pointOfInterestFilter = bowling
                if let location {
                    request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 100_000, longitudinalMeters: 100_000)
                }
                response = try await MKLocalSearch(request: request).start()
            }
            results = response.mapItems
                .map { BowlingCenter($0, from: location) }
                .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
            error = nil
        } catch let failure as MKError where failure.code == .placemarkNotFound {
            results = []
        } catch {
            results = []
            self.error = error.localizedDescription
        }
    }

    private func choose(_ name: String) {
        center = name
        dismiss()
    }
}

/// A form row showing the home center; tap to pick one.
struct HomeCenterField: View {
    @Binding var center: String
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            HStack {
                Label("Home center", systemImage: "mappin.and.ellipse")
                    .foregroundStyle(.primary)
                Spacer()
                Text(center.isEmpty ? "Choose" : center)
                    .foregroundStyle(center.isEmpty ? Theme.accent : .secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $picking) { BowlingCenterPicker(center: $center) }
    }
}
