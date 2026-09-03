import Foundation

/// A solar-term note shown only on the solar term's local calendar day.
struct SolarTermGreeting: Identifiable, Equatable {
    let name: String
    let date: Date
    let text: String

    var id: String { "\(name)-\(date.timeIntervalSinceReferenceDate)" }
}

/// Day-level solar-term lookup for the Chinese calendar.
///
/// The standard 21st-century solar-term formula is sufficient for deciding
/// which local day to decorate. The text is kept here, outside SwiftUI, so the
/// presentation layer has no calendar or copywriting rules embedded in it.
enum SolarTermService {
    private struct Definition {
        let name: String
        let month: Int
        let constant: Double
        let text: String
    }

    private static let definitions: [Definition] = [
        Definition(name: "小寒", month: 1, constant: 5.4055, text: "十二月节，月初寒尚小，故云；月半则大矣。"),
        Definition(name: "大寒", month: 1, constant: 20.12, text: "十二月中，解见前。"),
        Definition(name: "立春", month: 2, constant: 3.87, text: "正月节，立，建始也；春气始至，万物更新。"),
        Definition(name: "雨水", month: 2, constant: 18.73, text: "正月中，天一生水，春始属木，然生木者必水也。"),
        Definition(name: "惊蛰", month: 3, constant: 5.63, text: "二月节，万物出乎震，震为雷，故曰惊蛰。"),
        Definition(name: "春分", month: 3, constant: 20.646, text: "二月中，分者半也，此当九十日之半，故谓之分。"),
        Definition(name: "清明", month: 4, constant: 4.81, text: "三月节，物至此时，皆以洁齐而清明矣。"),
        Definition(name: "谷雨", month: 4, constant: 20.1, text: "三月中，自雨水后，土膏脉动，今又雨其谷于水也。"),
        Definition(name: "立夏", month: 5, constant: 5.52, text: "四月节，立，建始也；夏，假也，物至此时皆假大也。"),
        Definition(name: "小满", month: 5, constant: 21.04, text: "四月中，小满者，物致于此小得盈满。"),
        Definition(name: "芒种", month: 6, constant: 5.678, text: "五月节，谓有芒之种谷可稼种矣。"),
        Definition(name: "夏至", month: 6, constant: 21.37, text: "五月中，夏，假也；至者，极也，万物于此皆假大而至极也。"),
        Definition(name: "小暑", month: 7, constant: 7.108, text: "六月节，暑，热也；就热之中分为大小，月初为小。"),
        Definition(name: "大暑", month: 7, constant: 22.83, text: "六月中，解见小暑。"),
        Definition(name: "立秋", month: 8, constant: 7.5, text: "七月节，秋，揫也，物于此而揫敛也。"),
        Definition(name: "处暑", month: 8, constant: 23.13, text: "七月中，处，止也，暑气至此而止矣。"),
        Definition(name: "白露", month: 9, constant: 7.646, text: "八月节，秋属金，金色白，阴气渐重，露凝而白也。"),
        Definition(name: "秋分", month: 9, constant: 23.042, text: "八月中，分者半也，秋季九十日之半。"),
        Definition(name: "寒露", month: 10, constant: 8.318, text: "九月节，露气寒冷，将凝结也。"),
        Definition(name: "霜降", month: 10, constant: 23.438, text: "九月中，气肃而凝，露结为霜矣。"),
        Definition(name: "立冬", month: 11, constant: 7.438, text: "十月节，立，建始也；冬，终也，万物收藏也。"),
        Definition(name: "小雪", month: 11, constant: 22.36, text: "十月中，雨下而为寒气所薄，故凝而为雪；小者，未盛之辞。"),
        Definition(name: "大雪", month: 12, constant: 7.18, text: "十一月节，大者，盛也，至此而雪盛矣。"),
        Definition(name: "冬至", month: 12, constant: 21.94, text: "十一月中，终藏之气至此而极也。")
    ]

    /// Returns the solar-term greeting when `date` falls on a term day.
    static func greeting(
        on date: Date,
        calendar inputCalendar: Calendar = .current
    ) -> SolarTermGreeting? {
        let calendar = normalizedCalendar(inputCalendar)
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        return terms(in: year, calendar: calendar).first {
            calendar.isDate($0.date, inSameDayAs: day)
        }
    }

    /// Generates all 24 term days for a Gregorian year.
    static func terms(
        in year: Int,
        calendar inputCalendar: Calendar = .current
    ) -> [SolarTermGreeting] {
        guard (1900...2199).contains(year) else { return [] }
        let calendar = normalizedCalendar(inputCalendar)
        let yearWithinCentury = year % 100
        let leapCorrection = floor(Double(yearWithinCentury - 1) / 4.0)

        return definitions.compactMap { definition in
            let day = Int(floor(
                Double(yearWithinCentury) * 0.2422
                    + definition.constant
            ) - leapCorrection)
            guard let date = calendar.date(
                from: DateComponents(year: year, month: definition.month, day: day)
            ) else {
                return nil
            }
            return SolarTermGreeting(name: definition.name, date: date, text: definition.text)
        }
    }

    private static func normalizedCalendar(_ input: Calendar) -> Calendar {
        var calendar = input
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }
}
