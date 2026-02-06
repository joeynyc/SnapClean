import SwiftUI

struct PinWindow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        if let image = appState.pinnedImage {
            ZStack {
                if appState.isTransparentBackground {
                    // Checkerboard pattern for transparency
                    CheckerboardPattern()
                        .ignoresSafeArea()

                    // Pinned image
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .offset(offset)
                } else {
                    // Solid background with shadow
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .offset(offset)
                }

                // Floating toolbar
                VStack {
                    HStack {
                        Spacer()

                        PinToolbarView()
                            .padding(.top, 8)
                            .padding(.trailing, 8)
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appState.isTransparentBackground ? Color.clear : Color(NSColor.windowBackgroundColor))
            .ignoresSafeArea()
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    EmptyView()
                }
            }
        }
    }
}

struct PinToolbarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            // Transparency toggle
            Button {
                appState.isTransparentBackground.toggle()
            } label: {
                Image(systemName: appState.isTransparentBackground ? "square.dashed" : "square.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
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
                    appState.screenCapture.copyToClipboard(image)
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
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
                if let image = appState.pinnedImage {
                    if let path = appState.screenCapture.saveImage(image, to: appState.historyManager.saveDirectory) {
                        appState.addToHistory(path: path, image: image)
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
            .buttonStyle(.plain)
            .help("Save to History Folder")

            // Open in Finder
            Button {
                if let image = appState.pinnedImage {
                    if let path = appState.screenCapture.saveImage(image, to: appState.historyManager.saveDirectory) {
                        appState.screenCapture.openInFinder(path)
                    }
                }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
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
                appState.showPinWindow = false
                appState.pinnedImage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
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

struct CheckerboardPattern: View {
    let size: CGFloat = 20

    var body: some View {
        Canvas { context, canvasSize in
            let columns = Int(canvasSize.width / size) + 1
            let rows = Int(canvasSize.height / size) + 1

            for row in 0..<rows {
                for col in 0..<columns {
                    let isLight = (row + col).isMultiple(of: 2)
                    let rect = CGRect(
                        x: CGFloat(col) * size,
                        y: CGFloat(row) * size,
                        width: size,
                        height: size
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? .gray.opacity(0.15) : .gray.opacity(0.25))
                    )
                }
            }
        }
    }
}

#Preview {
    PinWindow()
        .environmentObject(AppState())
}
