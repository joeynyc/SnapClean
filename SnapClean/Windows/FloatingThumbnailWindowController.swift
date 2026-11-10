import SwiftUI
import AppKit

/// Where the floating thumbnail goes and how big it is. Pure geometry in Cocoa coordinates.
enum FloatingThumbnailLayout {
    /// The thumbnail image is fitted inside this box...
    static let maxThumbnailSize = CGSize(width: 240, height: 160)
    /// ...but the card never gets smaller than this, so the hover buttons always fit.
    static let minThumbnailSize = CGSize(width: 180, height: 110)
    /// Transparent room around the card for its shadow.
    static let shadowPadding: CGFloat = 16
    /// Distance from the card to the screen's visible edges.
    static let screenMargin: CGFloat = 20

    /// The card size for an image: aspect-fit into `maxThumbnailSize`, then raised to `minThumbnailSize`.
    static func thumbnailSize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return minThumbnailSize }
        let scale = min(maxThumbnailSize.width / imageSize.width, maxThumbnailSize.height / imageSize.height, 1)
        return CGSize(
            width: max((imageSize.width * scale).rounded(), minThumbnailSize.width),
            height: max((imageSize.height * scale).rounded(), minThumbnailSize.height)
        )
    }

    static func panelSize(forThumbnail size: CGSize) -> CGSize {
        CGSize(width: size.width + shadowPadding * 2, height: size.height + shadowPadding * 2)
    }

    /// Bottom-right corner of `visibleFrame` (Cocoa coordinates, so the bottom is `minY`).
    static func panelFrame(panelSize: CGSize, in visibleFrame: CGRect) -> CGRect {
        let inset = screenMargin - shadowPadding
        return CGRect(
            x: visibleFrame.maxX - panelSize.width - inset,
            y: visibleFrame.minY + inset,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    struct ScreenInfo: Equatable {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    /// The visible frame of the screen containing `point`, else of `fallback` (the main screen),
    /// else of the first screen.
    static func visibleFrame(containing point: CGPoint?, screens: [ScreenInfo], fallback: ScreenInfo?) -> CGRect? {
        if let point, let screen = screens.first(where: { contains($0.frame, point) }) {
            return screen.visibleFrame
        }
        return (fallback ?? screens.first)?.visibleFrame
    }

    /// Like `NSMouseInRect` for an unflipped rect: the top and right edges belong to the next screen.
    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x < rect.maxX && point.y > rect.minY && point.y <= rect.maxY
    }
}

/// Hosts `FloatingThumbnailView` in a small borderless panel in the corner of the screen. The panel
/// never activates SnapClean or takes key focus, so typing in the frontmost app is undisturbed.
@MainActor
final class FloatingThumbnailWindowController: FloatingThumbnailPresenting {
    private var panel: NSPanel?

    func show(_ state: FloatingThumbnailState, image: NSImage, near point: CGPoint?) {
        hide()

        let thumbnailSize = FloatingThumbnailLayout.thumbnailSize(for: image.size)
        let panelSize = FloatingThumbnailLayout.panelSize(forThumbnail: thumbnailSize)
        let screens = NSScreen.screens.map {
            FloatingThumbnailLayout.ScreenInfo(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let fallback = NSScreen.main.map {
            FloatingThumbnailLayout.ScreenInfo(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        guard let visibleFrame = FloatingThumbnailLayout.visibleFrame(
            containing: point,
            screens: screens,
            fallback: fallback
        ) else { return }

        let frame = FloatingThumbnailLayout.panelFrame(panelSize: panelSize, in: visibleFrame)
        let panel = makePanel(frame: frame)

        let container = HoverTrackingView(frame: CGRect(origin: .zero, size: frame.size))
        container.onHoverChange = { [weak state] hovering in
            state?.setHovered(hovering)
        }
        let hostingView = FirstMouseHostingView(
            rootView: FloatingThumbnailView(state: state, image: image, thumbnailSize: thumbnailSize)
        )
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container

        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)
        // Usually called from one of the panel's own buttons; tear the hosting view down after
        // that event has finished rather than from inside its handler.
        DispatchQueue.main.async {
            panel.contentView = nil
            panel.close()
        }
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // SwiftUI draws the card's shadow; a window shadow would outline the transparent padding.
        panel.hasShadow = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        return panel
    }
}

/// Clicks on the thumbnail work on the first click even though SnapClean isn't active.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Reports pointer enter/exit for the whole panel, whether or not SnapClean is active.
private final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}
