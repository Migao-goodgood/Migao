import SwiftUI

struct InBodyHistorySection: View {
    let snapshots: [InBodySnapshot]
    let latestSnapshotID: UUID?
    let comparisonFor: (InBodySnapshot) -> InBodyComparisonResult?
    let onSelect: (InBodySnapshot) -> Void
    var weightUnit: WeightUnit = .kilograms

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                Text("历史记录")
                    .roundedFont(19, weight: .heavy)
                    .foregroundStyle(BodyEditorial.ink)
                Spacer()
                Text("共 \(snapshots.count) 次测量")
                    .roundedFont(10, weight: .medium)
                    .foregroundStyle(BodyEditorial.muted)
            }

            VStack(spacing: 0) {
                ForEach(Array(snapshots.reversed())) { snapshot in
                    Button {
                        onSelect(snapshot)
                    } label: {
                        InBodyHistoryRow(
                            snapshot: snapshot,
                            comparison: comparisonFor(snapshot),
                            isLatest: snapshot.id == latestSnapshotID,
                            weightUnit: weightUnit
                        )
                    }
                    .buttonStyle(.plain)

                    if snapshot.id != snapshots.first?.id {
                        Rectangle()
                            .fill(BodyEditorial.rule)
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 13)
            .background(BodyEditorial.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BodyEditorial.rule, lineWidth: 1)
            }
        }
    }
}

private struct InBodyHistoryRow: View {
    let snapshot: InBodySnapshot
    let comparison: InBodyComparisonResult?
    let isLatest: Bool
    var weightUnit: WeightUnit = .kilograms

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(dayText)
                    .roundedFont(20, weight: .heavy)
                    .foregroundStyle(BodyEditorial.ink)
                Text(monthText)
                    .roundedFont(9, weight: .bold)
                    .foregroundStyle(BodyEditorial.muted)
            }
            .frame(width: 38)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(snapshot.weightKg.map { weightUnit.formatted(fromKilograms: $0) } ?? "--")
                        .roundedFont(14, weight: .heavy)
                        .foregroundStyle(BodyEditorial.ink)
                    if isLatest {
                        Text("最新")
                            .roundedFont(8, weight: .bold)
                            .foregroundStyle(BodyEditorial.ink)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(BodyEditorial.blueWash, in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    Text("体脂 \(value(snapshot.bodyFatPercentage, suffix: "%"))")
                    Text("肌肉 \(value(snapshot.skeletalMuscleKg, suffix: "kg"))")
                }
                .roundedFont(9, weight: .medium)
                .foregroundStyle(BodyEditorial.muted)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 5) {
                Text(weightChange)
                    .roundedFont(10, weight: .bold)
                    .foregroundStyle(BodyEditorial.blue)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BodyEditorial.muted)
            }
        }
        .frame(minHeight: 70)
        .contentShape(Rectangle())
    }

    private var weightChange: String {
        guard let delta = comparison?.delta(for: .weight) else { return "首份记录" }
        if delta.direction == .stable { return "体重持平" }
        return "\(delta.absoluteChange > 0 ? "↑" : "↓") \(weightUnit.formatted(fromKilograms: abs(delta.absoluteChange)))"
    }

    private var dayText: String {
        String(Calendar.current.component(.day, from: snapshot.date))
    }

    private var monthText: String {
        "\(Calendar.current.component(.month, from: snapshot.date))月"
    }

    private func value(_ number: Double?, suffix: String) -> String {
        guard let number else { return "--" }
        return suffix == "%"
            ? String(format: "%.1f%%", number)
            : String(format: "%.1f %@", number, suffix)
    }
}

struct InBodyHistoryDetailSheet: View {
    let snapshot: InBodySnapshot
    let comparison: InBodyComparisonResult?
    let onDelete: () -> Void
    var weightUnit: WeightUnit = .kilograms
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(InBodyFormatters.measurementDate.string(from: snapshot.date))
                                .roundedFont(22, weight: .heavy)
                                .foregroundStyle(BodyEditorial.ink)
                            Text(snapshot.source.title)
                                .roundedFont(10, weight: .medium)
                                .foregroundStyle(BodyEditorial.muted)
                        }
                        Spacer()
                        if let score = snapshot.score {
                            VStack(spacing: 2) {
                                Text(String(format: "%.0f", score))
                                    .roundedFont(22, weight: .heavy)
                                Text("评分")
                                    .roundedFont(8, weight: .bold)
                            }
                            .foregroundStyle(BodyEditorial.ink)
                            .frame(width: 58, height: 58)
                            .background(BodyEditorial.blueWash, in: Circle())
                        }
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(InBodyMetric.coreTrendMetrics) { metric in
                            CoreMetricCard(
                                metric: metric,
                                currentValue: metric.value(in: snapshot),
                                delta: comparison?.delta(for: metric),
                                weightUnit: weightUnit
                            )
                        }
                    }

                    VStack(spacing: 0) {
                        detailRow("身高", value: snapshot.heightCm.map { String(format: "%.1f cm", $0) })
                        detailRow("年龄", value: snapshot.age.map { "\($0) 岁" })
                        detailRow("性别", value: snapshot.sex)
                        detailRow("设备型号", value: snapshot.deviceModel)
                        detailRow("BMI", value: snapshot.bmi.map { String(format: "%.1f", $0) })
                        detailRow("内脏脂肪等级", value: snapshot.visceralFatLevel.map { String(format: "%.1f", $0) })
                        detailRow("腰臀比", value: snapshot.waistHipRatio.map { String(format: "%.2f", $0) })
                        detailRow("总体水分", value: snapshot.totalBodyWaterL.map { String(format: "%.1f L", $0) })
                        detailRow("蛋白质", value: snapshot.proteinKg.map { String(format: "%.1f kg", $0) })
                        detailRow("矿物质", value: snapshot.mineralKg.map { String(format: "%.2f kg", $0) })
                        detailRow("去脂体重", value: snapshot.fatFreeMassKg.map { String(format: "%.1f kg", $0) })
                        detailRow("身体细胞量", value: snapshot.bodyCellMassKg.map { String(format: "%.1f kg", $0) })
                        detailRow("基础代谢", value: snapshot.basalMetabolicRate.map { String(format: "%.0f kcal", $0) })
                        detailRow("SMI", value: snapshot.smiKgPerM2.map { String(format: "%.1f kg/m²", $0) })
                    }
                    .padding(.horizontal, 14)
                    .background(BodyEditorial.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(BodyEditorial.rule, lineWidth: 1)
                    }

                    if !snapshot.note.isEmpty {
                        Text(snapshot.note)
                            .roundedFont(11, weight: .medium)
                            .foregroundStyle(BodyEditorial.ink)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BodyEditorial.blushWash.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(18)
            }
            .background(BodyEditorial.paper.ignoresSafeArea())
            .navigationTitle("测量详情")
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("删除这次测量")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog(
                "删除这次测量？",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后，这次数据将不再参与趋势和身体变化分析。")
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ title: String, value: String?) -> some View {
        HStack {
            Text(title)
                .roundedFont(11, weight: .medium)
                .foregroundStyle(BodyEditorial.muted)
            Spacer()
            Text(value ?? "--")
                .roundedFont(12, weight: .bold)
                .foregroundStyle(BodyEditorial.ink)
        }
        .frame(minHeight: 42)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BodyEditorial.rule).frame(height: 1)
        }
    }
}
