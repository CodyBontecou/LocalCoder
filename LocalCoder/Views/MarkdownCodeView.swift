import SwiftUI

/// Renders text with inline code blocks that can be saved
struct MarkdownCodeView: View {
    let text: String
    let onSaveCode: (CodeBlock) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let content):
                    Text(content)
                        .font(.body)
                        .foregroundStyle(.primary)

                case .code(let block):
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        HStack {
                            Text(block.language.isEmpty ? "code" : block.language)
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(.green)

                            if let filename = block.filename {
                                Text("· \(filename)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(action: { copyToClipboard(block.code) }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }

                            Button(action: { onSaveCode(block) }) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray4))

                        // Code content
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(block.code)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(10)
                        }
                        .background(Color(.systemGray6))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                }
            }
        }
    }

    private enum Segment {
        case text(String)
        case code(CodeBlock)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(text)]
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        var lastEnd = 0

        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastEnd {
                let textContent = nsString.substring(with: NSRange(location: lastEnd, length: matchRange.location - lastEnd))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !textContent.isEmpty {
                    result.append(.text(textContent))
                }
            }

            let lang = match.range(at: 1).location != NSNotFound ? nsString.substring(with: match.range(at: 1)) : ""
            let code = match.range(at: 2).location != NSNotFound ? nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .newlines) : ""

            // Extract filename from first line comment
            var filename: String?
            let lines = code.components(separatedBy: "\n")
            if let first = lines.first {
                if first.hasPrefix("// ") && first.contains(".") {
                    filename = first.replacingOccurrences(of: "// ", with: "").trimmingCharacters(in: .whitespaces)
                }
            }

            result.append(.code(CodeBlock(language: lang, code: code, filename: filename)))
            lastEnd = matchRange.location + matchRange.length
        }

        if lastEnd < nsString.length {
            let remaining = nsString.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                result.append(.text(remaining))
            }
        }

        if result.isEmpty {
            result.append(.text(text))
        }

        return result
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }
}
