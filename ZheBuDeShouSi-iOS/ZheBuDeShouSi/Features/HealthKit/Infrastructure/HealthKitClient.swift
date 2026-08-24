import Foundation

#if os(iOS) && canImport(HealthKit)
import HealthKit
#endif

enum HealthKitClientError: LocalizedError, Equatable {
    case unavailable
    case authorizationDenied
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "这台设备暂不支持 Apple 健康"
        case .authorizationDenied:
            return "没有获得 Apple 健康读取权限，请在系统设置中允许"
        case .requestFailed(let message):
            return message
        }
    }
}

protocol HealthKitClient {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func fetchWeightSamples(since: Date) async throws -> [HealthKitWeightSample]
    func fetchWaistSamples(since: Date) async throws -> [HealthKitWaistSample]
    func fetchHabitSamples(since: Date) async throws -> [HealthKitHabitSample]
}

#if os(iOS) && canImport(HealthKit)
final class LiveHealthKitClient: HealthKitClient {
    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitClientError.unavailable }

        var readTypes = Set<HKObjectType>()
        if let type = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            readTypes.insert(type)
        }
        if let type = HKObjectType.quantityType(forIdentifier: .waistCircumference) {
            readTypes.insert(type)
        }
        for identifier in [
            HKQuantityTypeIdentifier.dietaryEnergyConsumed,
            HKQuantityTypeIdentifier.dietaryWater,
            HKQuantityTypeIdentifier.appleExerciseTime
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                readTypes.insert(type)
            }
        }
        for identifier in [
            HKCategoryTypeIdentifier.sleepAnalysis,
            HKCategoryTypeIdentifier.menstrualFlow
        ] {
            if let type = HKObjectType.categoryType(forIdentifier: identifier) {
                readTypes.insert(type)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: HealthKitClientError.requestFailed(error.localizedDescription))
                } else if !success {
                    continuation.resume(throwing: HealthKitClientError.authorizationDenied)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func fetchWeightSamples(since: Date) async throws -> [HealthKitWeightSample] {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let samples = try await query(type: type, since: since)
        return samples.compactMap { sample in
            guard let quantitySample = sample as? HKQuantitySample else { return nil }
            return HealthKitMapper.weight(from: quantitySample)
        }
    }

    func fetchWaistSamples(since: Date) async throws -> [HealthKitWaistSample] {
        guard let type = HKObjectType.quantityType(forIdentifier: .waistCircumference) else { return [] }
        let samples = try await query(type: type, since: since)
        return samples.compactMap { sample in
            guard let quantitySample = sample as? HKQuantitySample else { return nil }
            return HealthKitMapper.waist(from: quantitySample)
        }
    }

    func fetchHabitSamples(since: Date) async throws -> [HealthKitHabitSample] {
        var result: [HealthKitHabitSample] = []
        let quantityDefinitions: [(HKQuantityTypeIdentifier, HabitKind, HKUnit, String)] = [
            (.dietaryEnergyConsumed, .meal, .kilocalorie(), "kcal"),
            (.dietaryWater, .water, .literUnit(with: .milli), "ml"),
            (.appleExerciseTime, .exercise, .minute(), "分钟")
        ]

        for (identifier, kind, unit, label) in quantityDefinitions {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let samples = try await query(type: type, since: since)
            result.append(contentsOf: samples.compactMap { sample in
                guard let quantitySample = sample as? HKQuantitySample else { return nil }
                return HealthKitMapper.habit(from: quantitySample, kind: kind, unit: unit, label: label)
            })
        }

        if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            let samples = try await query(type: type, since: since)
            result.append(contentsOf: samples.compactMap { sample in
                guard let categorySample = sample as? HKCategorySample,
                      categorySample.value != 0,
                      categorySample.value != 2 else { return nil }
                return HealthKitMapper.habit(from: categorySample, kind: .sleep, note: "Apple 健康 · 睡眠记录")
            })
        }

        if let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow) {
            let samples = try await query(type: type, since: since)
            result.append(contentsOf: samples.compactMap { sample in
                guard let categorySample = sample as? HKCategorySample else { return nil }
                return HealthKitMapper.habit(from: categorySample, kind: .menstrualCycle, note: "Apple 健康 · 生理期记录")
            })
        }
        return result
    }

    private func query(type: HKSampleType, since: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitClientError.requestFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }
}
#else
final class LiveHealthKitClient: HealthKitClient {
    var isAvailable: Bool { false }

    func requestAuthorization() async throws {
        throw HealthKitClientError.unavailable
    }

    func fetchWeightSamples(since: Date) async throws -> [HealthKitWeightSample] {
        throw HealthKitClientError.unavailable
    }

    func fetchWaistSamples(since: Date) async throws -> [HealthKitWaistSample] {
        throw HealthKitClientError.unavailable
    }

    func fetchHabitSamples(since: Date) async throws -> [HealthKitHabitSample] {
        throw HealthKitClientError.unavailable
    }
}
#endif
