import SwiftUI

/// The post-capture thumbnail card. Click opens the editor, drag drops the capture as a PNG file,
/// and hovering reveals Close, Copy, Share, Pin and Save.
struct FloatingThumbnailView: View {
    let state: FloatingThumbnailState
    let image: NSImage
    let thumbnailSize: CGSize

    @State private var shareAnchor = SharingAnchor()
    @State private var didCopy = false

    private static let cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
                .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
                .onTapGesture { state.openEditor() }
                .onDrag { state.beginDragOut() }
                .help("Click to edit, drag to drop the screenshot into another app")
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Screenshot thumbnail")
                .accessibilityAction { state.openEditor() }

            // Kept in the hierarchy while hidden so the share picker's anchor view stays alive
            // when the pointer leaves the panel to choose a service.
            hoverControls
                .opacity(state.isHovered ? 1 : 0)
                .allowsHitTesting(state.isHovered)
                .animation(.easeInOut(duration: 0.15), value: state.isHovered)
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
        .padding(FloatingThumbnailLayout.shadowPadding)
    }

    private var hoverControls: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.25), .clear, .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .allowsHitTesting(false)

            VStack {
                HStack {
                    ThumbnailControlButton(icon: "xmark", help: "Close without saving") {
                        state.close()
                    }
                    Spacer()
                }
                Spacer()
                HStack(spacing: 8) {
                    ThumbnailControlButton(icon: didCopy ? "checkmark" : "doc.on.doc", help: "Copy") {
                        state.copy()
                        didCopy = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            didCopy = false
                        }
                    }
                    ThumbnailControlButton(icon: "square.and.arrow.up", help: "Share") {
                        share()
                    }
                    .sharingAnchor(shareAnchor)
                    ThumbnailControlButton(icon: "pin", help: "Pin to screen") {
                        state.pin()
                    }
                    ThumbnailControlButton(icon: "square.and.arrow.down", help: "Save to Downloads") {
                        state.save()
                    }
                }
            }
            .padding(8)
        }
    }

    private func share() {
        // Keep the thumbnail up while the picker is open, even though the pointer leaves it.
        let hold = state.beginHold()
        guard let url = state.exportForSharing() else {
            state.endHold(hold)
            return
        }
        shareAnchor.showPicker(items: [url]) {
            state.endHold(hold)
        }
    }
}

private struct ThumbnailControlButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Color.accentColor.opacity(isHovered ? 0.8 : 0), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovered = $0 }
    }
}
