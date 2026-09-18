import AppKit
import SwiftUI

private enum AppTheme {
    static let panelBackground = adaptiveColor(
        light: RGB(0xEE, 0xF1, 0xF1),
        dark: RGB(0x25, 0x29, 0x29)
    )
    static let primaryText = adaptiveColor(
        light: RGB(0x47, 0x49, 0x49),
        dark: RGB(0xD8, 0xDD, 0xDD)
    )
    static let titleText = adaptiveColor(
        light: RGB(0x22, 0x23, 0x23),
        dark: RGB(0xF3, 0xF6, 0xF6)
    )
    // 次级说明文字（坐标轴日期、指标名、加载提示）：比正文轻一档，但仍保证可读。
    static let captionText = adaptiveColor(
        light: RGB(0x63, 0x67, 0x67),
        dark: RGB(0x9E, 0xA5, 0xA5)
    )
    static let separator = adaptiveColor(
        light: RGB(0xC8, 0xCE, 0xCE),
        dark: RGB(0x3E, 0x46, 0x46)
    )
    static let statCardBackground = adaptiveColor(
        light: RGB(0x47, 0x49, 0x49, alpha: 0.045),
        dark: RGB(0xFF, 0xFF, 0xFF, alpha: 0.07)
    )
    // 卡片轮廓：比分区线更轻，避免面板上同时出现多条同强度的线。
    static let cardStroke = separator.opacity(0.6)
    // 图标按钮、次级按钮的停留底色：比卡片底色再重一档，作为可点击反馈。
    static let hoverSurface = adaptiveColor(
        light: RGB(0x47, 0x49, 0x49, alpha: 0.08),
        dark: RGB(0xFF, 0xFF, 0xFF, alpha: 0.11)
    )
    // 「今日」数字的强调色：与 Logo 同色系，浅色模式下足够深以保证小字号对比度。
    static let todayAccent = adaptiveColor(
        light: RGB(0x2B, 0x4A, 0xCB),
        dark: RGB(0x82, 0x9E, 0xFF)
    )
    // 主操作按钮沿用强调色；文字色随明暗模式反转，保证两种模式下的对比度。
    static let actionTint = todayAccent
    static let actionTintText = adaptiveColor(
        light: RGB(0xFF, 0xFF, 0xFF),
        dark: RGB(0x12, 0x16, 0x1A)
    )
    // 强调卡片的一点点投影：浅色下提供层次，深色下几乎不可见。
    static let surfaceShadow = adaptiveColor(
        light: RGB(0x1E, 0x22, 0x22, alpha: 0.07),
        dark: RGB(0x00, 0x00, 0x00, alpha: 0.3)
    )
    static let warning = Color.orange
    static let warningSurface = warning.opacity(0.08)
    static let chartEmpty = adaptiveColor(
        light: RGB(0x0A, 0x84, 0xFF),
        dark: RGB(0x4A, 0xA8, 0xFF)
    )
    static let chartFlash = adaptiveColor(
        light: RGB(0x0A, 0x84, 0xFF),
        dark: RGB(0x4A, 0xA8, 0xFF)
    )
    static let chartPro = adaptiveColor(
        light: RGB(0x10, 0xB8, 0xD8),
        dark: RGB(0x46, 0xD6, 0xEA)
    )
    static let chartChatReasoner = adaptiveColor(
        light: RGB(0x5A, 0xC8, 0xFA),
        dark: RGB(0x86, 0xDD, 0xFF)
    )
    static let chartFallbacks: [Color] = [
        adaptiveColor(light: RGB(0x00, 0x7A, 0xCC), dark: RGB(0x48, 0xB5, 0xF0)),
        adaptiveColor(light: RGB(0x32, 0xAD, 0xD8), dark: RGB(0x5E, 0xD2, 0xF1)),
        adaptiveColor(light: RGB(0x46, 0xA0, 0xF5), dark: RGB(0x80, 0xBA, 0xFF)),
        adaptiveColor(light: RGB(0x64, 0xD2, 0xFF), dark: RGB(0x9A, 0xE6, 0xFF))
    ]

    private struct RGB {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat

        init(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1) {
            self.red = CGFloat(red) / 255
            self.green = CGFloat(green) / 255
            self.blue = CGFloat(blue) / 255
            self.alpha = alpha
        }
    }

