import SwiftUI

struct HistoryPanel: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Spacer()

                Text("\(appState.history.screenshotHistory.count) screenshots")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            if appState.history.screenshotHistory.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("No screenshots yet")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("Capture your first screenshot to see it here")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(appState.history.screenshotHistory) { item in
                            HistoryItemView(item: item)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 500, height: 500)
    }
}

struct HistoryItemView: View {
    let item: ScreenshotItem
    @Environment(AppState.self) var appState

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail
            Button {
                Task {
                    let path = item.filePath
                    let loaded = await Task.detached(priority: .userInitiated) { NSImage(contentsOfFile: path) }.value
                    if let image = loaded {
                        appState.pinnedImage = image
                        appState.showPinWindow = true
                    }
                }
            } label: {
                if let thumbnailData = item.thumbnail,
                   let nsImage = NSImage(data: thumbnailData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 80)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .buttonStyle(.plain)

            // Info
            VStack(spacing: 2) {
                Text(item.date, style: .date)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                Text(item.date, style: .time)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Actions
            HStack(spacing: 8) {
                ActionIconButton(icon: "doc.on.doc", tooltip: "Copy") {
                    Task {
                        let path = item.filePath
                        let loaded = await Task.detached(priority: .userInitiated) { NSImage(contentsOfFile: path) }.value
                        if let image = loaded {
                            appState.capture.screenCapture.copyToClipboard(image)
                        }
                    }
                }

                ActionIconButton(icon: "arrow.right.doc.on.clipboard", tooltip: "Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.filePath, forType: .string)
                }

                ActionIconButton(icon: "folder", tooltip: "Show in Finder") {
                    appState.capture.screenCapture.openInFinder(item.filePath)
                }

                ActionIconButton(icon: "trash", tooltip: "Delete") {
                    appState.history.deleteHistoryItem(item)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

struct ActionIconButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    HistoryPanel()
        .environment(AppState())
}
