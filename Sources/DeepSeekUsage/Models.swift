import Foundation

enum UsageMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case cost
    case tokens
    case requests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cost: "费用"
        case .tokens: "Token"
        case .requests: "请求"
        }
    }
}

struct WalletSummary: Codable, Equatable, Sendable {
    var balanceCNY: Decimal
    var bonusCNY: Decimal
    var monthlyCostCNY: Decimal
    var monthlyTokenUsage: Int64
    var totalAvailableTokenEstimation: Int64
    var currentToken: Int64
}

struct DailyUsagePoint: Codable, Identifiable, Equatable, Sendable {
    var date: Date
    var costCNY: Decimal
    var tokenCount: Int64
    var requestCount: Int64
    var models: [DailyModelUsageBreakdown] = []

    var id: Date { date }

    func value(for metric: UsageMetric) -> Double {
        switch metric {
        case .cost:
            NSDecimalNumber(decimal: costCNY).doubleValue
        case .tokens:
            Double(tokenCount)
        case .requests:
            Double(requestCount)
        }
    }

    func visibleModels(for metric: UsageMetric) -> [DailyModelUsageBreakdown] {
        models.filter { $0.value(for: metric) > 0 }
    }
}

struct DailyModelUsageBreakdown: Codable, Identifiable, Equatable, Sendable {
    var model: String
    var costCNY: Decimal
    var tokenCount: Int64
    var requestCount: Int64

    var id: String { model }

    func value(for metric: UsageMetric) -> Double {
        switch metric {
        case .cost:
            NSDecimalNumber(decimal: costCNY).doubleValue
        case .tokens:
            Double(tokenCount)
        case .requests:
            Double(requestCount)
        }
    }
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    var summary: WalletSummary
    var dailyPoints: [DailyUsagePoint]
    var lastUpdated: Date

    var today: DailyUsagePoint? {
        let calendar = Calendar(identifier: .gregorian)
        return dailyPoints.last { calendar.isDate($0.date, inSameDayAs: lastUpdated) }
    }

    var totalCostCNY: Decimal {
        dailyPoints.reduce(Decimal.zero) { $0 + $1.costCNY }
    }

    var totalTokenCount: Int64 {
        dailyPoints.reduce(Int64.zero) { $0 + $1.tokenCount }
    }

    var totalRequestCount: Int64 {
        dailyPoints.reduce(Int64.zero) { $0 + $1.requestCount }
    }

    var dailyAverageCostCNY: Decimal {
        guard !dailyPoints.isEmpty else { return .zero }
        return totalCostCNY / Decimal(dailyPoints.count)
    }

    var dailyAverageTokenCount: Int64 {
        guard !dailyPoints.isEmpty else { return 0 }
        return totalTokenCount / Int64(dailyPoints.count)
    }

    var dailyAverageRequestCount: Int64 {
        guard !dailyPoints.isEmpty else { return 0 }
        return totalRequestCount / Int64(dailyPoints.count)
    }

    var peakCostCNY: Decimal {
        dailyPoints.map(\.costCNY).max() ?? .zero
    }

    var peakTokenCount: Int64 {
        dailyPoints.map(\.tokenCount).max() ?? 0
    }

    var peakRequestCount: Int64 {
        dailyPoints.map(\.requestCount).max() ?? 0
    }

    var activeDays: Int {
        dailyPoints.filter { $0.costCNY > .zero || $0.tokenCount > 0 || $0.requestCount > 0 }.count
    }
}

struct APIEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    var code: Int
    var msg: String
    var data: APIBusinessEnvelope<Payload>
}

struct APIBusinessEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    var bizCode: Int
    var bizMsg: String
    var bizData: Payload

    enum CodingKeys: String, CodingKey {
        case bizCode = "biz_code"
        case bizMsg = "biz_msg"
        case bizData = "biz_data"
    }
}

struct UserSummaryPayload: Decodable, Sendable {
    var normalWallets: [WalletPayload]
    var bonusWallets: [WalletPayload]
    var totalCosts: [CostPayload]
    var currentToken: Int64?
    var monthlyTokenUsage: String?
    var totalAvailableTokenEstimation: String?

    enum CodingKeys: String, CodingKey {
        case normalWallets = "normal_wallets"
        case bonusWallets = "bonus_wallets"
        case totalCosts = "total_costs"
        case currentToken = "current_token"
        case monthlyTokenUsage = "monthly_token_usage"
        case totalAvailableTokenEstimation = "total_available_token_estimation"
    }
}

