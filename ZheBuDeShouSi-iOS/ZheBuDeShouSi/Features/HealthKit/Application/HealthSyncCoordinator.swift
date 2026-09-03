import Foundation
import Combine

@MainActor
final class HealthSyncCoordinator: ObservableObject {
    @Published private(set) var connectionState: HealthKitConnectionState
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var importedWeightCount = 0
    @Published private(set) var importedWaistCount = 0
    @Published private(set) var importedHabitCount = 0
    @Published private(set) var importedDietCount = 0

    private let client: HealthKitClient

    init(client: HealthKitClient = LiveHealthKitClient()) {
        self.client = client
        connectionState = client.isAvailable ? .notConnected : .unavailable
    }

    var isAvailable: Bool { client.isAvailable }
    var isSyncing: Bool { connectionState == .syncing }

    func connectAndSync(
        appState: AppState,
        healthStore: HealthStore,
        dietStore: DietStore? = nil
    ) async {
        guard !isSyncing else { return }
        guard client.isAvailable else {
            connectionState = .unavailable
            return
        }

        connectionState = .syncing
        do {
            try await client.requestAuthorization()
            let since = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now
            async let weightSamples = client.fetchWeightSamples(since: since)
            async let waistSamples = client.fetchWaistSamples(since: since)
            async let habitSamples = client.fetchHabitSamples(since: since)
            let (weights, waists, habits) = try await (weightSamples, waistSamples, habitSamples)

            importedWeightCount = appState.importHealthKitWeights(weights)
            importedWaistCount = healthStore.importHealthKitWaistSamples(waists)
            importedHabitCount = healthStore.importHealthKitHabitSamples(habits)
            let energySamples = habits
                .filter { $0.kind == .meal }
                .map { DietEnergySample(id: $0.id, date: $0.date, kilocalories: $0.value) }
            importedDietCount = dietStore?.importEnergySamples(energySamples) ?? 0
            lastSyncDate = .now
            connectionState = .connected
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }
}