    private static func adaptiveColor(light: RGB, dark: RGB) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let matchedAppearance = appearance.bestMatch(from: [.darkAqua, .aqua])
            let color = matchedAppearance == .darkAqua ? dark : light
            return NSColor(
                calibratedRed: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha
            )
        })
    }
}

struct PopoverContentView: View {
    private let panelWidth: CGFloat = 318

    @ObservedObject var appState: AppState
    var onLoginRequested: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Separator()
            content
        }
        .frame(width: panelWidth)
        .background(AppTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppGlyph()
                .frame(width: 24, height: 24)
            Text("DeepSeek 用量")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.titleText)
            Spacer(minLength: 0)
            RefreshButton(isLoading: appState.isLoading) {
                appState.refresh()
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 13)
        .padding(.vertical, 10)
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
        AccountCard(
            balance: CurrencyFormatter.cny(snapshot.summary.balanceCNY),
            items: [
                StatStrip.Item(
                    id: "todayTokens",
                    title: "今日用量",
                    value: compactQuantity(snapshot.today?.tokenCount ?? 0),
                    isAccent: true
                ),
                StatStrip.Item(
                    id: "todayCost",
                    title: "今日费用",
                    value: CurrencyFormatter.cny(snapshot.today?.costCNY ?? .zero),
                    isAccent: true
                ),
                StatStrip.Item(
                    id: "monthTokens",
                    title: "本月用量",
                    value: compactQuantity(snapshot.totalTokenCount),
                    isAccent: false
                ),
                StatStrip.Item(
                    id: "monthCost",
                    title: "本月费用",
                    value: CurrencyFormatter.cny(snapshot.summary.monthlyCostCNY),
                    isAccent: false
                )
            ]
        )
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 5)
    }

    private func chartSection(_ snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 9) {
            metricChart(snapshot, title: "费用", metric: .cost)
            metricChart(snapshot, title: "Token", metric: .tokens)
            metricChart(snapshot, title: "请求", metric: .requests)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            Separator()
        }
    }

    private func metricChart(_ snapshot: UsageSnapshot, title: String, metric: UsageMetric) -> some View {
        GroupPanel(title: title) {
            VStack(spacing: 0) {
                BarChart(points: snapshot.dailyPoints, metric: metric)
                chartAxis(for: snapshot.dailyPoints)
                HStack(spacing: 6) {
                    StatItem(title: "日均", value: averageText(metric, snapshot))
                    StatItem(title: "峰值", value: peakText(metric, snapshot))
                    StatItem(title: "活跃", value: "\(snapshot.activeDays)/\(max(snapshot.dailyPoints.count, 1))")
                }
                .padding(.top, 6)
            }
        }
    }

    private func errorSection(_ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if shouldShowLoginButton(for: text) {
                QuietActionButton(title: "登录") { onLoginRequested() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.warningSurface)
        .overlay(alignment: .top) {
            Separator()
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 13) {
            if appState.isLoading {
                StatusBadge(isLoading: true)
                Text("正在加载 DeepSeek 用量...")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.captionText)
            } else {
                StatusBadge(systemName: "person.crop.circle.badge.exclamationmark")
                Text(appState.errorMessage ?? "需要登录 DeepSeek。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryActionButton(title: "登录 DeepSeek") {
                    onLoginRequested()
                }
                .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 26)
        .padding(.vertical, 28)
    }

    private func chartAxis(for points: [DailyUsagePoint]) -> some View {
        let labels = axisLabels(for: points)
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(labels) { label in
                    Text(label.title)
                        .frame(width: axisLabelSlotWidth, alignment: label.alignment)
                        .offset(x: axisLabelOffset(label, total: points.count, width: proxy.size.width))
                }
            }
            .frame(width: proxy.size.width, alignment: .topLeading)
        }
        .frame(height: 12)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(AppTheme.captionText)
        .padding(.top, 4)
    }

    private let axisLabelSlotWidth: CGFloat = 36

    /// 把日期标签对到对应柱子的中心上（首尾贴齐图表左右边缘）。
    private func axisLabelOffset(_ label: ChartAxisLabel, total: Int, width: CGFloat) -> CGFloat {
        guard total > 0, width > axisLabelSlotWidth else { return 0 }
        let center = width * (CGFloat(label.index) + 0.5) / CGFloat(total)
        let proposed = center - axisLabelSlotWidth / 2
        return min(max(proposed, 0), width - axisLabelSlotWidth)
    }

    private func averageText(_ metric: UsageMetric, _ snapshot: UsageSnapshot) -> String {
        switch metric {
        case .cost:
            CurrencyFormatter.cny(snapshot.dailyAverageCostCNY)
        case .tokens:
            compactQuantity(snapshot.dailyAverageTokenCount)
        case .requests:
            NumberFormatter.decimal.string(from: NSNumber(value: snapshot.dailyAverageRequestCount)) ?? "-"
        }
    }

    private func peakText(_ metric: UsageMetric, _ snapshot: UsageSnapshot) -> String {
        switch metric {
        case .cost:
            CurrencyFormatter.cny(snapshot.peakCostCNY)
        case .tokens:
            compactQuantity(snapshot.peakTokenCount)
        case .requests:
            NumberFormatter.decimal.string(from: NSNumber(value: snapshot.peakRequestCount)) ?? "-"
        }
    }

    private func compactQuantity(_ value: Int64) -> String {
        let doubleValue = Double(value)
        let absValue = abs(doubleValue)
        if absValue >= 1_000_000 {
            return "\(compactDecimal(doubleValue / 1_000_000))M"
        }
        if absValue >= 1_000 {
            return "\(compactDecimal(doubleValue / 1_000))K"
        }
        return "\(value)"
    }

    private func compactDecimal(_ number: Double) -> String {
        if number == number.rounded() {
            return String(format: "%.0f", number)
        }
        let truncated = (number * 10).rounded(.down) / 10
        return String(format: "%.1f", truncated)
    }

    private func axisLabels(for points: [DailyUsagePoint]) -> [ChartAxisLabel] {
        guard !points.isEmpty else { return [] }
        guard points.count > 1 else {
            return [
                ChartAxisLabel(index: 0, title: DateFormatter.shortMonthDay.string(from: points[0].date), alignment: .center)
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

private struct Separator: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.separator)
            .frame(height: 1)
    }
}

