import SwiftUI

/// Renders text with inline code blocks — TE-inspired industrial style
struct MarkdownCodeView: View {
    let text: String
    let onSaveCode: (CodeBlock) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LC.spacingSM) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let content):
                    Text(content)
                        .font(LC.body(14))
                        .foregroundStyle(LC.primary)

                case .code(let block):
                    VStack(alignment: .leading, spacing: 0) {
                        // Header bar
                        HStack(spacing: LC.spacingSM) {
                            Text(block.language.isEmpty ? "CODE" : block.language.uppercased())
                                .font(LC.label(9))
                                .tracking(1.5)
                                .foregroundStyle(LC.accent)

                            if let filename = block.filename {
                                Rectangle()
                                    .fill(LC.border)
                                    .frame(width: 1, height: 12)
                                Text(filename)
                                    .font(LC.caption(10))
                                    .foregroundStyle(LC.secondary)
                            }

                            Spacer()

                            Button(action: { copyToClipboard(block.code) }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundStyle(LC.secondary)
                            }

                            Button(action: { onSaveCode(block) }) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundStyle(LC.secondary)
                            }
                        }
                        .padding(.horizontal, LC.spacingSM + 2)
                        .padding(.vertical, 6)
                        .background(LC.inverseSurface.opacity(0.06))

                        Rectangle().fill(LC.border).frame(height: LC.borderWidth)

                        // Code content
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(block.code)
                                .font(LC.code(12))
                                .foregroundStyle(LC.primary)
                                .padding(LC.spacingSM + 2)
                        }
                        .background(LC.surface)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
                    .overlay(
                        RoundedRectangle(cornerRadius: LC.radiusSM)
                            .stroke(LC.border, lineWidth: LC.borderWidth)
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
