import SwiftUI
import Combine
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
final class AdMobController: ObservableObject {
    @Published private(set) var canRequestAds = false
    private var hasStartedAds = false

    func start() async {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            // A previous valid consent decision can still permit ads if refreshing fails.
            print("AdMob consent update failed: \(error.localizedDescription)")
        }

        guard ConsentInformation.shared.canRequestAds else { return }
        startAdsIfNeeded()
    }

    private func startAdsIfNeeded() {
        guard !hasStartedAds else { return }
        hasStartedAds = true
        MobileAds.shared.start()
        canRequestAds = true
    }
}

struct AdMobBannerView: View {
    let adUnitID: String

    var body: some View {
        GeometryReader { geometry in
            BannerViewContainer(
                adSize: largeAnchoredAdaptiveBanner(width: geometry.size.width),
                adUnitID: adUnitID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 64)
        .accessibilityLabel("Advertisement")
    }
}

private struct BannerViewContainer: UIViewRepresentable {
    let adSize: AdSize
    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {}
}
