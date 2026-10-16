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
                ToolbarIconButton(icon: "arrow.uturn.backward", isEnabled: appState.annotations.canUndo) {
                    appState.annotations.undo()
                }

                ToolbarIconButton(icon: "arrow.uturn.forward", isEnabled: appState.annotations.canRedo) {
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

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
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
    @State private var isPresented = false

    private static let presets: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .white, .black]

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Stroke Color")
        // NSMenu can't host a ColorPicker, so the choices live in a popover.
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 5), spacing: 8) {
                    ForEach(Self.presets, id: \.self) { preset in
                        Button {
                            color = preset
                            isPresented = false
                        } label: {
                            Circle()
                                .fill(preset)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                ColorPicker("Custom…", selection: $color)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .padding(12)
        }
    }
}

struct LineWidthPicker: View {
    @Binding var width: CGFloat
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 18, height: min(width, 10))
                Text("\(Int(width))")
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
            }
            .frame(height: 28)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Line Width")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 12) {
                HStack {
                    Text("Size")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(width))")
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))

                Slider(value: $width, in: 1...20, step: 1)
                    .frame(width: 160)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 60, height: width)
                    .frame(height: 20)
            }
            .padding(12)
        }
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
