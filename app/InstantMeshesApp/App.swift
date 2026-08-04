import SwiftUI

@main
struct InstantMeshesApp: App {
    @StateObject private var viewModel = MeshViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 900, minHeight: 650)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
