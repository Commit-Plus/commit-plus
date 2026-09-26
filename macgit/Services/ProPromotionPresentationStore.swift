// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import FirebaseCore
import FirebaseFirestore

@MainActor
final class ProPromotionPresentationStore {
    static let shared = ProPromotionPresentationStore()
    private var reservedID: String?
    private var loading = false
    private let defaults = UserDefaults.standard
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var ignoresFrequency: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    func claimPresentation() async -> ProPromotion? {
        guard !loading, reservedID == nil, !FirebaseBootstrap.isRunningUnitTests,
              FirebaseApp.app() != nil else { return nil }
        loading = true
        defer { loading = false }
        do {
            // Server-only reads prevent a disabled or expired campaign resurfacing offline.
            let snapshot = try await Firestore.firestore().collection("featurePolicies")
                .document("release").getDocument(source: .server)
            guard !Task.isCancelled,
                  let data = snapshot.data()?["promotion"] as? [String: Any],
                  let promotion = ProPromotion(data: data),
                  promotion.isEligible(
                    defaults: defaults,
                    now: Date(),
                    version: version,
                    ignoresFrequency: ignoresFrequency
                  )
            else { return nil }
            reservedID = promotion.id
            return promotion
        } catch {
            return nil
        }
    }

    func didPresent(_ promotion: ProPromotion) {
        guard reservedID == promotion.id else { return }
        defaults.set(Date(), forKey: "proPromotion.\(promotion.id).date")
        defaults.set(version, forKey: "proPromotion.\(promotion.id).version")
    }

    func releasePresentation() {
        reservedID = nil
    }
}
