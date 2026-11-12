import SwiftUI

@main
struct LyngoTunesApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.settings)
                .environment(model.session)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    model.setActive(phase == .active)
                }
        }
    }
}
