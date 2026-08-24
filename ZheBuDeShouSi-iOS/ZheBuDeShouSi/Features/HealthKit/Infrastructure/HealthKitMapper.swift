import Foundation

#if os(iOS) && canImport(HealthKit)
import HealthKit

enum HealthKitMapper {
    static func weight(from sample: HKQuantitySample) -> HealthKitWeightSample {
        HealthKitWeightSample(
            id: sample.uuid.uuidString,
            date: sample.startDate,
            kilograms: sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        )
    }

    static func waist(from sample: HKQuantitySample) -> HealthKitWaistSample {
        HealthKitWaistSample(
            id: sample.uuid.uuidString,
            date: sample.startDate,
            centimeters: sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
        )
    }

    static func habit(from sample: HKQuantitySample, kind: HabitKind, unit: HKUnit, label: String) -> HealthKitHabitSample {
        let value = sample.quantity.doubleValue(for: unit)
        return HealthKitHabitSample(
            id: sample.uuid.uuidString,
            date: sample.startDate,
            kind: kind,
            value: value,
            unit: label,
            note: "Apple 健康 · \(String(format: "%.0f", value)) \(label)"
        )
    }

    static func habit(from sample: HKCategorySample, kind: HabitKind, note: String) -> HealthKitHabitSample {
        HealthKitHabitSample(
            id: sample.uuid.uuidString,
            date: sample.startDate,
            kind: kind,
            value: sample.endDate.timeIntervalSince(sample.startDate),
            unit: "",
            note: note
        )
    }
}
#endif
