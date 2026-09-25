import Foundation

/// The title-bar search across Mail and Calendar ("Search Mail and Events"): which loaded events match a query,
/// and in what order. Mail is searched by Gmail itself (`q=`); events are matched locally over the cached months.
public enum SearchMatch {
    /// True when every word of `query` appears (case- and diacritic-insensitive) in the event's title, location,
    /// description (as plain text), or a guest's / organizer's name or address.
    public static func matches(_ event: CalendarEvent, query: String) -> Bool {
        let terms = words(query)
        guard !terms.isEmpty else { return false }
        var fields = [event.title, event.location ?? "", HTMLSanitizer.plainText(event.description)]
        for attendee in event.attendees ?? [] {
            fields.append(attendee.email)
            if let name = attendee.displayName { fields.append(name) }
        }
        if let organizer = event.organizer {
            fields.append(organizer.email ?? "")
            fields.append(organizer.displayName ?? "")
        }
        let haystack = fold(fields.joined(separator: " "))
        return terms.allSatisfy { haystack.contains($0) }
    }

    /// Matching events, one per recurring series (its next occurrence from `now`, else its latest), upcoming first
    /// (soonest first), then past ones (most recent first); cancelled events are skipped.
    public static func events(_ items: [AgendaEvent], query: String, now: Date, zone: TimeZone, limit: Int = 20) -> [AgendaEvent] {
        let hits = items.filter { !$0.event.isCancelled && matches($0.event, query: query) }
        var bySeries: [String: AgendaEvent] = [:]
        for item in hits {
            let key = "\(item.calendar)|\(item.event.seriesID)"
            guard let existing = bySeries[key] else { bySeries[key] = item; continue }
            if better(item, than: existing, now: now, zone: zone) { bySeries[key] = item }
        }
        let upcoming = bySeries.values.filter { $0.end(in: zone) > now }.sorted { $0.start(in: zone) < $1.start(in: zone) }
        let past = bySeries.values.filter { $0.end(in: zone) <= now }.sorted { $0.start(in: zone) > $1.start(in: zone) }
        return Array((upcoming + past).prefix(limit))
    }

    private static func better(_ a: AgendaEvent, than b: AgendaEvent, now: Date, zone: TimeZone) -> Bool {
        let aUp = a.end(in: zone) > now, bUp = b.end(in: zone) > now
        if aUp != bUp { return aUp }
        return aUp ? a.start(in: zone) < b.start(in: zone) : a.start(in: zone) > b.start(in: zone)
    }

    static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
    }
}
