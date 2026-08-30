import Foundation
import StoreKit

@MainActor
final class UnlockStore: ObservableObject {
    static let unlockProductID = "com.afterimage.camera.unlock"

    @Published private(set) var unlockProduct: Product?
    @Published private(set) var isUnlocked = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = listenForTransactionUpdates()
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func configure() async {
        await refreshEntitlements()
        await loadProducts()
    }

    func canBeginNewRoll(hasCompletedFreeRoll: Bool) -> Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "nine.debug.forcePurchaseGate") {
            return !hasCompletedFreeRoll
        }
        #endif

        return isUnlocked || !hasCompletedFreeRoll
    }

    func purchaseUnlock() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let product: Product
            if let unlockProduct {
                product = unlockProduct
            } else {
                product = try await loadUnlockProduct()
            }
            unlockProduct = product
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                isUnlocked = true
                statusMessage = nil
                await transaction.finish()
            case .userCancelled:
                statusMessage = nil
            case .pending:
                statusMessage = "Purchase pending."
            @unknown default:
                statusMessage = "Purchase unavailable."
            }
        } catch {
            statusMessage = "Purchase unavailable."
        }
    }

    func restorePurchases() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isUnlocked ? nil : "No purchase found."
        } catch {
            statusMessage = "Restore unavailable."
        }
    }

    private func loadProducts() async {
        do {
            unlockProduct = try await loadUnlockProduct()
        } catch {
            unlockProduct = nil
        }
    }

    private func loadUnlockProduct() async throws -> Product {
        guard let product = try await Product.products(for: [Self.unlockProductID]).first else {
            throw UnlockStoreError.productNotFound
        }
        return product
    }

    private func refreshEntitlements() async {
        var ownsUnlock = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  transaction.productID == Self.unlockProductID,
                  transaction.revocationDate == nil else {
                continue
            }
            ownsUnlock = true
            break
        }
        isUnlocked = ownsUnlock
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.checkVerified(result) else { continue }
                if transaction.productID == Self.unlockProductID, transaction.revocationDate == nil {
                    await MainActor.run {
                        self.isUnlocked = true
                        self.statusMessage = nil
                    }
                }
                await transaction.finish()
            }
        }
    }

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw UnlockStoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

private enum UnlockStoreError: Error {
    case failedVerification
    case productNotFound
}
