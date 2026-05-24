import Observation

@MainActor
@Observable
final class AppEnvironment {
    let mediaManager: any MediaManaging

    init(mediaManager: any MediaManaging = MediaManager.shared) {
        self.mediaManager = mediaManager
    }

    static var preview: AppEnvironment {
        AppEnvironment(mediaManager: MediaManager.shared)
    }
}
