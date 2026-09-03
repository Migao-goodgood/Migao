import Foundation
import Combine

/// Owns verified body-composition snapshots and measurement cadence. Views do
/// not write UserDefaults directly.
@MainActor
final class BodyTrendStore: ObservableObject {
    static let storageKey = "zhebudeshousi.bodyTrendStore.v1"

    @Published private(set) var snapshots: [InBodySnapshot] = []
    @Published private(set) var measurementSchedule: InBodyMeasurementSchedule = .defaultSchedule

    private let defaults: UserDefaults
    private let comparisonService: InBodyComparisonService

    init(
        defaults: UserDefaults = .standard,
        comparisonService: InBodyComparisonService = InBodyComparisonService()
    ) {
        self.defaults = defaults
        self.comparisonService = comparisonService
        load()
    }

    /// Newest snapshot, if at least one verified record exists.
    var latest: InBodySnapshot? { snapshots.first }

    /// Chronological order for a left-to-right timeline (oldest first).
    var orderedSnapshots: [InBodySnapshot] {
        snapshots.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.date < rhs.date
        }
    }

    /// Inserts or updates a snapshot by ID. A valid weight is required; other
    /// fields may be absent when OCR could not confidently find them.
    @discardableResult
    func add(_ record: InBodySnapshot) -> Bool {
        guard let cleaned = validated(record) else { return false }
        if let index = snapshots.firstIndex(where: { $0.id == cleaned.id }) {
            snapshots[index] = cleaned
        } else {
            snapshots.append(cleaned)
        }
        sortAndSave()
        return true
    }

    func remove(id: UUID) {
        snapshots.removeAll { $0.id == id }
        save()
    }

    func remove(_ snapshot: InBodySnapshot) {
        remove(id: snapshot.id)
    }

    func removeAll() {
        snapshots.removeAll()
        save()
    }

    /// Finds an existing check-in that is very likely the same paper report.
    /// The narrow time window avoids blocking legitimate measurements on the
    /// same day while still catching accidental double uploads.
    func likelyDuplicate(
        of record: InBodySnapshot,
        timeTolerance: TimeInterval = 10 * 60
    ) -> InBodySnapshot? {
        guard let weight = record.weightKg else { return nil }
        return snapshots.first { existing in
            guard existing.id != record.id,
                  let existingWeight = existing.weightKg else { return false }
            return abs(existing.date.timeIntervalSince(record.date)) <= timeTolerance
                && abs(existingWeight - weight) < 0.05
        }
    }

    /// Comparison against both the immediately preceding and first check-in.
    /// The service owns all arithmetic so views only render the result.
    func comparison(
        for snapshot: InBodySnapshot,
        weightUnit: WeightUnit = .kilograms
    ) -> InBodyProgressComparison {
        comparisonService.comparison(for: snapshot, in: snapshots, weightUnit: weightUnit)
    }

    var latestComparison: InBodyProgressComparison? {
        latest.map { comparison(for: $0) }
    }

    func updateMeasurementSchedule(_ schedule: InBodyMeasurementSchedule) {
        let cleaned = schedule.normalized()
        guard cleaned != measurementSchedule else { return }
        measurementSchedule = cleaned
        save()
    }

    func measurementDueStatus(
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> InBodyMeasurementDueStatus {
        guard measurementSchedule.isEnabled else { return .disabled }
        guard let latest else { return .noMeasurements }
        guard let dueDate = measurementSchedule.nextDueDate(
            after: latest.date,
            asOf: now,
            calendar: calendar
        ) else {
            return .noMeasurements
        }
        return dueDate <= now ? .due(dueDate) : .upcoming(dueDate)
    }

    /// Returns records in the calendar month containing the supplied date.
    func snapshots(inMonth date: Date, calendar: Calendar = .current) -> [InBodySnapshot] {
        snapshots.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
    }

    private struct PersistedSnapshot: Codable {
        var version: Int
        var snapshots: [InBodySnapshot]
        var measurementSchedule: InBodyMeasurementSchedule?
    }

    private func validated(_ record: InBodySnapshot) -> InBodySnapshot? {
        var copy = record.normalized()
        guard let weight = copy.weightKg, weight.isFinite, (20...400).contains(weight) else {
            return nil
        }
        guard copy.date >= Self.earliestMeasurementDate,
              copy.date <= Date().addingTimeInterval(5 * 60) else {
            return nil
        }

        copy.heightCm = valid(copy.heightCm, range: 80...260)
        copy.bodyFatKg = valid(copy.bodyFatKg, range: 0...200)
        copy.bodyFatPercentage = valid(copy.bodyFatPercentage, range: 0...100)
        copy.skeletalMuscleKg = valid(copy.skeletalMuscleKg, range: 0...150)
        copy.bmi = valid(copy.bmi, range: 5...100)
        copy.visceralFatLevel = valid(copy.visceralFatLevel, range: 0...100)
        copy.score = valid(copy.score, range: 0...100)
        copy.waistHipRatio = valid(copy.waistHipRatio, range: 0.2...3)
        copy.totalBodyWaterL = valid(copy.totalBodyWaterL, range: 0...150)
        copy.proteinKg = valid(copy.proteinKg, range: 0...100)
        copy.mineralKg = valid(copy.mineralKg, range: 0...30)
        copy.fatFreeMassKg = valid(copy.fatFreeMassKg, range: 0...300)
        copy.bodyCellMassKg = valid(copy.bodyCellMassKg, range: 0...200)
        copy.basalMetabolicRate = valid(copy.basalMetabolicRate, range: 0...10_000)
        copy.smiKgPerM2 = valid(copy.smiKgPerM2, range: 0...30)
        copy.targetWeightKg = valid(copy.targetWeightKg, range: 20...400)
        copy.recommendedCalories = valid(copy.recommendedCalories, range: 0...20_000)
        copy.age = copy.age.flatMap { (0...130).contains($0) ? $0 : nil }
        return copy
    }

    private static var earliestMeasurementDate: Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2000, month: 1, day: 1)
        ) ?? .distantPast
    }

    private func valid(_ value: Double?, range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }

    private func sortAndSave() {
        snapshots.sort { lhs, rhs in
            if lhs.date == rhs.date { return lhs.id.uuidString > rhs.id.uuidString }
            return lhs.date > rhs.date
        }
        save()
    }

    private func save() {
        let payload = PersistedSnapshot(
            version: 3,
            snapshots: snapshots,
            measurementSchedule: measurementSchedule
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let payload = try? JSONDecoder().decode(PersistedSnapshot.self, from: data) else { return }
        snapshots = payload.snapshots.compactMap { validated($0) }.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.id.uuidString > rhs.id.uuidString }
            return lhs.date > rhs.date
        }
        measurementSchedule = payload.measurementSchedule?.normalized() ?? .defaultSchedule
    }
}
