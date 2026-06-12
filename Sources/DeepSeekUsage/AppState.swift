import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedMetric: UsageMetric = .cost

    private let webSession: DeepSeekWebSession
    private var refreshTask: Task<Void, Never>?
    private var refreshSequence = 0

    init(
        webSession: DeepSeekWebSession
    ) {
        self.webSession = webSession
    }

    func cancelRefresh() {
        refreshSequence += 1
        refreshTask?.cancel()
        refreshTask = nil
        isLoading = false
    }

    func logout() {
        cancelRefresh()
        snapshot = nil
        errorMessage = "已退出登录。"
    }

    func update(with snapshot: UsageSnapshot) {
        cancelRefresh()
        self.snapshot = snapshot
        errorMessage = nil
    }

    func refresh() {
        refreshSequence += 1
        let sequence = refreshSequence
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh(sequence: sequence)
        }
    }

    private func performRefresh(sequence: Int) async {
        isLoading = true
        defer {
            if sequence == refreshSequence {
                isLoading = false
                refreshTask = nil
            }
        }

        do {
            let newSnapshot = try await webSession.fetchSnapshot()
            guard !Task.isCancelled, sequence == refreshSequence else { return }
            snapshot = newSnapshot
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, sequence == refreshSequence else { return }
            errorMessage = error.localizedDescription
        }
    }
}
