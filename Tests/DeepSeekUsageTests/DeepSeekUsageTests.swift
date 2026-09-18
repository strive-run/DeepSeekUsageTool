import Foundation
import Testing
@testable import DeepSeekUsage

struct DeepSeekUsageTests {
    @Test func testUserSummaryDecoding() throws {
        let envelope = try JSONDecoder().decode(APIEnvelope<UserSummaryPayload>.self, from: Data(summaryJSON.utf8))
        let summary = UsageAggregator.walletSummary(from: envelope.data.bizData)

        #expect(envelope.code == 0)
        #expect(summary.balanceCNY == Decimal(string: "22.5404823200000000")!)
        #expect(summary.monthlyCostCNY == Decimal(string: "16.1022661200000000")!)
        #expect(summary.monthlyTokenUsage == 103_225_801)
        #expect(summary.totalAvailableTokenEstimation == 7_513_494)
    }

    @Test func testAmountDecodingAggregatesTokensAndRequests() throws {
        let envelope = try JSONDecoder().decode(APIEnvelope<UsageAmountPayload>.self, from: Data(amountJSON.utf8))
        let firstDay = try #require(envelope.data.bizData.days.first)

        let tokens = firstDay.data.reduce(Int64.zero) { $0 + $1.tokenValue }
        let requests = firstDay.data.reduce(Int64.zero) { $0 + $1.requestValue }

        #expect(envelope.data.bizData.days.count == 2)
        #expect(tokens == 8_690_339)
        #expect(requests == 106)
    }

    @Test func testCostDecodingAndDailyAggregation() throws {
        let costEnvelope = try JSONDecoder().decode(APIEnvelope<[UsageCostPayload]>.self, from: Data(costJSON.utf8))
        let amountEnvelope = try JSONDecoder().decode(APIEnvelope<UsageAmountPayload>.self, from: Data(amountJSON.utf8))
        let costPayload = try #require(costEnvelope.data.bizData.first)

        let today = ISO8601DateFormatter().date(from: "2026-06-30T12:00:00Z")!
        let points = UsageAggregator.dailyPoints(
            costPayload: costPayload,
            amountPayload: amountEnvelope.data.bizData,
            today: today
        )

        #expect(points.count == 30)
        #expect(points[0].costCNY == Decimal(string: "1.55048056")!)
        #expect(points[0].tokenCount == 8_690_339)
        #expect(points[0].requestCount == 106)
        #expect(points[0].models.count == 2)
        #expect(points[0].models[0].model == "deepseek-v4-flash")
        #expect(points[0].models[0].costCNY == Decimal(string: "0.44088136")!)
        #expect(points[0].models[0].tokenCount == 3_349_061)
        #expect(points[0].models[0].requestCount == 55)
        #expect(points[0].models[1].model == "deepseek-v4-pro")
        #expect(points[0].models[1].costCNY == Decimal(string: "1.10959920")!)
        #expect(points[0].models[1].tokenCount == 5_341_278)
        #expect(points[0].models[1].requestCount == 51)
        #expect(points[0].models.reduce(Decimal.zero) { $0 + $1.costCNY } == points[0].costCNY)
        #expect(points[0].models.reduce(Int64.zero) { $0 + $1.tokenCount } == points[0].tokenCount)
        #expect(points[0].models.reduce(Int64.zero) { $0 + $1.requestCount } == points[0].requestCount)
        #expect(points[1].costCNY == Decimal(string: "1.00693608")!)
        #expect(points[2].costCNY == .zero)
        #expect(points[2].tokenCount == 0)
        #expect(points[2].models == [])
        #expect(points[29].costCNY == .zero)
        #expect(points[29].requestCount == 0)
    }

