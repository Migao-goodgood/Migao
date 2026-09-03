import Foundation
import Combine

@MainActor
final class HealthStore: ObservableObject {
    static let storageKey = "zhebudeshousi.healthStore"

    @Published private(set) var bodyMeasurements: [BodyMeasurementRecord] = []
    @Published private(set) var habitRecords: [HabitRecord] = []

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        load()
    }

    var todayCompletedHabitCount: Int {
        HabitKind.allCases.filter { isCompleted($0, on: .now) }.count
    }

    func isCompleted(_ kind: HabitKind, on date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        return habitRecords.first { record in
            record.kind == kind && calendar.isDate(record.date, inSameDayAs: day)
        }?.completed ?? false
    }

    func toggleHabit(_ kind: HabitKind, on date: Date = .now) {
        let day = calendar.startOfDay(for: date)
        if let index = habitRecords.firstIndex(where: { $0.kind == kind && calendar.isDate($0.date, inSameDayAs: day) }) {
            habitRecords[index].completed.toggle()
            habitRecords[index].source = .manual
        } else {
            habitRecords.insert(HabitRecord(date: day, kind: kind, completed: true), at: 0)
        }
        sortAndSave()
    }

    func recordHabit(_ kind: HabitKind, on date: Date = .now, note: String = "") {
        let day = calendar.startOfDay(for: date)
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = habitRecords.firstIndex(where: { $0.kind == kind && calendar.isDate($0.date, inSameDayAs: day) }) {
            habitRecords[index].completed = true
            habitRecords[index].note = cleanedNote
            habitRecords[index].source = .manual
        } else {
            habitRecords.insert(
                HabitRecord(date: day, kind: kind, completed: true, note: cleanedNote),
                at: 0
            )
        }
        sortAndSave()
    }

    func addMeasurement(
        type: BodyMeasurementType,
        valueCm: Double,
        date: Date = .now,
        note: String = "",
        source: HealthRecordSource = .manual,
        externalIdentifier: String? = nil
    ) -> Bool {
        guard valueCm.isFinite, (10...300).contains(valueCm) else { return false }
        bodyMeasurements.insert(
            BodyMeasurementRecord(
                date: date,
                type: type,
                valueCm: (valueCm * 10).rounded() / 10,
                source: source,
                note: note,
                externalIdentifier: externalIdentifier
            ),
            at: 0
        )
        sortAndSave()
        return true
    }

    @discardableResult
    func importHealthKitWaistSamples(_ samples: [HealthKitWaistSample]) -> Int {
        let importedRecords = samples.compactMap { sample -> BodyMeasurementRecord? in
            guard sample.centimeters.isFinite, (10...300).contains(sample.centimeters),
                  !bodyMeasurements.contains(where: { $0.externalIdentifier == sample.id }) else { return nil }
            return BodyMeasurementRecord(
                date: sample.date,
                type: .waist,
                valueCm: (sample.centimeters * 10).rounded() / 10,
                source: .healthKit,
                note: "来自 Apple 健康",
                externalIdentifier: sample.id
            )
        }
        guard !importedRecords.isEmpty else { return 0 }
        bodyMeasurements.append(contentsOf: importedRecords)
        sortAndSave()
        return importedRecords.count
    }

    @discardableResult
    func importHealthKitHabitSamples(_ samples: [HealthKitHabitSample]) -> Int {
        var importedRecords: [HabitRecord] = []
        var importedDays = Set<String>()

        for sample in samples.sorted(by: { $0.date < $1.date }) {
            guard !habitRecords.contains(where: { $0.externalIdentifier == sample.id }) else { continue }
            let day = calendar.startOfDay(for: sample.date)
            let dayKey = "\(day.timeIntervalSinceReferenceDate)|\(sample.kind.rawValue)"
            guard !importedDays.contains(dayKey) else { continue }

            let hasExistingRecord = habitRecords.contains {
                $0.kind == sample.kind && calendar.isDate($0.date, inSameDayAs: day)
            }
            guard !hasExistingRecord else { continue }

            importedRecords.append(
                HabitRecord(
                    date: day,
                    kind: sample.kind,
                    completed: true,
                    note: sample.note,
                    source: .healthKit,
                    externalIdentifier: sample.id
                )
            )
            importedDays.insert(dayKey)
        }

        guard !importedRecords.isEmpty else { return 0 }
        habitRecords.append(contentsOf: importedRecords)
        sortAndSave()
        return importedRecords.count
    }

    func records(for type: BodyMeasurementType) -> [BodyMeasurementRecord] {
        bodyMeasurements
            .filter { $0.type == type }
            .sorted { $0.date < $1.date }
    }

    func latestMeasurement(for type: BodyMeasurementType) -> BodyMeasurementRecord? {
        bodyMeasurements.first { $0.type == type }
    }

    private struct Snapshot: Codable {
        var bodyMeasurements: [BodyMeasurementRecord]
        var habitRecords: [HabitRecord]
    }

    private func sortAndSave() {
        bodyMeasurements.sort { $0.date > $1.date }
        habitRecords.sort { $0.date > $1.date }
        save()
    }

    private func save() {
        let snapshot = Snapshot(bodyMeasurements: bodyMeasurements, habitRecords: habitRecords)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        bodyMeasurements = snapshot.bodyMeasurements.sorted { $0.date > $1.date }
        habitRecords = snapshot.habitRecords.sorted { $0.date > $1.date }
    }
}
