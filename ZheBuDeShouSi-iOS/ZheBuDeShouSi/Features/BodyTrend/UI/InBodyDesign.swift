import Foundation
import SwiftUI

enum BodyEditorial {
    static let paper = Color(hex: "F7F7F9")
    static let surface = Color.white.opacity(0.98)
    static let ink = Color(hex: "1D1D1F")
    static let muted = Color(hex: "8E8E93")
    static let blue = Color.waterAccent
    static let blueWash = Color.waterAccentPale
    static let sage = Color.mintGreen
    static let sageWash = Color.mintPale
    static let blush = Color(hex: "D98282")
    static let blushWash = Color(hex: "F8ECEC")
    static let gold = Color(hex: "B19156")
    static let rule = Color(hex: "E5E5EA")
}

enum InBodyFormatters {
    static let measurementDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}