    @Test func testZeroValueModelBreakdownsAreHiddenForSelectedMetric() {
        let point = DailyUsagePoint(
            date: Date(),
            costCNY: Decimal(1),
            tokenCount: 10,
            requestCount: 1,
            models: [
                DailyModelUsageBreakdown(
                    model: UsageAggregator.normalizedModelName("deepseek-chat"),
                    costCNY: .zero,
                    tokenCount: 0,
                    requestCount: 0
                ),
                DailyModelUsageBreakdown(
                    model: "deepseek-v4-pro",
                    costCNY: Decimal(1),
                    tokenCount: 10,
                    requestCount: 1
                )
            ]
        )

        #expect(UsageAggregator.normalizedModelName("deepseek-reasoner") == "deepseek-chat & deepseek-reasoner")
        #expect(point.visibleModels(for: .cost).map(\.model) == ["deepseek-v4-pro"])
        #expect(point.visibleModels(for: .tokens).map(\.model) == ["deepseek-v4-pro"])
        #expect(point.visibleModels(for: .requests).map(\.model) == ["deepseek-v4-pro"])
    }

    @Test func testMonthToDatePointsFillMissingDates() throws {
        let costEnvelope = try JSONDecoder().decode(APIEnvelope<[UsageCostPayload]>.self, from: Data(costJSON.utf8))
        let amountEnvelope = try JSONDecoder().decode(APIEnvelope<UsageAmountPayload>.self, from: Data(amountJSON.utf8))
        let costPayload = try #require(costEnvelope.data.bizData.first)

        let today = ISO8601DateFormatter().date(from: "2026-06-11T12:00:00Z")!
        let points = UsageAggregator.dailyPoints(
            costPayload: costPayload,
            amountPayload: amountEnvelope.data.bizData,
            today: today
        )

        let calendar = Calendar(identifier: .gregorian)
        #expect(points.count == 11)
        #expect(calendar.isDate(points[0].date, inSameDayAs: ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!))
        #expect(calendar.isDate(points[10].date, inSameDayAs: ISO8601DateFormatter().date(from: "2026-06-11T00:00:00Z")!))
        #expect(points[2].costCNY == .zero)
        #expect(points[2].tokenCount == 0)
        #expect(points[2].requestCount == 0)
    }

    @Test func testSnapshotMonthlyMetricTotalsAndStats() throws {
        let costEnvelope = try JSONDecoder().decode(APIEnvelope<[UsageCostPayload]>.self, from: Data(costJSON.utf8))
        let amountEnvelope = try JSONDecoder().decode(APIEnvelope<UsageAmountPayload>.self, from: Data(amountJSON.utf8))
        let costPayload = try #require(costEnvelope.data.bizData.first)
        let summaryEnvelope = try JSONDecoder().decode(APIEnvelope<UserSummaryPayload>.self, from: Data(summaryJSON.utf8))
        let today = ISO8601DateFormatter().date(from: "2026-06-11T12:00:00Z")!
        let points = UsageAggregator.dailyPoints(
            costPayload: costPayload,
            amountPayload: amountEnvelope.data.bizData,
            today: today
        )
        let snapshot = UsageSnapshot(
            summary: UsageAggregator.walletSummary(from: summaryEnvelope.data.bizData),
            dailyPoints: points,
            lastUpdated: today
        )

        #expect(snapshot.totalCostCNY == Decimal(string: "2.55741664")!)
        #expect(snapshot.totalTokenCount == 24_590_291)
        #expect(snapshot.totalRequestCount == 347)
        #expect(snapshot.dailyAverageTokenCount == 2_235_481)
        #expect(snapshot.dailyAverageRequestCount == 31)
        #expect(snapshot.peakTokenCount == 15_899_952)
        #expect(snapshot.peakRequestCount == 241)
        #expect(snapshot.activeDays == 2)
    }

    @Test func testSnapshotTodayUsesLastUpdatedDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let juneTen = ISO8601DateFormatter().date(from: "2026-06-10T00:00:00Z")!
        let juneEleven = ISO8601DateFormatter().date(from: "2026-06-11T00:00:00Z")!
        let snapshot = UsageSnapshot(
            summary: WalletSummary(
                balanceCNY: .zero,
                bonusCNY: .zero,
                monthlyCostCNY: .zero,
                monthlyTokenUsage: 0,
                totalAvailableTokenEstimation: 0,
                currentToken: 0
            ),
            dailyPoints: [
                DailyUsagePoint(date: juneTen, costCNY: Decimal(1), tokenCount: 10, requestCount: 1),
                DailyUsagePoint(date: juneEleven, costCNY: Decimal(2), tokenCount: 20, requestCount: 2)
            ],
            lastUpdated: ISO8601DateFormatter().date(from: "2026-06-11T12:00:00Z")!
        )

