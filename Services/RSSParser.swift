import Foundation

struct RSSItem {
    var title: String = ""
    var description: String = ""
    var guid: String?
    var pubDate: Date?
}

enum RSSParseError: Error, LocalizedError {
    case malformed(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .malformed(let underlying):
            return underlying?.localizedDescription ?? "Malformed RSS/Atom feed"
        }
    }
}

class RSSStatusParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var items: [RSSItem] = []
    private var currentItem: RSSItem?
    private var currentElement = ""
    private var currentText = ""
    private var isInsideItem = false

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",      // RFC 822, numeric offset (+0000)
            "EEE, dd MMM yyyy HH:mm:ss zzz",    // RFC 822, named zone (PST, UTC) — AWS style
            "yyyy-MM-dd'T'HH:mm:ssZ",           // ISO 8601
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        ]
        return formats.map { fmt in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            return df
        }
    }()

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [RSSItem] {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse() else {
            throw RSSParseError.malformed(underlying: parser.parserError)
        }
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        currentText = ""

        if currentElement == "item" || currentElement == "entry" {
            isInsideItem = true
            currentItem = RSSItem()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    /// Status-page RSS feeds typically wrap descriptions in CDATA (they contain
    /// HTML). `XMLParser` delivers those here, NOT via `foundCharacters`.
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            currentText += text
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let el = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if isInsideItem {
            switch el {
            case "title": currentItem?.title = text
            case "description", "summary", "content": currentItem?.description = text
            case "guid", "id": currentItem?.guid = text
            case "pubdate", "published", "updated":
                for df in Self.dateFormatters {
                    if let date = df.date(from: text) {
                        currentItem?.pubDate = date
                        break
                    }
                }
            default: break
            }
        }

        if el == "item" || el == "entry" {
            if let item = currentItem {
                items.append(item)
            }
            isInsideItem = false
            currentItem = nil
        }
    }
}
