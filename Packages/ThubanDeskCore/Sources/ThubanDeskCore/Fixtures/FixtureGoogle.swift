import Foundation

/// An in-process fake of the Google endpoints the app uses, backed by a `FixtureWorld`. Reads and reversible
/// writes (events, labels, drafts, filters) change the in-memory world so the UI can be exercised end to end;
/// SENDS ARE ALWAYS REFUSED (403). Any request outside the known Google APIs is refused too, so a session using
/// `FixtureURLProtocol` can never reach the network.
public final class FixtureGoogle: @unchecked Sendable {
    public struct Response: Sendable {
        public var status: Int
        public var body: Data
        public var headers: [String: String] = ["Content-Type": "application/json"]
    }

    private let lock = NSLock()
    private var world: FixtureWorld
    private var requestLog: [String] = []
    private var nextID = 1

    public init(world: FixtureWorld) {
        self.world = world
    }

    /// "METHOD path" for every request served (tests assert nothing unexpected happened).
    public var log: [String] { lock.withLock { requestLog } }
    public var snapshot: FixtureWorld { lock.withLock { world } }

    /// Replaces the fake's data (smoke scenes: an empty inbox / an empty day, then the original back).
    public func replaceWorld(_ newWorld: FixtureWorld) {
        lock.withLock { world = newWorld }
    }

    /// A URLSession whose every request is answered by this backend.
    public func makeSession() -> URLSession {
        FixtureURLProtocol.backend = self
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    // MARK: Dispatch

    public func handle(method: String, url: URL, headers: [String: String], body: Data?) -> Response {
        lock.lock()
        defer { lock.unlock() }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath ?? url.path
        requestLog.append("\(method) \(url.host ?? "")\(path)")
        let query = components?.queryItems ?? []
        let segments = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }

        if url.host == "oauth2.googleapis.com" { return token(body: body) }
        guard let account = account(from: headers) else { return error(401, "Missing or unknown fixture token") }
        switch url.host {
        case "www.googleapis.com" where segments.starts(with: ["calendar", "v3"]):
            return calendar(method: method, segments: Array(segments.dropFirst(2)), query: query, body: body, account: account)
        case "gmail.googleapis.com" where segments.starts(with: ["gmail", "v1", "users", "me"]):
            return gmail(method: method, segments: Array(segments.dropFirst(4)), query: query, body: body, account: account)
        default:
            return error(403, "Blocked by the fixture backend: \(url.host ?? "?")\(path)")
        }
    }

    private func account(from headers: [String: String]) -> String? {
        let auth = headers.first { $0.key.caseInsensitiveCompare("Authorization") == .orderedSame }?.value ?? ""
        let token = auth.replacingOccurrences(of: "Bearer ", with: "")
        guard token.hasPrefix("fixture-token-") else { return nil }
        let email = String(token.dropFirst("fixture-token-".count))
        return world.accounts.contains { $0.id == email } ? email : nil
    }

