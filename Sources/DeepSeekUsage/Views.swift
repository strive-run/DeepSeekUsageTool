import SwiftUI

private enum AppTheme {
    static let panelBackground = Color(red: 0xEE / 255, green: 0xF1 / 255, blue: 0xF1 / 255)
    static let primaryText = Color(red: 0x47 / 255, green: 0x49 / 255, blue: 0x49 / 255)
    static let titleText = Color(red: 0x22 / 255, green: 0x23 / 255, blue: 0x23 / 255)
}

struct PopoverContentView: View {
    private let panelWidth: CGFloat = 318

    @ObservedObject var appState: AppState
    var onLoginRequested: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            content
        }
        .frame(width: panelWidth)
        .background(AppTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppGlyph()
                .frame(width: 26, height: 26)
            Text("DeepSeek 用量")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.titleText)
            Spacer()
            Button {
                appState.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.primaryText.opacity(0.82))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("刷新")
            .disabled(appState.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = appState.snapshot {
            snapshotContent(snapshot)
        } else {
            emptyContent
        }
    }

    private func snapshotContent(_ snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 0) {
            accountSection(snapshot)
            chartSection(snapshot)
            if let error = appState.errorMessage {
                errorSection(error)
            }
        }
    }

    private func accountSection(_ snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 0) {
            InfoRow(
                title: "账户余额",
                value: CurrencyFormatter.cny(snapshot.summary.balanceCNY)
            )
            InfoRow(
                title: "今日用量",
                value: CurrencyFormatter.cny(snapshot.today?.costCNY ?? .zero)
            )
            InfoRow(
                title: "本月费用",
                value: CurrencyFormatter.cny(snapshot.summary.monthlyCostCNY)
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    private func chartSection(_ snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 0) {
            MetricPicker(selected: $appState.selectedMetric)
                .padding(.top, 8)
                .padding(.bottom, 5)
            BarChart(points: snapshot.dailyPoints, metric: appState.selectedMetric)
                .frame(height: 78)
            chartAxis(for: snapshot.dailyPoints)
            HStack(spacing: 8) {
                StatItem(title: "日均", value: averageText(for: snapshot))
                StatItem(title: "峰值", value: peakText(for: snapshot))
                StatItem(title: "活跃天数", value: "\(snapshot.activeDays)/\(max(snapshot.dailyPoints.count, 1))")
            }
            .padding(.top, 7)
            .padding(.bottom, 11)
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }

    private func errorSection(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(2)
            Spacer()
            if shouldShowLoginButton(for: text) {
                Button("登录") { onLoginRequested() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.primaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            if appState.isLoading {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载 DeepSeek 用量...")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.primaryText.opacity(0.78))
            } else {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.primaryText.opacity(0.65))
                Text(appState.errorMessage ?? "需要登录 DeepSeek。")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.primaryText)
                Button("登录 DeepSeek") {
                    onLoginRequested()
                }
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.primaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 16)
    }

    private func chartAxis(for points: [DailyUsagePoint]) -> some View {
        HStack {
            ForEach(axisLabels(for: points)) { label in
                Text(label.title)
                    .frame(maxWidth: .infinity, alignment: label.alignment)
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(AppTheme.primaryText.opacity(0.58))
        .padding(.top, 4)
    }

    private func averageText(for snapshot: UsageSnapshot) -> String {
        switch appState.selectedMetric {
        case .cost:
            CurrencyFormatter.cny(snapshot.dailyAverageCostCNY)
        case .tokens:
            NumberFormatter.decimal.string(from: NSNumber(value: snapshot.dailyAverageTokenCount)) ?? "-"
        case .requests:
            NumberFormatter.decimal.string(from: NSNumber(value: snapshot.dailyAverageRequestCount)) ?? "-"
        }
    }

    private func peakText(for snapshot: UsageSnapshot) -> String {
        switch appState.selectedMetric {
        case .cost:
            CurrencyFormatter.cny(snapshot.peakCostCNY)
        case .tokens:
            NumberFormatter.decimal.string(from: NSNumber(value: snapshot.peakTokenCount)) ?? "-"
        case .requests:
            NumberFormatter.decimal.string(from: NSNumber(value: snapshot.peakRequestCount)) ?? "-"
        }
    }

    private func axisLabels(for points: [DailyUsagePoint]) -> [ChartAxisLabel] {
        guard !points.isEmpty else { return [] }
        guard points.count > 1 else {
            return [
                ChartAxisLabel(index: 0, title: DateFormatter.shortMonthDay.string(from: points[0].date), alignment: .leading)
            ]
        }

        let candidateIndices = [0, points.count / 3, (points.count * 2) / 3, points.count - 1]
        let uniqueIndices = candidateIndices.reduce(into: [Int]()) { result, index in
            guard !result.contains(index) else { return }
            result.append(index)
        }

        return uniqueIndices.map { index in
            let alignment: Alignment = if index == 0 {
                .leading
            } else if index == points.count - 1 {
                .trailing
            } else {
                .center
            }
            return ChartAxisLabel(
                index: index,
                title: DateFormatter.shortMonthDay.string(from: points[index].date),
                alignment: alignment
            )
        }
    }

    private func shouldShowLoginButton(for text: String) -> Bool {
        text.localizedCaseInsensitiveContains("login")
            || text.contains("登录")
            || text.contains("失效")
            || text.contains("凭据")
    }
}

private struct ChartAxisLabel: Identifiable {
    var index: Int
    var title: String
    var alignment: Alignment

    var id: Int { index }
}

struct AppGlyph: View {
    var body: some View {
        DeepSeekLogoShape()
            .fill(Color(red: 0x4D / 255, green: 0x6B / 255, blue: 0xFE / 255))
            .aspectRatio(1, contentMode: .fit)
    }
}

struct DeepSeekLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(DeepSeekLogoPath.makePath(in: rect))
    }
}

struct SectionHeader: View {
    var title: String
    var trailing: String?

    init(title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.titleText)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.primaryText)
            }
        }
        .padding(.top, 7)
        .padding(.bottom, 5)
    }
}

