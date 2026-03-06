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
                HStack(spacing: LC.spacingSM) {
                    Text(extLabel.uppercased())
                        .font(LC.label(8))
                        .tracking(1)
                        .foregroundStyle(LC.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(LC.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))

                    Text(filename)
                        .font(LC.body(13))
                        .foregroundStyle(LC.primary)
                        .lineLimit(1)

                    Spacer()

                    if hasChanges {
                        Text("MODIFIED")
                            .font(LC.label(8))
                            .tracking(1)
                            .foregroundStyle(LC.accent)
                    }

                    Text("\(content.components(separatedBy: "\n").count) L")
                        .font(LC.caption(10))
                        .foregroundStyle(LC.secondary)
                }
                .padding(.horizontal, LC.spacingMD)
                .padding(.vertical, LC.spacingSM)
                .background(LC.surfaceElevated)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(LC.border).frame(height: LC.borderWidth)
                }

                // Editor
                if showLineNumbers {
                    numberedEditor
                } else {
                    plainEditor
                }
            }
            .background(LC.surface)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EDITOR")
                        .font(LC.label(12))
                        .tracking(2)
                        .foregroundStyle(LC.primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                        .font(LC.body(14))
                        .foregroundStyle(LC.secondary)
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
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundStyle(LC.secondary)
                    }

                    Button(action: {
                        onSave()
                        hasChanges = false
                        originalContent = content
                    }) {
                        Text("SAVE")
                            .font(LC.label(11))
                            .tracking(1)
                            .foregroundStyle(hasChanges ? LC.accent : LC.secondary)
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
            .background(LC.surface)
    }

    private var numberedEditor: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                // Line numbers
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(1...max(content.components(separatedBy: "\n").count, 1), id: \.self) { num in
                        Text("\(num)")
                            .font(.system(size: fontSize, design: .monospaced))
                            .foregroundStyle(LC.secondary.opacity(0.5))
                            .padding(.trailing, LC.spacingSM)
                    }
                }
                .padding(.vertical, LC.spacingSM)
                .frame(minWidth: 40)
                .background(LC.surfaceElevated)

                Rectangle().fill(LC.border).frame(width: LC.borderWidth)

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
        .background(LC.surface)
    }

    private var extLabel: String {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ext.isEmpty ? "txt" : ext
    }
}