/// 行内竖分隔线：用于同一行里分组的两个数据。
private struct VerticalRule: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.cardStroke)
            .frame(width: 1, height: 15)
    }
}

/// 按下时轻微回弹，让无边框按钮也有触感。
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 主操作按钮（登录）：实心强调色 + 悬停提亮。
private struct PrimaryActionButton: View {
    var title: String
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.actionTintText)
                .padding(.horizontal, 14)
                .frame(height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.actionTint)
                )
                .brightness(isHovering ? 0.05 : 0)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
    }
}

/// 次级按钮（错误条上的登录）：描边 + 悬停底色，不与主按钮抢视线。
private struct QuietActionButton: View {
    var title: String
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? AppTheme.hoverSurface : AppTheme.statCardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
    }
}

/// 头部刷新按钮：悬停底色 + 刷新中持续旋转。
/// 用 TimelineView(.animation) 驱动旋转而非 repeatForever：
/// repeatForever 在状态归 false 后可能停不干净（已知 SwiftUI 问题），
/// TimelineView 随 isLoading 切换视图树，加载结束动画必然终止。
private struct RefreshButton: View {
    var isLoading: Bool
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            refreshIcon
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.hoverSurface)
                        .opacity(isHovering && !isLoading ? 1 : 0)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .disabled(isLoading)
        .help("刷新")
    }

    @ViewBuilder
    private var refreshIcon: some View {
        if isLoading {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                    .rotationEffect(
                        .degrees(
                            (context.date.timeIntervalSinceReferenceDate * 375)
                                .truncatingRemainder(dividingBy: 360)
                        )
                    )
            }
        } else {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText.opacity(0.85))
        }
    }
}

/// 空态/加载态的圆形图标位：两种状态共用同一尺寸，切换时不跳动。
private struct StatusBadge: View {
    var systemName: String? = nil
    var isLoading = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.statCardBackground)
            Circle()
                .strokeBorder(AppTheme.cardStroke, lineWidth: 1)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 19))
                    .foregroundStyle(AppTheme.primaryText.opacity(0.72))
            }
        }
        .frame(width: 46, height: 46)
    }
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
    var compact = false

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
        .frame(minHeight: compact ? 24 : 32)
        .contentShape(Rectangle())
    }
}

