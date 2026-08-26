import Combine
import Foundation
import StoreKit

enum SchedAIProduct: String, CaseIterable, Sendable {
    case monthly = "me.SchedAI.pro.monthly"
    case annual = "me.SchedAI.pro.annual"

    static func isPro(_ productID: String) -> Bool {
        allCases.contains { $0.rawValue == productID }
    }
}

enum PaywallContext: String, Identifiable, Sendable {
    case hostedAI
    case removeAds
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hostedAI:
            return "Keep improving with AI"
        case .removeAds:
            return "Plan without ads"
        case .settings:
            return "Upgrade to SchedAI Pro"
        }
    }

    var subtitle: String {
        switch self {
        case .hostedAI:
            return "You used today's free hosted AI improvements. Pro keeps the cloud fallback available when on-device intelligence needs help."
        case .removeAds:
            return "SchedAI Pro removes banner ads and includes expanded hosted AI access."
        case .settings:
            return "Get expanded hosted AI access, remove banner ads, and support continued improvements to SchedAI."
        }
    }
}

struct HostedAIUsage: Codable, Equatable, Sendable {
    private(set) var dayKey: String
    private(set) var count: Int

    init(dayKey: String = "", count: Int = 0) {
        self.dayKey = dayKey
        self.count = max(0, count)
    }

    func remaining(limit: Int, on date: Date, calendar: Calendar = .current) -> Int {
        let usedToday = dayKey == Self.dayKey(for: date, calendar: calendar) ? count : 0
        return max(0, limit - usedToday)
    }

    mutating func recordUse(on date: Date, calendar: Calendar = .current) {
        let currentDay = Self.dayKey(for: date, calendar: calendar)
        if dayKey != currentDay {
            dayKey = currentDay
            count = 0
        }
        count += 1
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let freeHostedAILimit = 3

    private enum DefaultsKey {
        static let hostedAIUsage = "hostedAIUsageV1"
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published private(set) var isLoading = false
    @Published private(set) var isRestoring = false
    @Published private(set) var statusMessage: String?
    @Published var presentedPaywall: PaywallContext?

    private(set) var entitlementJWS: String?

    private let defaults: UserDefaults
    private var usage: HostedAIUsage
    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: DefaultsKey.hostedAIUsage),
           let decoded = try? JSONDecoder().decode(HostedAIUsage.self, from: data) {
            self.usage = decoded
        } else {
            self.usage = HostedAIUsage()
        }

        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var remainingFreeHostedImprovements: Int {
        usage.remaining(limit: Self.freeHostedAILimit, on: Date())
    }

    var canUseHostedAI: Bool {
        isPro || remainingFreeHostedImprovements > 0
    }

    var proStatusText: String {
        if isPro {
            return "SchedAI Pro is active"
        }
        let remaining = remainingFreeHostedImprovements
        return "\(remaining) of \(Self.freeHostedAILimit) free AI improvements left today"
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let loadedProducts = loadProducts()
        await refreshEntitlements()
        products = await loadedProducts
    }

    func purchase(_ product: Product) async {
        statusMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    statusMessage = "The App Store could not verify this purchase."
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                statusMessage = "Your purchase is pending approval."
            case .userCancelled:
                break
            @unknown default:
                statusMessage = "The purchase could not be completed."
            }
        } catch {
            statusMessage = "The purchase could not be completed. Please try again."
        }
    }

    func restorePurchases() async {
        statusMessage = nil
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isPro ? "SchedAI Pro was restored." : "No active SchedAI Pro subscription was found."
        } catch {
            statusMessage = "Purchases could not be restored. Please try again."
        }
    }

    func presentPaywall(_ context: PaywallContext) {
        presentedPaywall = context
    }

    func recordHostedAIUse() {
        guard !isPro else { return }
        usage.recordUse(on: Date())
        persistUsage()
        objectWillChange.send()
    }

    func clearStatusMessage() {
        statusMessage = nil
    }

    private func loadProducts() async -> [Product] {
        do {
            let loaded = try await Product.products(for: SchedAIProduct.allCases.map(\.rawValue))
            return loaded.sorted { lhs, rhs in
                if lhs.price == rhs.price { return lhs.id < rhs.id }
                return lhs.price < rhs.price
            }
        } catch {
            statusMessage = "Subscription options are temporarily unavailable."
            return []
        }
    }

    private func refreshEntitlements() async {
        var activeJWS: String?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard SchedAIProduct.isPro(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= Date() { continue }
            activeJWS = result.jwsRepresentation
            break
        }

        entitlementJWS = activeJWS
        isPro = activeJWS != nil
        if isPro {
            presentedPaywall = nil
        }
    }

    private func persistUsage() {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: DefaultsKey.hostedAIUsage)
    }
}
