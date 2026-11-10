import SwiftUI

struct PinWindow: View {
    @Environment(AppState.self) var appState

    @State private var isHovering = false

    var body: some View {
        if let image = appState.pinnedImage {
            ZStack {
                // The panel itself provides the (opaque or clear) background.
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .shadow(
                        color: .black.opacity(appState.isTransparentBackground ? 0 : 0.3),
                        radius: 20, x: 0, y: 10
                    )

                // Floating toolbar
                VStack {
                    HStack {
                        Spacer()

                        // Only shown on hover so it doesn't cover small pinned images.
                        PinToolbarView()
                            .padding(.top, 8)
                            .padding(.trailing, 8)
                            .opacity(isHovering ? 1 : 0)
                            .allowsHitTesting(isHovering)
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .ignoresSafeArea()
        }
    }
}

struct PinToolbarView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 8) {
            // Transparency toggle
            Button {
                appState.isTransparentBackground.toggle()
            } label: {
                Image(systemName: appState.isTransparentBackground ? "square.dashed" : "square.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
            .buttonStyle(.plain)
            .help(appState.isTransparentBackground ? "Solid background" : "Transparent background")

            Divider()
                .frame(height: 16)

            // Copy
            Button {
                if let image = appState.pinnedImage {
                    appState.capture.screenCapture.copyToClipboard(image)
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")

            // Save
            Button {
                appState.savePinnedImage()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
            .buttonStyle(.plain)
            .disabled(appState.pinnedSourcePath != nil)
            .help(appState.pinnedSourcePath != nil ? "Already saved" : "Save to History Folder")

            // Open in Finder
            Button {
                appState.revealPinnedImage()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
            .buttonStyle(.plain)
            .help("Show in Finder")

            Divider()
                .frame(height: 16)

            // Close
            Button {
                appState.closePinnedImage()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
    }
}

#Preview {
    PinWindow()
        .environment(AppState())
}