struct InfoRow: View {
    var title: String
    var value: String
    var showsDot = false

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                if showsDot {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: .green.opacity(0.4), radius: 3)
                }
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.primaryText)
            }
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(AppTheme.primaryText)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }
}

struct MetricPicker: View {
    @Binding var selected: UsageMetric

    var body: some View {
        Picker("", selection: $selected) {
            ForEach(UsageMetric.allCases) { metric in
                Text(metric.title).tag(metric)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
    }
}

struct BarChart: View {
    var points: [DailyUsagePoint]
    var metric: UsageMetric

    var body: some View {
        let values = points.map { $0.value(for: metric) }
        let maxValue = max(values.max() ?? 0, 0.0001)

        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                StackedBar(point: point, metric: metric, maxValue: maxValue)
                    .frame(maxWidth: .infinity)
                    .animation(.easeOut(duration: 0.25).delay(Double(index) * 0.005), value: points)
            }
        }
        .frame(height: 74, alignment: .bottom)
    }
}

private struct StackedBar: View {
    var point: DailyUsagePoint
    var metric: UsageMetric
    var maxValue: Double

    var body: some View {
        let visibleModels = point.visibleModels(for: metric)
        let totalValue = point.value(for: metric)

        VStack(spacing: 0) {
            if visibleModels.isEmpty {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(BarPalette.empty)
                    .opacity(0.12)
                    .frame(height: 2)
            } else {
                ForEach(visibleModels.reversed()) { model in
                    Rectangle()
                        .fill(BarPalette.color(for: model.model))
                        .frame(height: segmentHeight(for: model.value(for: metric)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .frame(height: totalValue > 0 ? max(2, 68 * CGFloat(totalValue / maxValue)) : 2, alignment: .bottom)
    }

    private func segmentHeight(for value: Double) -> CGFloat {
        guard point.value(for: metric) > 0 else { return 0 }
        return max(1, 68 * CGFloat(value / maxValue))
    }
}

private enum BarPalette {
    static let empty = Color.blue

    static func color(for model: String) -> Color {
        switch model {
        case "deepseek-v4-flash":
            Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
        case "deepseek-v4-pro":
            Color(red: 0x10 / 255, green: 0xB8 / 255, blue: 0xD8 / 255)
        case "deepseek-chat & deepseek-reasoner":
            Color(red: 0x5A / 255, green: 0xC8 / 255, blue: 0xFA / 255)
        default:
            fallbackColors[stableColorIndex(for: model)]
        }
    }

    private static func stableColorIndex(for model: String) -> Int {
        let value = model.unicodeScalars.reduce(0) { partial, scalar in
            partial &+ Int(scalar.value)
        }
        return abs(value) % fallbackColors.count
    }

    private static let fallbackColors: [Color] = [
        Color(red: 0x00 / 255, green: 0x7A / 255, blue: 0xCC / 255),
        Color(red: 0x32 / 255, green: 0xAD / 255, blue: 0xD8 / 255),
        Color(red: 0x46 / 255, green: 0xA0 / 255, blue: 0xF5 / 255),
        Color(red: 0x64 / 255, green: 0xD2 / 255, blue: 0xFF / 255)
    ]
}

struct StatItem: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppTheme.primaryText.opacity(0.6))
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(AppTheme.primaryText.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

enum CurrencyFormatter {
    static func cny(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.currencySymbol = "¥"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "¥0.00"
    }
}

extension NumberFormatter {
    static var compact: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 1
        return formatter
    }

    static var decimal: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter
    }
}

extension DateFormatter {
    static var shortMonthDay: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M.d"
        return formatter
    }

    static var updateTime: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    static var updateDateTime: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }
}
