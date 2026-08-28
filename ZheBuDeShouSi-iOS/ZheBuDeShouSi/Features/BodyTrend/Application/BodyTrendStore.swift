import Foundation
import Combine

/// Owns body-composition snapshots and the avatar preferences used by the
/// trend workspace. Views do not write UserDefaults directly.
@MainActor
final class BodyTrendStore: ObservableObject {
    static let storageKey = "zhebudeshousi.bodyTrendStore.v1"
    static let maxAvatarImageBytes = 16 * 1024 * 1024

    @Published private(set) var snapshots: [InBodySnapshot] = []
    @Published private(set) var selectedAvatarStyle: AvatarStyle = .human
    @Published private(set) var avatarImageData: Data?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Alias kept for presentation code that reads the selected style as a
    /// simple preference.
    var avatarStyle: AvatarStyle { selectedAvatarStyle }

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

    func setAvatarStyle(_ style: AvatarStyle) {
        guard selectedAvatarStyle != style else { return }
        selectedAvatarStyle = style
        save()
    }

    /// Stores the selected avatar image. Callers should downsample photos
    /// before passing them here; the upper bound protects UserDefaults from
    /// accidentally receiving a camera-original file.
    @discardableResult
    func setAvatarImageData(_ data: Data?) -> Bool {
        if let data, data.count > Self.maxAvatarImageBytes { return false }
        avatarImageData = data
        save()
        return true
    }

    func assessment(for snapshot: InBodySnapshot) -> BodyTrendAssessment {
        let ordered = orderedSnapshots
        let previous: InBodySnapshot?
        if let index = ordered.firstIndex(where: { $0.id == snapshot.id }), index > 0 {
            previous = ordered[index - 1]
        } else {
            previous = nil
        }
        return BodyTrendEvaluator.evaluate(snapshot: snapshot, previous: previous)
    }

    var latestAssessment: BodyTrendAssessment? {
        guard let latest else { return nil }
        return assessment(for: latest)
    }

    /// Returns records in the calendar month containing the supplied date.
    func snapshots(inMonth date: Date, calendar: Calendar = .current) -> [InBodySnapshot] {
        snapshots.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
    }

    private struct PersistedSnapshot: Codable {
        var version: Int
        var snapshots: [InBodySnapshot]
        var avatarStyle: AvatarStyle?
        var avatarImageData: Data?
    }

    private func validated(_ record: InBodySnapshot) -> InBodySnapshot? {
        var copy = record.normalized()
        guard let weight = copy.weightKg, weight.isFinite, (20...400).contains(weight) else {
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
        copy.bodyWaterKg = valid(copy.bodyWaterKg, range: 0...150)
        copy.proteinKg = valid(copy.proteinKg, range: 0...100)
        copy.mineralKg = valid(copy.mineralKg, range: 0...30)
        copy.fatFreeMassKg = valid(copy.fatFreeMassKg, range: 0...300)
        copy.basalMetabolicRate = valid(copy.basalMetabolicRate, range: 0...10_000)
        copy.targetWeightKg = valid(copy.targetWeightKg, range: 20...400)
        copy.recommendedCalories = valid(copy.recommendedCalories, range: 0...20_000)
        copy.age = copy.age.flatMap { (0...130).contains($0) ? $0 : nil }
        return copy
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
            version: 1,
            snapshots: snapshots,
            avatarStyle: selectedAvatarStyle,
            avatarImageData: avatarImageData
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
        selectedAvatarStyle = payload.avatarStyle ?? .human
        if let imageData = payload.avatarImageData,
           imageData.count <= Self.maxAvatarImageBytes {
            avatarImageData = imageData
        }
    }
}
