import Foundation

extension String {
    /// Strips HTML markup and decodes a handful of common entities. Podcast
    /// search results and RSS feeds routinely embed HTML (`<p>`, `<br>`,
    /// `&amp;`) in fields this app otherwise renders as plain text.
    var strippingHTML: String {
        guard contains("<") else { return decodingHTMLEntities() }
        let withoutTags = replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
        let collapsed = withoutTags.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return collapsed.decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodingHTMLEntities() -> String {
        guard contains("&") else { return self }
        var result = self
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&lt;", "<"), ("&gt;", ">")
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
