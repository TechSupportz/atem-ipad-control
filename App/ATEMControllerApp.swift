import SwiftUI

@main
@MainActor
struct ATEMControllerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = ATEMController()

    var body: some Scene {
        WindowGroup {
            ControllerShellView(controller: controller)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        controller.resumeAfterForegrounding()
                    }
                }
        }
    }
}
