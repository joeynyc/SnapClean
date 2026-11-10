import SwiftUI
import AppKit

// MARK: - Share picker

/// Holds the AppKit view a share picker is anchored to. Keep one in `@State` and attach it to
/// the share button with `.sharingAnchor(_:)`.
@MainActor
final class SharingAnchor {
    fileprivate(set) weak var view: NSView?

    /// Shows the system share picker below the anchored view. `onFinish` runs once the picker
    /// closes, whether a service was chosen or not.
    func showPicker(items: [Any], onFinish: (() -> Void)? = nil) {
        guard let view, view.window != nil, !items.isEmpty else {
            onFinish?()
            return
        }
        SharingPickerSession.show(items: items, relativeTo: view, onFinish: onFinish)
    }
}

extension View {
    /// Marks this view as the place a `SharingAnchor`'s picker appears from.
    func sharingAnchor(_ anchor: SharingAnchor) -> some View {
        background(SharingAnchorView(anchor: anchor))
    }
}

private struct SharingAnchorView: NSViewRepresentable {
    let anchor: SharingAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

/// Keeps the picker's delegate alive while the picker is open; NSSharingServicePicker holds it weakly.
@MainActor
private final class SharingPickerSession: NSObject, NSSharingServicePickerDelegate {
    private static var active: SharingPickerSession?

    private let picker: NSSharingServicePicker
    private var onFinish: (() -> Void)?

    private init(items: [Any], onFinish: (() -> Void)?) {
        self.picker = NSSharingServicePicker(items: items)
        self.onFinish = onFinish
        super.init()
        picker.delegate = self
    }

    static func show(items: [Any], relativeTo view: NSView, onFinish: (() -> Void)?) {
        active?.finish()
        let session = SharingPickerSession(items: items, onFinish: onFinish)
        active = session
        session.picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    nonisolated func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        MainActor.assumeIsolated { finish() }
    }

    private func finish() {
        let callback = onFinish
        onFinish = nil
        if Self.active === self {
            Self.active = nil
        }
        callback?()
    }
}

// MARK: - Drag handle

/// A small "Drag" handle that drags the screenshot out as a PNG file. The canvas itself is for
/// drawing, so the editor offers this instead of making the image a drag source.
struct DragOutHandle: View {
    let makeItemProvider: () -> NSItemProvider

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw")
                .font(.system(size: 14, weight: .medium))
            Text("Drag")
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(isHovered ? Color.accentColor : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    Color.secondary.opacity(isHovered ? 0 : 0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onDrag(makeItemProvider)
        .help("Drag the screenshot into Finder, Mail, Slack or Messages")
        .accessibilityLabel("Drag screenshot")
    }
}
