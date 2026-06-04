import SwiftUI

@main
struct ShotTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            CameraScreen()
                .ignoresSafeArea()
        }
    }
}

/// UIViewController を SwiftUI に橋渡し
struct CameraScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraViewController {
        CameraViewController()
    }
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}
