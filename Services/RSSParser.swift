import Foundation

struct RSSItem {
    var title: String = ""
    var description: String = ""
    var guid: String?
    var pubDate: Date?
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
            "EEE, dd MMM yyyy HH:mm:ss Z",    // RFC 822
            "yyyy-MM-dd'T'HH:mm:ssZ",          // ISO 8601
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

    func parse() -> [RSSItem] {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        parser.parse()
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
                currentItem?.pubDate = Self.dateFormatters.compactMap { $0.date(from: text) }.first
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