    private func token(body: Data?) -> Response {
        let form = String(decoding: body ?? Data(), as: UTF8.self)
        let pairs = Dictionary(form.split(separator: "&").map { pair -> (String, String) in
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            return (parts[0], parts.count > 1 ? parts[1] : "")
        }, uniquingKeysWith: { a, _ in a })
        guard pairs["grant_type"] == "refresh_token", let refresh = pairs["refresh_token"], refresh.hasPrefix("fixture-refresh-") else {
            return Response(status: 400, body: Data(#"{"error":"invalid_grant","error_description":"Fixture backend: unknown grant"}"#.utf8))
        }
        let email = String(refresh.dropFirst("fixture-refresh-".count))
        return json(["access_token": SampleData.accessToken(for: email), "expires_in": 3599, "token_type": "Bearer"] as [String: Any])
    }

    // MARK: Calendar

    private func calendar(method: String, segments: [String], query: [URLQueryItem], body: Data?, account: String) -> Response {
        func q(_ name: String) -> String? { query.first { $0.name == name }?.value }
        switch (method, segments.count) {
        case ("GET", 3) where segments == ["users", "me", "calendarList"]:
            return encode(CalendarListPageBody(items: world.calendars[account] ?? []))
        case ("POST", 1) where segments[0] == "calendars":
            guard let new = decode(NewCalendar.self, body) else { return error(400, "Bad calendar") }
            let id = "created-\(nextID)@fixture"
            nextID += 1
            world.calendars[account, default: []].append(CalendarListEntry(id: id, summary: new.summary, timeZone: new.timeZone, backgroundColor: "#9fc6e7"))
            return encode(CalendarResource(id: id, summary: new.summary, timeZone: new.timeZone))
        default: break
        }
        guard segments.count >= 3, segments[0] == "calendars", segments[2] == "events" else { return error(404, "Not found") }
        let calendarID = segments[1]
        guard world.calendars[account]?.contains(where: { $0.id == calendarID }) == true else { return error(404, "Calendar not found") }
        let zone = world.zone
        switch (method, segments.count) {
        case ("GET", 3):
            let from = q("timeMin").flatMap(RFC3339.date(from:)) ?? .distantPast
            let to = q("timeMax").flatMap(RFC3339.date(from:)) ?? .distantFuture
            let single = q("singleEvents") == "true"
            var items = listEvents(account: account, calendarID: calendarID, from: from, to: to, single: single)
            if let text = q("q")?.lowercased(), !text.isEmpty {
                items = items.filter { [$0.summary, $0.description, $0.location].compactMap { $0?.lowercased() }.contains { $0.contains(text) } }
            }
            return encode(EventsPageBody(items: items, timeZone: zone.identifier))
        case ("POST", 3):
            guard var event = decode(CalendarEvent.self, body) else { return error(400, "Bad event") }
            event.id = "evt\(nextID)"
            nextID += 1
            event.iCalUID = "\(event.id)@fixture.thuban"
            event.created = world.now
            event.updated = world.now
            if event.organizer == nil { event.organizer = EventPerson(email: account, isSelf: true) }
            world.events[account, default: [:]][calendarID, default: []].append(event)
            return encode(event)
        case (_, 4):
            let eventID = segments[3]
            switch method {
            case "GET":
                if let stored = stored(account, calendarID, eventID), !stored.isCancelled { return encode(stored) }
                if let instance = generatedInstance(account, calendarID, eventID) { return encode(instance) }
                return error(404, "Not Found")
            case "PATCH", "PUT":
                guard let patch = decode(EventPatch.self, body) else { return error(400, "Bad patch") }
                guard var event = stored(account, calendarID, eventID) ?? generatedInstance(account, calendarID, eventID) else { return error(404, "Not Found") }
                event = patch.applyingFields(to: event)
                if let start = patch.start { event.start = start }
                if let end = patch.end { event.end = end }
                if let recurrence = patch.recurrence { event.recurrence = recurrence.isEmpty ? nil : recurrence }
                event.updated = world.now
                event.sequence = (event.sequence ?? 0) + 1
                upsert(account, calendarID, event)
                return encode(event)
            case "DELETE":
                if var event = stored(account, calendarID, eventID) {
                    if event.recurringEventId != nil {
                        event.status = "cancelled"
                        upsert(account, calendarID, event)
                    } else {
                        world.events[account]?[calendarID]?.removeAll { $0.id == eventID || $0.recurringEventId == eventID }
                    }
                    return Response(status: 204, body: Data())
                }
                if var instance = generatedInstance(account, calendarID, eventID) {
                    instance.status = "cancelled"
                    upsert(account, calendarID, instance)
                    return Response(status: 204, body: Data())
                }
                return error(410, "Resource has been deleted")
            default: return error(405, "Method not allowed")
            }
        case ("GET", 5) where segments[4] == "instances":
            guard let master = stored(account, calendarID, segments[3]), master.isRecurringMaster else { return error(404, "Not Found") }
            let from = q("timeMin").flatMap(RFC3339.date(from:)) ?? master.startDate(in: zone)
            let to = q("timeMax").flatMap(RFC3339.date(from:)) ?? from.addingTimeInterval(400 * 86_400)
            return encode(EventsPageBody(items: expand(master, account: account, calendarID: calendarID, from: from, to: to), timeZone: zone.identifier))
        default:
            return error(404, "Not found")
        }
    }

    private func stored(_ account: String, _ calendarID: String, _ id: String) -> CalendarEvent? {
        world.events[account]?[calendarID]?.first { $0.id == id }
    }

    private func upsert(_ account: String, _ calendarID: String, _ event: CalendarEvent) {
        var list = world.events[account]?[calendarID] ?? []
        if let index = list.firstIndex(where: { $0.id == event.id }) { list[index] = event } else { list.append(event) }
        world.events[account, default: [:]][calendarID] = list
    }

    /// An instance id `master_20260924T110000Z` / `master_20260924` not stored as an exception.
    private func generatedInstance(_ account: String, _ calendarID: String, _ id: String) -> CalendarEvent? {
        guard let underscore = id.lastIndex(of: "_") else { return nil }
        let masterID = String(id[..<underscore])
        let stamp = String(id[id.index(after: underscore)...])
        guard let master = stored(account, calendarID, masterID), master.isRecurringMaster else { return nil }
        let zone = master.start.zone ?? world.zone
        let start: Date
        if stamp.count == 8, let day = CivilDate(string: stamp) { start = day.startDate(in: zone) } else if let instant = RRule.parseStamp(stamp, zone: zone) { start = instant } else { return nil }
        return expand(master, account: account, calendarID: calendarID, from: start, to: start.addingTimeInterval(1), includeCancelled: true).first { $0.id == id }
    }

    private func listEvents(account: String, calendarID: String, from: Date, to: Date, single: Bool) -> [CalendarEvent] {
        let zone = world.zone
        let events = world.events[account]?[calendarID] ?? []
        var result: [CalendarEvent] = []
        for event in events {
            if event.isRecurringMaster {
                if single { result += expand(event, account: account, calendarID: calendarID, from: from, to: to) } else { result.append(event) }
            } else if event.recurringEventId == nil || !single {
                guard !event.isCancelled || !single else { continue }
                if event.startDate(in: zone) < to && event.endDate(in: zone) > from { result.append(event) }
            }
        }
        return result.sorted { $0.startDate(in: zone) < $1.startDate(in: zone) }
    }

    /// Instances of `master` overlapping `[from, to)`, with stored exceptions (modified / cancelled) applied.
    private func expand(_ master: CalendarEvent, account: String, calendarID: String, from: Date, to: Date, includeCancelled: Bool = false) -> [CalendarEvent] {
        guard let rule = master.rrule else { return [] }
        let zone = master.start.zone ?? world.zone
        let set = RecurrenceSet(lines: master.recurrence ?? [])
        let duration = master.endDate(in: zone).timeIntervalSince(master.startDate(in: zone))
        let exceptions = (world.events[account]?[calendarID] ?? []).filter { $0.recurringEventId == master.id }
        var result: [CalendarEvent] = []
        let starts = rule.occurrences(start: master.startDate(in: zone), zone: zone, isAllDay: master.isAllDay, until: to,
                                      excluding: set.exclusions(defaultZone: zone), limit: 5000)
        for start in starts {
            var instance = master
            instance.recurrence = nil
            instance.recurringEventId = master.id
            if master.isAllDay {
                let day = CivilDate(start, in: zone)
                instance.id = "\(master.id)_\(day.compact)"
                instance.originalStartTime = .allDay(day)
                instance.start = .allDay(day)
                instance.end = .allDay(day.adding(days: max(1, (master.start.date ?? day).days(to: master.end.date ?? day.adding(days: 1)))))
            } else {
                instance.id = "\(master.id)_\(RRule.utcStamp(start))"
                instance.originalStartTime = .timed(start, timeZone: master.start.timeZone)
                instance.start = .timed(start, timeZone: master.start.timeZone)
                instance.end = .timed(start.addingTimeInterval(duration), timeZone: master.end.timeZone)
            }
            if let exception = exceptions.first(where: { $0.originalStartTime?.instant(in: zone) == instance.originalStartTime?.instant(in: zone) }) {
                instance = exception
            }
            if instance.isCancelled && !includeCancelled { continue }
            if instance.endDate(in: zone) > from && instance.startDate(in: zone) < to { result.append(instance) }
        }
        return result
    }

    // MARK: Gmail

    private func gmail(method: String, segments: [String], query: [URLQueryItem], body: Data?, account: String) -> Response {
        func q(_ name: String) -> String? { query.first { $0.name == name }?.value }
        let path = segments.joined(separator: "/")
        switch (method, segments.first ?? "") {
        case ("GET", "profile"):
            return encode(GmailProfile(emailAddress: account, messagesTotal: nil, threadsTotal: world.threads[account]?.count, historyId: "1"))
        case ("GET", "labels"):
            return encode(LabelsBody(labels: labelsWithCounts(account)))
        case ("POST", "labels"):
            guard let new = decode(NewLabel.self, body) else { return error(400, "Bad label") }
            if world.labels[account]?.contains(where: { $0.name.caseInsensitiveCompare(new.name) == .orderedSame }) == true { return error(409, "Label name exists or conflicts") }
            let label = GmailLabel(id: "Label_\(nextID)", name: new.name, color: new.color)
            nextID += 1
            world.labels[account, default: []].append(label)
            return encode(label)
        case ("GET", "threads") where segments.count == 1:
            let labelIDs = query.filter { $0.name == "labelIds" }.compactMap(\.value)
            let includeSpamTrash = q("includeSpamTrash") == "true"
            var threads = (world.threads[account] ?? []).filter { thread in
                let labels = Set((thread.messages ?? []).flatMap { $0.labelIds ?? [] })
                if !labelIDs.allSatisfy(labels.contains) { return false }
                if !includeSpamTrash, !labelIDs.contains(GmailSystemLabel.spam), !labelIDs.contains(GmailSystemLabel.trash),
                   !labels.isDisjoint(with: [GmailSystemLabel.spam, GmailSystemLabel.trash]) { return false }
                return matches(thread, query: q("q"))
            }
            threads.sort { lastDate($0) > lastDate($1) }
            let offset = Int(q("pageToken") ?? "") ?? 0
            let size = Int(q("maxResults") ?? "") ?? 100
            let page = Array(threads.dropFirst(offset).prefix(size))
            let next = offset + size < threads.count ? String(offset + size) : nil
            return encode(ThreadListBody(threads: page.map { GmailThreadRef(id: $0.id, snippet: $0.messages?.last?.snippet, historyId: $0.historyId) },
                                         nextPageToken: next, resultSizeEstimate: threads.count))
        case (_, "threads"):
            guard segments.count >= 2, let index = world.threads[account]?.firstIndex(where: { $0.id == segments[1] }) else { return error(404, "Requested entity was not found.") }
            if method == "GET" {
                var thread = world.threads[account]![index]
                if q("format") == "metadata" {
                    thread.messages = thread.messages?.map { message in
                        var copy = message
                        copy.payload = GmailMessagePart(partId: "", mimeType: message.payload?.mimeType, filename: "", headers: message.payload?.headers ?? [],
                                                        body: .init(size: 0))
                        return copy
                    }
                }
                return encode(thread)
            }
            if method == "DELETE" {
                world.threads[account]!.remove(at: index)
                return Response(status: 204, body: Data())
            }
            let action = segments.count > 2 ? segments[2] : ""
            var add: [String] = [], remove: [String] = []
            switch action {
            case "modify":
                guard let change = decode(ModifyBody.self, body) else { return error(400, "Bad modify") }
                add = change.addLabelIds ?? []
                remove = change.removeLabelIds ?? []
            case "trash": add = [GmailSystemLabel.trash]
            case "untrash": remove = [GmailSystemLabel.trash]
            default: return error(404, "Not found")
            }
            var thread = world.threads[account]![index]
            thread.messages = thread.messages?.map { message in
                var copy = message
                var labels = Set(copy.labelIds ?? [])
                labels.subtract(remove)
                labels.formUnion(add)
                copy.labelIds = labels.sorted()
                return copy
            }
            world.threads[account]![index] = thread
            return encode(thread)
        case ("POST", "messages") where path == "messages/send":
            return error(403, "Sending is disabled in fixture mode.")
        case ("POST", "messages") where path == "messages/batchModify":
            guard let change = decode(BatchBody.self, body) else { return error(400, "Bad batch") }
            for (t, thread) in (world.threads[account] ?? []).enumerated() {
                world.threads[account]![t].messages = thread.messages?.map { message in
                    guard change.ids.contains(message.id) else { return message }
                    var copy = message
                    var labels = Set(copy.labelIds ?? [])
                    labels.subtract(change.removeLabelIds ?? [])
                    labels.formUnion(change.addLabelIds ?? [])
                    copy.labelIds = labels.sorted()
                    return copy
                }
            }
            return Response(status: 204, body: Data())
        case ("GET", "messages"):
            guard segments.count >= 2, let message = allMessages(account).first(where: { $0.id == segments[1] }) else { return error(404, "Not found") }
            if segments.count == 4, segments[2] == "attachments" {
                let part = message.payload.map(findAttachment(id: segments[3])) ?? nil
                return encode(AttachmentBody(size: part?.body?.size, data: part?.body?.data ?? ""))
            }
            return encode(message)
        case ("POST", "drafts") where path == "drafts/send":
            return error(403, "Sending is disabled in fixture mode.")
        case ("GET", "drafts"):
            let drafts = allMessages(account).filter { $0.labelIds?.contains(GmailSystemLabel.draft) == true }
                .map { GmailDraft(id: "d-" + $0.id, message: GmailMessage(id: $0.id, threadId: $0.threadId, labelIds: $0.labelIds)) }
            return encode(DraftListBody(drafts: drafts))
        case ("POST", "drafts"), ("PUT", "drafts"):
            guard let draft = decode(DraftBody.self, body), let raw = Base64URL.decode(draft.message.raw) else { return error(400, "Bad draft") }
            let messageID = method == "PUT" && segments.count > 1 ? String(segments[1].dropFirst(2)) : "m\(nextID)"
            nextID += 1
            let threadID = draft.message.threadId ?? "thread-\(messageID)"
            let mime = MIMEParser.parse(raw)
            let message = GmailMessage(id: messageID, threadId: threadID, labelIds: [GmailSystemLabel.draft],
                                       snippet: String(HTMLSanitizer.plainText(MIMEContent.extract(mime).text ?? "").prefix(120)),
                                       internalDate: String(Int64(world.now.timeIntervalSince1970 * 1000)), payload: GmailMessagePart(mime: mime))
            var threads = world.threads[account] ?? []
            for t in threads.indices { threads[t].messages?.removeAll { $0.id == messageID } }
            if let t = threads.firstIndex(where: { $0.id == threadID }) {
                threads[t].messages = (threads[t].messages ?? []) + [message]
            } else {
                threads.append(GmailThread(id: threadID, historyId: "1", snippet: nil, messages: [message]))
            }
            world.threads[account] = threads
            return encode(GmailDraft(id: "d-" + messageID, message: GmailMessage(id: messageID, threadId: threadID, labelIds: [GmailSystemLabel.draft])))
        case ("DELETE", "drafts"):
            guard segments.count > 1 else { return error(404, "Not found") }
            let messageID = String(segments[1].dropFirst(2))
            var threads = world.threads[account] ?? []
            for t in threads.indices { threads[t].messages?.removeAll { $0.id == messageID } }
            world.threads[account] = threads.filter { !($0.messages ?? []).isEmpty }
            return Response(status: 204, body: Data())
        case ("GET", "settings") where path == "settings/filters":
            return encode(FiltersBody(filter: world.filters[account] ?? []))
        case ("POST", "settings") where path == "settings/filters":
            guard var filter = decode(GmailFilter.self, body) else { return error(400, "Bad filter") }
            filter.id = "f\(nextID)"
            nextID += 1
            world.filters[account, default: []].append(filter)
            return encode(filter)
        case ("DELETE", "settings") where segments.count == 3 && segments[1] == "filters":
            world.filters[account]?.removeAll { $0.id == segments[2] }
            return Response(status: 204, body: Data())
        case ("GET", "settings") where path == "settings/sendAs":
            return encode(SendAsBody(sendAs: world.sendAs[account] ?? []))
        default:
            return error(404, "Not found: \(method) \(path)")
        }
    }

    private func allMessages(_ account: String) -> [GmailMessage] { (world.threads[account] ?? []).flatMap { $0.messages ?? [] } }

    private func lastDate(_ thread: GmailThread) -> Date { thread.messages?.compactMap(\.date).max() ?? .distantPast }

    private func labelsWithCounts(_ account: String) -> [GmailLabel] {
        let threads = world.threads[account] ?? []
        return (world.labels[account] ?? []).map { label in
            var copy = label
            let containing = threads.filter { ($0.messages ?? []).contains { $0.labelIds?.contains(label.id) == true } }
            copy.threadsTotal = containing.count
            copy.threadsUnread = containing.filter { ($0.messages ?? []).contains { $0.labelIds?.contains(GmailSystemLabel.unread) == true } }.count
            return copy
        }
    }

    /// Supports the query terms the app builds: in:/-in:<label>, is:unread/starred, from:, label:, plain words.
    private func matches(_ thread: GmailThread, query: String?) -> Bool {
        guard let query, !query.isEmpty else { return true }
        let messages = thread.messages ?? []
        let labels = Set(messages.flatMap { $0.labelIds ?? [] })
        let mail = MailThread(account: "", thread)
        let haystack = ([mail.subject] + mail.messages.map { "\($0.from?.description ?? "") \($0.snippet) \($0.plainBody)" }).joined(separator: " ").lowercased()
        for rawTerm in query.split(separator: " ").map(String.init) {
            let negated = rawTerm.hasPrefix("-")
            let term = negated ? String(rawTerm.dropFirst()) : rawTerm
            var hit: Bool
            if term.hasPrefix("in:") {
                let name = String(term.dropFirst(3)).uppercased()
                let map = ["INBOX": "INBOX", "SPAM": "SPAM", "TRASH": "TRASH", "DRAFTS": "DRAFT", "SENT": "SENT", "CHATS": "CHAT"]
                hit = labels.contains(map[name] ?? name)
            } else if term.hasPrefix("newer_than:") || term.hasPrefix("older_than:") {
                let days = Double(term.split(separator: ":").last?.dropLast() ?? "") ?? 0
                let cutoff = world.now.addingTimeInterval(-days * 86_400)
                hit = term.hasPrefix("newer_than:") ? lastDate(thread) >= cutoff : lastDate(thread) < cutoff
            } else if term == "is:unread" {
                hit = labels.contains(GmailSystemLabel.unread)
            } else if term == "is:starred" {
                hit = labels.contains(GmailSystemLabel.starred)
            } else if term.hasPrefix("from:") {
                let who = term.dropFirst(5).lowercased()
                hit = mail.messages.contains { ($0.from?.description.lowercased() ?? "").contains(who) }
            } else {
                hit = haystack.contains(term.lowercased())
            }
            if hit == negated { return false }
        }
        return true
    }

    private func findAttachment(id: String) -> (GmailMessagePart) -> GmailMessagePart? {
        { part in
            if part.body?.attachmentId == id { return part }
            for child in part.parts ?? [] { if let hit = self.findAttachment(id: id)(child) { return hit } }
            return nil
        }
    }

    // MARK: Encoding

    private func encode<T: Encodable>(_ value: T) -> Response {
        Response(status: 200, body: (try? GoogleJSON.encoder.encode(value)) ?? Data("{}".utf8))
    }

    private func json(_ object: [String: Any]) -> Response {
        Response(status: 200, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }

    private func decode<T: Decodable>(_ type: T.Type, _ body: Data?) -> T? {
        guard let body else { return nil }
        return try? GoogleJSON.decoder.decode(T.self, from: body)
    }

    private func error(_ status: Int, _ message: String) -> Response {
        let body = ["error": ["code": status, "message": message, "errors": [["reason": status == 403 ? "forbidden" : "notFound", "message": message]]] as [String: Any]]
        return Response(status: status, body: (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
    }

    struct CalendarListPageBody: Encodable { var items: [CalendarListEntry] }
    struct EventsPageBody: Encodable { var items: [CalendarEvent]; var timeZone: String }
    struct LabelsBody: Encodable { var labels: [GmailLabel] }
    struct ThreadListBody: Encodable { var threads: [GmailThreadRef]; var nextPageToken: String?; var resultSizeEstimate: Int }
    struct ModifyBody: Decodable { var addLabelIds: [String]?; var removeLabelIds: [String]? }
    struct BatchBody: Decodable { var ids: [String]; var addLabelIds: [String]?; var removeLabelIds: [String]? }
    struct DraftBody: Decodable { struct Message: Decodable { var raw: String; var threadId: String? }; var message: Message }
    struct DraftListBody: Encodable { var drafts: [GmailDraft] }
    struct FiltersBody: Encodable { var filter: [GmailFilter] }
    struct SendAsBody: Encodable { var sendAs: [GmailSendAs] }
    struct AttachmentBody: Encodable { var size: Int?; var data: String }
}

/// Routes every request of a session to `FixtureURLProtocol.backend` (nothing reaches the network).
public final class FixtureURLProtocol: URLProtocol {
    nonisolated(unsafe) public static var backend: FixtureGoogle?

    override public class func canInit(with request: URLRequest) -> Bool { true }
    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        guard let url = request.url else { return }
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let response: FixtureGoogle.Response
        if let backend = Self.backend {
            response = backend.handle(method: request.httpMethod ?? "GET", url: url, headers: request.allHTTPHeaderFields ?? [:], body: body)
        } else {
            response = FixtureGoogle.Response(status: 503, body: Data(#"{"error":{"code":503,"message":"No fixture backend"}}"#.utf8))
        }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override public func stopLoading() {}

    static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Writes a fixture home (credentials for the sample accounts, settings with one hidden calendar and one pin) so
/// the app starts signed in against `FixtureGoogle`. Used by smoke and by fixture mode on first launch.
public enum FixtureSeeder {
    public static func seed(world: FixtureWorld, credentialsURL: URL = AppPaths.credentialsFile, settingsURL: URL = AppPaths.settingsFile) throws {
        try CredentialStore.save(CredentialsFile(client: world.client, accounts: world.accounts), to: credentialsURL)
        if !FileManager.default.fileExists(atPath: settingsURL.path) {
            var settings = AppSettings()
            settings.hiddenCalendars = [CalendarKey(account: SampleData.primaryEmail, calendarID: SampleData.holidaysCalendarID)]
            settings.setPinned(true, ThreadKey(account: SampleData.primaryEmail, threadID: "t1"))
            try JSONFile.write(settings, to: settingsURL)
        }
    }
}