struct WalletPayload: Decodable, Sendable {
    var currency: String
    var balance: String
    var tokenEstimation: String

    enum CodingKeys: String, CodingKey {
        case currency
        case balance
        case tokenEstimation = "token_estimation"
    }
}

struct CostPayload: Decodable, Sendable {
    var currency: String
    var amount: String
}

struct UsageAmountPayload: Decodable, Sendable {
    var total: [ModelUsagePayload]
    var days: [DailyModelUsagePayload]
}

struct UsageCostPayload: Decodable, Sendable {
    var currency: String?
    var total: [ModelUsagePayload]
    var days: [DailyModelUsagePayload]
}

struct DailyModelUsagePayload: Decodable, Sendable {
    var date: String
    var data: [ModelUsagePayload]
}

struct ModelUsagePayload: Decodable, Sendable {
    var model: String
    var usage: [UsageValuePayload]
}

struct UsageValuePayload: Decodable, Sendable {
    var type: String
    var amount: String
}

// MARK: - by_api_key 用量接口（当前 DeepSeek 平台前端首选）

struct UsageByApiKeyAmountPayload: Decodable, Sendable {
    var start: Int64
    var end: Int64
    var bucket: Int64
    var models: [String]
    var series: [UsageByApiKeySeriesPayload]
}

struct UsageByApiKeyCostPayload: Decodable, Sendable {
    var start: Int64
    var end: Int64
    var bucket: Int64
    var models: [String]
    var data: [UsageCostCurrencySeriesPayload]
}

struct UsageCostCurrencySeriesPayload: Decodable, Sendable {
    var currency: String
    var series: [UsageByApiKeySeriesPayload]
}

struct UsageByApiKeySeriesPayload: Decodable, Sendable {
    var apiKey: ApiKeyInfoPayload
    var model: String
    var buckets: [UsageByApiKeyBucketPayload]

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case model
        case buckets
    }
}

struct ApiKeyInfoPayload: Decodable, Sendable {
    var trackingId: String
    var name: String
    var sensitiveId: String
    var valid: Bool
    var keyType: String

    enum CodingKeys: String, CodingKey {
        case trackingId = "tracking_id"
        case name
        case sensitiveId = "sensitive_id"
        case valid
        case keyType = "key_type"
    }
}

struct UsageByApiKeyBucketPayload: Decodable, Sendable {
    var time: Int64
    var usage: [String: Int64]?
    var cost: String?
}

enum DeepSeekError: LocalizedError, Equatable, Sendable {
    case unauthorized
    case invalidURL
    case httpStatus(Int)
    case businessError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "DeepSeek 登录已失效。"
        case .invalidURL:
            "DeepSeek 地址无效。"
        case .httpStatus(let status):
            "DeepSeek 请求失败，HTTP \(status)。"
        case .businessError(let code, let message):
            Self.localizedBusinessMessage(code: code, message: message)
        }
    }

    private static func localizedBusinessMessage(code: Int, message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "DeepSeek 返回业务错误 \(code)。"
        }

        switch trimmed.lowercased() {
        case "missing token":
            return "缺少登录 Token，请重新登录 DeepSeek。"
        case "login expired", "unauthorized":
            return "DeepSeek 登录已失效。"
        default:
            return trimmed
        }
    }
}

enum DeepSeekResponseValidator {
    static func validateBusinessEnvelope(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let code = object["code"] as? Int ?? 0
        let msg = object["msg"] as? String ?? ""
        if code != 0 {
            throw DeepSeekError.businessError(code: code, message: msg)
        }
        guard let dataObject = object["data"] as? [String: Any] else {
            throw DeepSeekError.businessError(code: code, message: msg.isEmpty ? "DeepSeek 返回空数据。" : msg)
        }
        let bizCode = dataObject["biz_code"] as? Int ?? 0
        let bizMsg = dataObject["biz_msg"] as? String ?? ""
        if bizCode != 0 {
            throw DeepSeekError.businessError(code: bizCode, message: bizMsg)
        }
        if dataObject["biz_data"] is NSNull {
            throw DeepSeekError.businessError(code: bizCode, message: bizMsg.isEmpty ? "DeepSeek 返回空用量数据。" : bizMsg)
        }
    }
}

extension Decimal {
    static func fromDeepSeekString(_ value: String?) -> Decimal {
        guard let value, !value.isEmpty else { return .zero }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
    }
}

extension Int64 {
    static func fromDeepSeekString(_ value: String?) -> Int64 {
        guard let value else { return 0 }
        return Int64(value) ?? 0
    }
}
