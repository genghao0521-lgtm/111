import SwiftUI
import WebKit

struct MathMarkdownWebView: UIViewRepresentable {
    let markdown: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInset = .zero
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(MarkdownHTMLRenderer.html(from: markdown), baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var height: CGFloat

        init(height: Binding<CGFloat>) {
            _height = height
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { result, _ in
                let measured: CGFloat
                if let value = result as? CGFloat {
                    measured = value
                } else if let value = result as? Double {
                    measured = CGFloat(value)
                } else if let value = result as? NSNumber {
                    measured = CGFloat(truncating: value)
                } else if let value = result as? Int {
                    measured = CGFloat(value)
                } else {
                    measured = 80
                }
                DispatchQueue.main.async {
                    self.height = max(measured, 56)
                }
            }
        }
    }
}

enum MarkdownHTMLRenderer {
    static func html(from markdown: String) -> String {
        let body = renderBlocks(markdown)
        return #"""
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
:root {
  color-scheme: light;
  --text: #1f2328;
  --muted: #68707c;
  --line: #d9dee7;
  --soft: #f7f8fb;
}
html, body {
  margin: 0;
  padding: 0;
  background: transparent;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
  font-size: 15px;
  line-height: 1.55;
  color: var(--text);
}
body { overflow: hidden; }
p { margin: 0 0 12px; }
h3 {
  margin: 14px 0 8px;
  font-size: 16px;
  font-weight: 700;
}
blockquote {
  margin: 8px 0 12px;
  padding: 8px 10px;
  border-left: 3px solid #8fb7ff;
  color: var(--muted);
  background: var(--soft);
  border-radius: 6px;
}
table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  margin: 10px 0 14px;
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 8px;
  font-size: 14px;
}
th, td {
  padding: 8px 10px;
  text-align: left;
  border-bottom: 1px solid var(--line);
  border-right: 1px solid var(--line);
}
th {
  background: #f2f4f8;
  font-weight: 650;
}
tr:last-child td { border-bottom: none; }
th:last-child, td:last-child { border-right: none; }
code {
  font-family: "SF Mono", Menlo, monospace;
  background: #f2f4f8;
  padding: 1px 4px;
  border-radius: 4px;
}
.MathJax { font-size: 112% !important; }
</style>
<script>
window.MathJax = {
  tex: {
    inlineMath: [['\\(', '\\)'], ['$', '$']],
    displayMath: [['\\[', '\\]']]
  },
  svg: { fontCache: 'global' }
};
</script>
<script defer src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js"></script>
</head>
<body>
\#(body)
</body>
</html>
"""#
    }

    private static func renderBlocks(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                index += 1
                continue
            }

            if isTableStart(lines, index) {
                let table = renderTable(lines, start: index)
                output.append(table.html)
                index = table.nextIndex
                continue
            }

            if line.hasPrefix("### ") {
                output.append("<h3>\(formatInline(String(line.dropFirst(4))))</h3>")
                index += 1
                continue
            }

            if line.hasPrefix("> ") {
                output.append("<blockquote>\(formatInline(String(line.dropFirst(2))))</blockquote>")
                index += 1
                continue
            }

            var paragraph = line
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("### ") || next.hasPrefix("> ") || isTableStart(lines, index) {
                    break
                }
                paragraph += "\n" + next
                index += 1
            }
            output.append("<p>\(formatInline(paragraph).replacingOccurrences(of: "\n", with: "<br>"))</p>")
        }

        return output.joined(separator: "\n")
    }

    private static func isTableStart(_ lines: [String], _ index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        return splitRow(lines[index]).count > 1 && isSeparatorRow(lines[index + 1])
    }

    private static func renderTable(_ lines: [String], start: Int) -> (html: String, nextIndex: Int) {
        let headers = splitRow(lines[start])
        var html = "<table><thead><tr>"
        for header in headers {
            html += "<th>\(formatInline(header))</th>"
        }
        html += "</tr></thead><tbody>"

        var index = start + 2
        while index < lines.count {
            let cells = splitRow(lines[index])
            if cells.count <= 1 { break }
            html += "<tr>"
            for cell in cells {
                html += "<td>\(formatInline(cell))</td>"
            }
            html += "</tr>"
            index += 1
        }

        html += "</tbody></table>"
        return (html, index)
    }

    private static func splitRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let cells = splitRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let cleaned = cell
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces)
            return cleaned.isEmpty
        }
    }

    private static func formatInline(_ text: String) -> String {
        escapeHTML(text)
            .replacingOccurrences(of: "`", with: "")
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
