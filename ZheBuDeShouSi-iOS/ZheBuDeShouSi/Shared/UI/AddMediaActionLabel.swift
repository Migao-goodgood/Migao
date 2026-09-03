import SwiftUI

/// Shared compact label for photo-backed add actions.
///
/// Feature views own the actual button or PhotosPicker interaction and supply
/// their palette. Keeping the visual label interaction-free lets Diet and
/// BodyTrend share one shape without coupling their state or workflows.
struct AddMediaActionLabel: View {
    let systemName: String
    let foregroundColor: Color
    let surfaceColor: Color
    let badgeColor: Color
    let borderColor: Color
    var showsBadge = true

    var body: some View {
        ZStack {
            Circle()
                .fill(surfaceColor)
                .frame(width: 50, height: 50)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                }

            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .offset(x: showsBadge ? -2 : 0, y: showsBadge ? -1 : 0)

            if showsBadge {
                ZStack {
                    Circle()
                        .fill(badgeColor)
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)
                .overlay {
                    Circle()
                        .stroke(borderColor, lineWidth: 2.5)
                }
                .offset(x: 18, y: 18)
            }
        }
        .frame(width: 58, height: 58)
        .contentShape(Rectangle())
        .shadow(color: badgeColor.opacity(0.18), radius: 9, y: 4)
    }
}