        let today = try #require(snapshot.today)
        #expect(calendar.isDate(today.date, inSameDayAs: juneEleven))
        #expect(today.costCNY == Decimal(2))
    }

    @Test func testFutureDatesAreIgnored() throws {
        let costEnvelope = try JSONDecoder().decode(APIEnvelope<[UsageCostPayload]>.self, from: Data(costJSON.utf8))
        let amountEnvelope = try JSONDecoder().decode(APIEnvelope<UsageAmountPayload>.self, from: Data(amountJSON.utf8))
        let costPayload = try #require(costEnvelope.data.bizData.first)

        let today = ISO8601DateFormatter().date(from: "2026-06-01T12:00:00Z")!
        let points = UsageAggregator.dailyPoints(
            costPayload: costPayload,
            amountPayload: amountEnvelope.data.bizData,
            today: today
        )

        #expect(points.count == 1)
        #expect(points[0].requestCount == 106)
    }

    @Test func testNullDataBusinessErrorIsNotDecodedAsMissingData() throws {
        let data = Data(#"{"code":40002,"msg":"Missing Token","data":null}"#.utf8)

        do {
            _ = try DeepSeekResponseValidator.validateBusinessEnvelope(data)
            Issue.record("Expected .businessError to be thrown")
        } catch let error as DeepSeekError {
            #expect(error == .businessError(code: 40002, message: "Missing Token"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @MainActor
    @Test func testBridgeResponseDecodingSuccess() throws {
        let decoded = try #require(
            DeepSeekScriptBridge.decodeResponse(
                from: ["requestId": "abc", "status": 200, "ok": true, "body": #"{"code":0}"#]
            )
        )

        #expect(decoded.requestId == "abc")
        #expect(decoded.response == WebFetchResponse(status: 200, ok: true, body: #"{"code":0}"#, error: nil))
    }

    @MainActor
    @Test func testBridgeResponseDecodingError() throws {
        let decoded = try #require(
            DeepSeekScriptBridge.decodeResponse(
                from: ["requestId": "abc", "error": "network failed"]
            )
        )

        #expect(decoded.requestId == "abc")
        #expect(decoded.response.error == "network failed")
        #expect(decoded.response.errorOrNil == .businessError(code: -1, message: "network failed"))
    }

    @MainActor
    @Test func testBridgeResponseDecodingUnauthorizedStatus() throws {
        let decoded = try #require(
            DeepSeekScriptBridge.decodeResponse(
                from: ["requestId": "abc", "status": 401, "ok": false, "body": ""]
            )
        )

        #expect(decoded.response.status == 401)
        #expect(decoded.response.ok == false)
    }

    @MainActor
    @Test func testFetchScriptStartsAsyncWorkWithoutReturningPromise() {
        let script = DeepSeekWebSession.fetchScript(requestId: "request-1", relativeURL: "/api/v0/users/get_user_summary")

        #expect(script.contains("(async ()") == false)
        #expect(script.contains("postMessage"))
        #expect(script.contains("return undefined;"))
        #expect(script.contains("request-1"))
    }
}

private let summaryJSON = """
{
  "code": 0,
  "msg": "",
  "data": {
    "biz_code": 0,
    "biz_msg": "",
    "biz_data": {
      "current_token": 10000000,
      "monthly_usage": "103225801",
      "total_usage": 0,
      "normal_wallets": [
        {
          "currency": "CNY",
          "balance": "22.5404823200000000",
          "token_estimation": "7513494"
        }
      ],
      "bonus_wallets": [
        {
          "currency": "CNY",
          "balance": "0",
          "token_estimation": "0"
        }
      ],
      "total_available_token_estimation": "7513494",
      "monthly_costs": [
        {
          "currency": "CNY",
          "amount": "16.1022661200000000"
        }
      ],
      "monthly_token_usage": "103225801"
    }
  }
}
"""

