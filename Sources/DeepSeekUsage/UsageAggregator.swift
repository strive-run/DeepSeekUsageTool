import Foundation

enum UsageAggregator {
    private struct ModelAccumulator {
        var costCNY: Decimal = .zero
        var tokenCount: Int64 = 0
        var requestCount: Int64 = 0
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func walletSummary(
        from payload: UserSummaryPayload,
        monthlyCostCNY: Decimal? = nil
    ) -> WalletSummary {
        let normal = payload.normalWallets.first { $0.currency == "CNY" } ?? payload.normalWallets.first
        let bonus = payload.bonusWallets.first { $0.currency == "CNY" } ?? payload.bonusWallets.first
        let totalCost = payload.totalCosts.first { $0.currency == "CNY" } ?? payload.totalCosts.first

        return WalletSummary(
            balanceCNY: .fromDeepSeekString(normal?.balance),
            bonusCNY: .fromDeepSeekString(bonus?.balance),
            monthlyCostCNY: monthlyCostCNY ?? .fromDeepSeekString(totalCost?.amount),
            monthlyTokenUsage: .fromDeepSeekString(payload.monthlyTokenUsage),
            totalAvailableTokenEstimation: .fromDeepSeekString(payload.totalAvailableTokenEstimation ?? normal?.tokenEstimation),
            currentToken: payload.currentToken ?? 0
        )
    }

    static func dailyPoints(
        costPayload: UsageCostPayload,
        amountPayload: UsageAmountPayload,
        today: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [DailyUsagePoint] {
        let todayStart = calendar.startOfDay(for: today)
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: todayStart)
        ) else {
            return []
        }

        var modelsByDate: [Date: [String: ModelAccumulator]] = [:]

        for day in costPayload.days {
            guard let date = dateFormatter.date(from: day.date) else {
                continue
            }
            let normalizedDate = calendar.startOfDay(for: date)
            guard normalizedDate >= monthStart, normalizedDate <= todayStart else {
                continue
            }
            for model in day.data {
                let modelName = normalizedModelName(model.model)
                modelsByDate[normalizedDate, default: [:]][modelName, default: ModelAccumulator()].costCNY += model.costValue
            }
        }

        for day in amountPayload.days {
            guard let date = dateFormatter.date(from: day.date) else {
                continue
            }
            let normalizedDate = calendar.startOfDay(for: date)
            guard normalizedDate >= monthStart, normalizedDate <= todayStart else {
                continue
            }
            for model in day.data {
                let modelName = normalizedModelName(model.model)
                modelsByDate[normalizedDate, default: [:]][modelName, default: ModelAccumulator()].tokenCount += model.tokenValue
                modelsByDate[normalizedDate, default: [:]][modelName, default: ModelAccumulator()].requestCount += model.requestValue
            }
        }

        return monthDates(from: monthStart, through: todayStart, calendar: calendar).map { date in
            let models = sortedModelBreakdowns(from: modelsByDate[date] ?? [:])
            return DailyUsagePoint(
                date: date,
                costCNY: models.reduce(Decimal.zero) { $0 + $1.costCNY },
                tokenCount: models.reduce(Int64.zero) { $0 + $1.tokenCount },
                requestCount: models.reduce(Int64.zero) { $0 + $1.requestCount },
                models: models
            )
        }
    }

    static func dailyPoints(
        byApiKeyCostPayload costPayload: UsageByApiKeyCostPayload,
        byApiKeyAmountPayload amountPayload: UsageByApiKeyAmountPayload,
        today: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [DailyUsagePoint] {
        let todayStart = calendar.startOfDay(for: today)
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: todayStart)
        ) else {
            return []
        }

        var modelsByDate: [Date: [String: ModelAccumulator]] = [:]

        for currencySeries in costPayload.data where currencySeries.currency == "CNY" {
            for series in currencySeries.series {
                let modelName = normalizedModelName(series.model)
                for bucket in series.buckets {
                    guard let date = dayStart(from: bucket.time, calendar: calendar),
                          date >= monthStart, date <= todayStart else {
                        continue
                    }
                    modelsByDate[date, default: [:]][modelName, default: ModelAccumulator()].costCNY += .fromDeepSeekString(bucket.cost)
                }
            }
        }

        for series in amountPayload.series {
            let modelName = normalizedModelName(series.model)
            for bucket in series.buckets {
                guard let date = dayStart(from: bucket.time, calendar: calendar),
                      date >= monthStart, date <= todayStart else {
                    continue
                }
                var accumulator = modelsByDate[date]?[modelName] ?? ModelAccumulator()
                for (key, value) in bucket.usage ?? [:] {
                    switch key {
                    case "PROMPT_TOKEN", "PROMPT_CACHE_HIT_TOKEN", "PROMPT_CACHE_MISS_TOKEN", "RESPONSE_TOKEN":
                        accumulator.tokenCount += value
                    case "REQUEST":
                        accumulator.requestCount += value
                    default:
                        break
                    }
                }
                modelsByDate[date, default: [:]][modelName] = accumulator
            }
        }

        return monthDates(from: monthStart, through: todayStart, calendar: calendar).map { date in
            let models = sortedModelBreakdowns(from: modelsByDate[date] ?? [:])
            return DailyUsagePoint(
                date: date,
                costCNY: models.reduce(Decimal.zero) { $0 + $1.costCNY },
                tokenCount: models.reduce(Int64.zero) { $0 + $1.tokenCount },
                requestCount: models.reduce(Int64.zero) { $0 + $1.requestCount },
                models: models
            )
        }
    }

    static func normalizedModelName(_ model: String) -> String {
        switch model {
        case "deepseek-chat", "deepseek-reasoner":
            "deepseek-chat & deepseek-reasoner"
        default:
            model
        }
    }

    private static func sortedModelBreakdowns(from accumulators: [String: ModelAccumulator]) -> [DailyModelUsageBreakdown] {
        accumulators
            .map { model, value in
                DailyModelUsageBreakdown(
                    model: model,
                    costCNY: value.costCNY,
                    tokenCount: value.tokenCount,
                    requestCount: value.requestCount
                )
            }
            .sorted { lhs, rhs in
                let lhsRank = modelSortRank(lhs.model)
                let rhsRank = modelSortRank(rhs.model)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.model.localizedStandardCompare(rhs.model) == .orderedAscending
            }
    }

    private static func modelSortRank(_ model: String) -> Int {
        switch model {
        case "deepseek-v4-flash":
            0
        case "deepseek-v4-pro":
            1
        case "deepseek-chat & deepseek-reasoner":
            2
        default:
            10
        }
    }

    private static func dayStart(from epochSeconds: Int64, calendar: Calendar) -> Date? {
        calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    private static func monthDates(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        var cursor = start
        while cursor <= end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return dates
    }
}

extension ModelUsagePayload {
    var costValue: Decimal {
        usage.reduce(Decimal.zero) { partial, value in
            value.type == "REQUEST" ? partial : partial + .fromDeepSeekString(value.amount)
        }
    }

    var tokenValue: Int64 {
        usage.reduce(Int64.zero) { partial, value in
            switch value.type {
            case "PROMPT_TOKEN", "PROMPT_CACHE_HIT_TOKEN", "PROMPT_CACHE_MISS_TOKEN", "RESPONSE_TOKEN":
                partial + .fromDeepSeekString(value.amount)
            default:
                partial
            }
        }
    }

    var requestValue: Int64 {
        usage.first { $0.type == "REQUEST" }.map { .fromDeepSeekString($0.amount) } ?? 0
    }
}

extension JSONDecoder {
    static var deepSeek: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var deepSeek: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
