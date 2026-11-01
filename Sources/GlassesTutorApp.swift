import SwiftUI
import UIKit
import MWDATCore

@main
struct GlassesTutorApp: App {
    @StateObject private var model = AppModel()

    init() {
        do {
            try Wearables.configure()
        } catch {
            assertionFailure("Wearables.configure failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { url in
                    // Meta AI calls back with ?metaWearablesAction=... after registration
                    // and permission prompts. Anything else is not ours.
                    guard
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                        components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
                    else { return }
                    Task { @MainActor in
                        do {
                            _ = try await Wearables.shared.handleUrl(url)
                            model.glasses.log("Meta AI callback handled")
                        } catch {
                            model.glasses.log("handleUrl: \(error)")
                        }
                    }
                }
                .onAppear {
                    // The app must stay on screen for the glasses session to live,
                    // so never let the phone dim and lock on its own.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}