/// 账户区整卡：上半是余额（左标签 + 右侧大字），下半是四联统计行。
/// 余额收进统计卡片里、与统计共用同一块底色/描边/投影，账户区读起来就是「一块」信息，
/// 而不是「一行余额 + 一张统计卡」；余额靠字号（18pt）当视觉锚点，
/// 中线用与竖分隔线同一手法的两端渐隐细线分区，避免横竖两条线在卡片里抢戏。
private struct AccountCard: View {
    var balance: String
    var items: [StatStrip.Item]

    var body: some View {
        VStack(spacing: 0) {
            balanceRow
            divider
            StatStrip(items: items)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.statCardBackground)
                .shadow(color: AppTheme.surfaceShadow, radius: 2.5, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        )
    }

    /// 余额行的左右内边距与下面统计项的取值保持一致，三处文字共用一条左对齐基线。
    private var balanceRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("账户余额")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.captionText)
            Spacer(minLength: 8)
            Text(balance)
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(AppTheme.titleText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: balance)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 7)
    }

    private var divider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.cardStroke.opacity(0),
                        AppTheme.cardStroke,
                        AppTheme.cardStroke.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

/// StatStrip：账户卡下半部分的四联统计行，四个指标等宽并排 + 三条渐隐竖分隔线。
/// 「今日」两项用强调色、「本月」两项用正文色，靠颜色而非字号区分两组归属，
/// 这样四项共享同一字号（14pt），一行放得下且不打架。
/// 卡片底色/描边/投影由外层 AccountCard 统一提供，这里只负责排内容。
private struct StatStrip: View {
    struct Item: Identifiable {
        var id: String
        var title: String
        var value: String
        var isAccent: Bool
    }

    var items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    divider
                }
                stat(item)
            }
        }
        .padding(.vertical, 6)
    }

    /// 分隔线用上下渐隐的细线，比硬邦邦的一刀更有层次；高度撑满内容区但不顶到卡片边缘。
    private var divider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.cardStroke.opacity(0),
                        AppTheme.cardStroke,
                        AppTheme.cardStroke.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private func stat(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.captionText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(item.value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(item.isAccent ? AppTheme.todayAccent : AppTheme.titleText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: item.value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
}

struct GroupPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.cardStroke, lineWidth: 1)
        )
        .padding(.top, 7)
        .overlay(alignment: .topLeading) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.titleText)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(AppTheme.panelBackground)
                .padding(.leading, 12)
        }
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
    var barHeight: CGFloat = 68

    var body: some View {
        let values = points.map { $0.value(for: metric) }
        let maxValue = max(values.max() ?? 0, 0.0001)

        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                StackedBar(point: point, metric: metric, maxValue: maxValue, barHeight: barHeight)
                    .frame(maxWidth: .infinity)
                    .animation(.easeOut(duration: 0.25).delay(Double(index) * 0.005), value: points)
            }
        }
        .frame(height: barHeight, alignment: .bottom)
    }
}

private struct StackedBar: View {
    var point: DailyUsagePoint
    var metric: UsageMetric
    var maxValue: Double
    var barHeight: CGFloat

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
        .frame(height: totalValue > 0 ? max(2, barHeight * CGFloat(totalValue / maxValue)) : 2, alignment: .bottom)
    }

    private func segmentHeight(for value: Double) -> CGFloat {
        guard point.value(for: metric) > 0 else { return 0 }
        return max(1, barHeight * CGFloat(value / maxValue))
    }
}

private enum BarPalette {
    static let empty = AppTheme.chartEmpty

    static func color(for model: String) -> Color {
        switch model {
        case "deepseek-v4-flash":
            AppTheme.chartFlash
        case "deepseek-v4-pro":
            AppTheme.chartPro
        case "deepseek-chat & deepseek-reasoner":
            AppTheme.chartChatReasoner
        default:
            AppTheme.chartFallbacks[stableColorIndex(for: model)]
        }
    }

    private static func stableColorIndex(for model: String) -> Int {
        let value = model.unicodeScalars.reduce(0) { partial, scalar in
            partial &+ Int(scalar.value)
        }
        return abs(value) % AppTheme.chartFallbacks.count
    }
}

struct StatItem: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppTheme.captionText)
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(AppTheme.statCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.cardStroke, lineWidth: 1)
        )
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
