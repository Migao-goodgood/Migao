import SwiftUI

enum JournalTypography {
    static let pageTitle: CGFloat = 28
    static let sectionTitle: CGFloat = 18
    static let metric: CGFloat = 24
    static let metricSmall: CGFloat = 16
    static let body: CGFloat = 14
    static let secondary: CGFloat = 12
    static let caption: CGFloat = 11
    static let micro: CGFloat = 10

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    func journalPageTitle() -> some View { font(JournalTypography.font(JournalTypography.pageTitle, weight: .semibold)) }
    func journalSectionTitle() -> some View { font(JournalTypography.font(JournalTypography.sectionTitle, weight: .semibold)) }
    func journalMetric() -> some View { font(JournalTypography.font(JournalTypography.metric, weight: .semibold)).monospacedDigit() }
    func journalMetricSmall() -> some View { font(JournalTypography.font(JournalTypography.metricSmall, weight: .semibold)).monospacedDigit() }
    func journalBody() -> some View { font(JournalTypography.font(JournalTypography.body)) }
    func journalSecondary() -> some View { font(JournalTypography.font(JournalTypography.secondary)) }
    func journalCaption() -> some View { font(JournalTypography.font(JournalTypography.caption, weight: .medium)) }
    func journalMicro() -> some View { font(JournalTypography.font(JournalTypography.micro, weight: .medium)) }
}

/// Shared page-level rhythm for the first three journal surfaces.
enum JournalPageLayout {
    static let horizontalPadding: CGFloat = 16
    static let topPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 16
    static let headerSpacing: CGFloat = 12
    static let headerActionSize: CGFloat = 58
    static let titleSize: CGFloat = 29
    static let pageBackground = Color.platinumPale
}

/// Keeps the home, diet, and body-data page headers on the same visual grid.
/// The action remains generic because Diet and Home use a button while the
/// body-data page wraps its action in PhotosPicker. Optional title details
/// (such as the home's solar-term note) stay in the same title column.
struct JournalPageHeader<Action: View, Details: View>: View {
    let title: String
    let titleColor: Color
    private let details: () -> Details
    private let action: () -> Action

    init(
        title: String,
        titleColor: Color,
        @ViewBuilder details: @escaping () -> Details,
        @ViewBuilder action: @escaping () -> Action
    ) {
        self.title = title
        self.titleColor = titleColor
        self.details = details
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: JournalPageLayout.headerSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .journalPageTitle()
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                    .accessibilityHeading(.h1)
                details()
            }

            Spacer(minLength: JournalPageLayout.headerSpacing)
            action()
                .frame(
                    width: JournalPageLayout.headerActionSize,
                    height: JournalPageLayout.headerActionSize,
                    alignment: .top
                )
        }
        .frame(maxWidth: .infinity, minHeight: JournalPageLayout.headerActionSize, alignment: .top)
    }
}

extension JournalPageHeader where Details == EmptyView {
    init(
        title: String,
        titleColor: Color,
        @ViewBuilder action: @escaping () -> Action
    ) {
        self.init(title: title, titleColor: titleColor, details: { EmptyView() }, action: action)
    }
}

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

/// Shared top-right action used by the diet and weight journals. The feature
/// supplies its icon and colors, while shape, badge placement, hit area, and
/// accessibility behavior stay identical.
struct JournalAddActionButton: View {
    let systemName: String
    let foregroundColor: Color
    let surfaceColor: Color
    let badgeColor: Color
    let borderColor: Color
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AddMediaActionLabel(
                systemName: systemName,
                foregroundColor: foregroundColor,
                surfaceColor: surfaceColor,
                badgeColor: badgeColor,
                borderColor: borderColor
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
