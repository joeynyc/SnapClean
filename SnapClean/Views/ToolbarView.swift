import SwiftUI

struct ToolbarView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var annotations = appState.annotations
        HStack(spacing: 8) {
            // Tool selector
            ToolPicker()

            Divider()
                .frame(height: 24)

            // Color picker
            ColorPickerButton(color: $annotations.selectedColor)

            Divider()
                .frame(height: 24)

            // Line width
            LineWidthPicker(width: $annotations.lineWidth)

            Divider()
                .frame(height: 24)

            // Undo/Redo
            HStack(spacing: 4) {
                ToolbarIconButton(icon: "arrow.uturn.backward", isEnabled: !appState.annotations.undoStack.isEmpty) {
                    appState.annotations.undo()
                }

                ToolbarIconButton(icon: "arrow.uturn.forward", isEnabled: !appState.annotations.redoStack.isEmpty) {
                    appState.annotations.redo()
                }
            }

            Divider()
                .frame(height: 24)

            // Clear
            ToolbarIconButton(icon: "trash", isEnabled: true) {
                appState.annotations.clearAnnotations()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct ToolPicker: View {
    @Environment(AppState.self) var appState

    var body: some View {
        Menu {
            ForEach(AnnotationTool.selectableTools) { tool in
                Button {
                    appState.annotations.selectedTool = tool
                } label: {
                    Label(tool.rawValue, systemImage: tool.icon)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: appState.annotations.selectedTool.icon)
                    .font(.system(size: 16, weight: .medium))
                Text(appState.annotations.selectedTool.rawValue)
                    .font(.system(size: 12, weight: .medium, design: .rounded))

                if #available(macOS 26, *) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.15))
            )
        }
        .menuStyle(.borderlessButton)
    }
}

struct ColorPickerButton: View {
    @Binding var color: Color

    var body: some View {
        Menu {
            ColorPicker("Stroke Color", selection: $color)
                .labelsHidden()
                .frame(width: 200, height: 150)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )

                if #available(macOS 26, *) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .menuStyle(.borderlessButton)
    }
}

struct LineWidthPicker: View {
    @Binding var width: CGFloat

    var body: some View {
        Menu {
            VStack(spacing: 12) {
                HStack {
                    Text("Size")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(width))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }

                Slider(value: $width, in: 1...20, step: 1)
                    .frame(width: 150)

                // Preview
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 50, height: width)
                        .clipShape(.rect(cornerRadius: width / 2))
                    Spacer()
                }
            }
            .padding(12)
        } label: {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 20, height: width)
                    .clipShape(.rect(cornerRadius: width / 2))

                if #available(macOS 26, *) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .menuStyle(.borderlessButton)
    }
}

struct ToolbarIconButton: View {
    let icon: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

#Preview {
    ToolbarView()
        .environment(AppState())
        .frame(height: 50)
}
