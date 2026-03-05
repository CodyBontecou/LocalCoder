import SwiftUI

struct CodeEditorView: View {
    let filename: String
    @Binding var content: String
    let onSave: () -> Void
    let onDismiss: () -> Void

    @State private var fontSize: CGFloat = 14
    @State private var showLineNumbers = true
    @State private var hasChanges = false
    @State private var originalContent = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // File info bar
                HStack {
                    Image(systemName: iconForExtension)
                        .foregroundStyle(colorForExtension)
                    Text(filename)
                        .font(.subheadline.monospaced().bold())
                    Spacer()
                    if hasChanges {
                        Text("Modified")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    Text("\(content.components(separatedBy: "\n").count) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)

                Divider()

                // Editor
                if showLineNumbers {
                    numberedEditor
                } else {
                    plainEditor
                }
            }
            .navigationTitle("Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Line Numbers", isOn: $showLineNumbers)

                        Menu("Font Size") {
                            Button("Small (12)") { fontSize = 12 }
                            Button("Medium (14)") { fontSize = 14 }
                            Button("Large (16)") { fontSize = 16 }
                        }

                        Button(action: { UIPasteboard.general.string = content }) {
                            Label("Copy All", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

                    Button(action: {
                        onSave()
                        hasChanges = false
                        originalContent = content
                    }) {
                        Text("Save")
                            .bold()
                    }
                    .disabled(!hasChanges)
                }
            }
            .onAppear {
                originalContent = content
            }
            .onChange(of: content) { _, newValue in
                hasChanges = newValue != originalContent
            }
        }
    }

    private var plainEditor: some View {
        TextEditor(text: $content)
            .font(.system(size: fontSize, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
    }

    private var numberedEditor: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                // Line numbers
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(1...max(content.components(separatedBy: "\n").count, 1), id: \.self) { num in
                        Text("\(num)")
                            .font(.system(size: fontSize, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.trailing, 8)
                    }
                }
                .padding(.vertical, 8)
                .frame(minWidth: 40)
                .background(Color(.systemGray6))

                Divider()

                // Code
                TextEditor(text: $content)
                    .font(.system(size: fontSize, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(minHeight: CGFloat(content.components(separatedBy: "\n").count) * (fontSize + 4) + 20)
            }
        }
    }

    private var iconForExtension: String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "text.page"
        case "js", "ts": return "j.square"
        case "html": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text"
        }
    }

    private var colorForExtension: Color {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "py": return .blue
        case "js": return .yellow
        case "ts": return .blue
        default: return .secondary
        }
    }
}
