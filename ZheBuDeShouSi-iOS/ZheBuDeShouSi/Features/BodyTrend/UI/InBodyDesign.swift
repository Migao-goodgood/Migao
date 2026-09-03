import Foundation
import SwiftUI

enum BodyEditorial {
    static let paper = Color(hex: "FFF8FC")
    static let surface = Color.white.opacity(0.9)
    static let ink = Color(hex: "342D3A")
    static let muted = Color(hex: "857784")
    static let blue = Color(hex: "76BCCE")
    static let blueWash = Color(hex: "E7F5F8")
    static let sage = Color(hex: "79B69D")
    static let sageWash = Color(hex: "EAF5EF")
    static let blush = Color(hex: "E18EAC")
    static let blushWash = Color(hex: "FBE8F0")
    static let gold = Color(hex: "C5A057")
    static let rule = Color(hex: "EADDE5")
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
