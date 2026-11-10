import Foundation

/// What happens after a capture when "Show preview after capture" is on.
enum AfterCaptureAction: String, CaseIterable, Identifiable {
    /// Open the annotation editor in the main window (the original behavior).
    case openEditor
    /// Show a floating thumbnail in the corner of the screen; it saves itself after a few seconds.
    case floatingThumbnail

    static let defaultsKey = "afterCaptureAction"
    static let defaultValue: AfterCaptureAction = .openEditor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openEditor: return "Open editor"
        case .floatingThumbnail: return "Show floating thumbnail"
        }
    }

    /// The stored choice, or the default when nothing (or something unrecognized) is stored.
    static func load(from defaults: UserDefaults = .standard) -> AfterCaptureAction {
        defaults.string(forKey: defaultsKey).flatMap(AfterCaptureAction.init(rawValue:)) ?? defaultValue
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// How `AppState.handleCapturedImage` treats a new capture.
enum AfterCaptureOutcome: Equatable {
    case openEditor
    case showFloatingThumbnail
    /// Preview turned off: save straight to Downloads.
    case saveImmediately

    init(showPreview: Bool, action: AfterCaptureAction) {
        guard showPreview else {
            self = .saveImmediately
            return
        }
        switch action {
        case .openEditor: self = .openEditor
        case .floatingThumbnail: self = .showFloatingThumbnail
        }
    }
}