private let amountJSON = """
{
  "code": 0,
  "msg": "",
  "data": {
    "biz_code": 0,
    "biz_msg": "",
    "biz_data": {
      "total": [],
      "days": [
        {
          "date": "2026-06-01",
          "data": [
            {
              "model": "deepseek-v4-pro",
              "usage": [
                { "type": "PROMPT_TOKEN", "amount": "0" },
                { "type": "PROMPT_CACHE_HIT_TOKEN", "amount": "5036928" },
                { "type": "PROMPT_CACHE_MISS_TOKEN", "amount": "280808" },
                { "type": "RESPONSE_TOKEN", "amount": "23542" },
                { "type": "REQUEST", "amount": "51" }
              ]
            },
            {
              "model": "deepseek-v4-flash",
              "usage": [
                { "type": "PROMPT_TOKEN", "amount": "0" },
                { "type": "PROMPT_CACHE_HIT_TOKEN", "amount": "2989568" },
                { "type": "PROMPT_CACHE_MISS_TOKEN", "amount": "337896" },
                { "type": "RESPONSE_TOKEN", "amount": "21597" },
                { "type": "REQUEST", "amount": "55" }
              ]
            }
          ]
        },
        {
          "date": "2026-06-02",
          "data": [
            {
              "model": "deepseek-v4-flash",
              "usage": [
                { "type": "PROMPT_TOKEN", "amount": "0" },
                { "type": "PROMPT_CACHE_HIT_TOKEN", "amount": "15275904" },
                { "type": "PROMPT_CACHE_MISS_TOKEN", "amount": "546678" },
                { "type": "RESPONSE_TOKEN", "amount": "77370" },
                { "type": "REQUEST", "amount": "241" }
              ]
            }
          ]
        }
      ]
    }
  }
}
"""

private let costJSON = """
{
  "code": 0,
  "msg": "",
  "data": {
    "biz_code": 0,
    "biz_msg": "",
    "biz_data": [
      {
        "currency": "CNY",
        "total": [],
        "days": [
          {
            "date": "2026-06-01",
            "data": [
              {
                "model": "deepseek-v4-pro",
                "usage": [
                  { "type": "PROMPT_TOKEN", "amount": "0" },
                  { "type": "PROMPT_CACHE_HIT_TOKEN", "amount": "0.1259232000000000" },
                  { "type": "PROMPT_CACHE_MISS_TOKEN", "amount": "0.8424240000000000" },
                  { "type": "RESPONSE_TOKEN", "amount": "0.1412520000000000" },
                  { "type": "REQUEST", "amount": "0" }
                ]
              },
              {
                "model": "deepseek-v4-flash",
                "usage": [
                  { "type": "PROMPT_TOKEN", "amount": "0" },
                  { "type": "PROMPT_CACHE_HIT_TOKEN", "amount": "0.0597913600000000" },
                  { "type": "PROMPT_CACHE_MISS_TOKEN", "amount": "0.3378960000000000" },
                  { "type": "RESPONSE_TOKEN", "amount": "0.0431940000000000" },
                  { "type": "REQUEST", "amount": "0" }
                ]
              }
            ]
          },
          {
            "date": "2026-06-02",
            "data": [
              {
                "model": "deepseek-v4-flash",
                "usage": [
                  { "type": "PROMPT_TOKEN", "amount": "0" },
                  { "type": "PROMPT_CACHE_HIT_TOKEN", "amount": "0.3055180800000000" },
                  { "type": "PROMPT_CACHE_MISS_TOKEN", "amount": "0.5466780000000000" },
                  { "type": "RESPONSE_TOKEN", "amount": "0.1547400000000000" },
                  { "type": "REQUEST", "amount": "0" }
                ]
              }
            ]
          }
        ]
      }
    ]
  }
}
"""