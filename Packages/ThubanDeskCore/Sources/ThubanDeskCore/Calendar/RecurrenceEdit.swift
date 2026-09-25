import Foundation

/// Which events of a repeating series an edit or delete applies to (design: "Change a repeating event").
public enum RecurrenceScope: Hashable, Sendable {
    /// Only the clicked occurrence (patch / delete the instance).
    case thisEvent
    /// Every occurrence on this weekday from this one on ("Every Thursday like this"); the other weekdays keep their
    /// times. Only offered for weekly rules with two or more BYDAY days.
    case everyWeekday(Weekday)
    /// This occurrence and every later one: the master is truncated with UNTIL and a new series starts here.
    case thisAndFollowing
    /// The whole series, past occurrences included (patch / delete the master).
    case allEvents

    public var title: String {
        switch self {
        case .thisEvent: return "Only this event"
        case .everyWeekday(let day): return "Every \(day.name) like this"
        case .thisAndFollowing: return "This and following events"
        case .allEvents: return "All events"
        }
    }
}

/// One API call a plan needs. `CalendarAPI.perform(_:)` executes it; tests inspect it.
public enum CalendarMutation: Hashable, Sendable {
    case insert(calendarID: String, event: CalendarEvent)
    case patch(calendarID: String, eventID: String, patch: EventPatch)
    case delete(calendarID: String, eventID: String)

    public var calendarID: String {
        switch self {
        case .insert(let id, _), .patch(let id, _, _), .delete(let id, _): return id
        }
    }
}

public enum RecurrenceEditError: Error, Equatable, Sendable {
    case notRecurring
    case scopeUnavailable
}

/// Pure planning for edits to repeating events: given the recurring master, the clicked instance (as listed with
/// `singleEvents=true`) and the change, returns the insert / patch / delete calls that realise the chosen scope.
/// No network. `zone` is the calendar's zone, used when the master carries no `timeZone`.
///
/// - thisEvent: patch the instance id (delete: delete the instance, which cancels that occurrence).
/// - everyWeekday(w): the master keeps every occurrence before this one (UNTIL just before it) and two series carry
///   on from here — the other weekdays unchanged, and weekday `w` with the edit. When nothing precedes this
///   occurrence the master itself becomes the "other weekdays" series (BYDAY minus `w`). Delete drops the `w` series.
/// - thisAndFollowing: truncate the master (UNTIL, COUNT reduced to what already happened) and insert a new series
///   from this occurrence with the edit; on the first occurrence this is the same as allEvents.
/// - allEvents: patch the master (a moved time shifts the master's start by the same wall-clock offset and moves
///   BYDAY weekdays by the same number of days). Delete removes the master.
public enum RecurrenceEditPlanner {
    // MARK: Scopes

    /// The scopes to offer for this instance. Empty when the event does not repeat (edit it directly).
    /// `changingRecurrence`: the editor changed the Repeat rule — only thisAndFollowing / allEvents make sense.
    public static func scopes(master: CalendarEvent?, instance: CalendarEvent, zone: TimeZone = .current,
                              changingRecurrence: Bool = false) -> [RecurrenceScope] {
        guard let master, instance.isRecurringInstance || master.id == instance.id, let rule = master.rrule else { return [] }
        if changingRecurrence { return [.thisAndFollowing, .allEvents] }
        var scopes: [RecurrenceScope] = [.thisEvent]
        if let day = splittableWeekday(rule: rule, instance: instance, zone: seriesZone(master, zone)) { scopes.append(.everyWeekday(day)) }
        scopes += [.thisAndFollowing, .allEvents]
        return scopes
    }

    static func splittableWeekday(rule: RRule, instance: CalendarEvent, zone: TimeZone) -> Weekday? {
        guard rule.frequency == .weekly, rule.byDay.count >= 2, rule.byDay.allSatisfy({ $0.ordinal == nil }) else { return nil }
        let day = originalStart(instance).civilDate(in: zone).weekday
        return rule.weekdays.contains(day) ? day : nil
    }

    // MARK: Edit

    public static func planEdit(master: CalendarEvent?, instance: CalendarEvent, patch: EventPatch, scope: RecurrenceScope,
                                calendarID: String, zone: TimeZone = .current) throws -> [CalendarMutation] {
        guard let master, let rule = master.rrule, instance.isRecurringInstance || master.id == instance.id else {
            // A single event: the patch applies as-is.
            return patch.isEmpty ? [] : [.patch(calendarID: calendarID, eventID: instance.id, patch: patch)]
        }
        let zone = seriesZone(master, zone)
        let context = Context(master: master, rule: rule, instance: instance, zone: zone)
        switch scope {
        case .thisEvent:
            var single = patch
            single.recurrence = nil
            return single.isEmpty ? [] : [.patch(calendarID: calendarID, eventID: instance.id, patch: single)]
        case .allEvents:
            return [.patch(calendarID: calendarID, eventID: master.id, patch: masterPatch(context, patch))]
        case .thisAndFollowing:
            if context.isFirstOccurrence {
                return [.patch(calendarID: calendarID, eventID: master.id, patch: masterPatch(context, patch))]
            }
            var series = seriesCopy(master)
            series = patch.applyingFields(to: series)
            let (start, end) = context.newTimes(patch)
            series.start = start
            series.end = end
            if let recurrence = patch.recurrence {
                series.recurrence = recurrence.isEmpty ? nil : recurrence
            } else {
                var newRule = shiftedRule(rule, days: context.dayDelta(to: start), toAllDay: start.isAllDay, zone: zone)
                if let count = rule.count { newRule.count = max(1, count - context.producedBefore) }
                series.recurrence = [newRule.line] + context.set.otherLines
            }
            return [
                .patch(calendarID: calendarID, eventID: master.id, patch: EventPatch(recurrence: context.truncatedLines())),
                .insert(calendarID: calendarID, event: series),
            ]
        case .everyWeekday(let day):
            guard splittableWeekday(rule: rule, instance: instance, zone: zone) == day else { throw RecurrenceEditError.scopeUnavailable }
            var mutations = restOfWeek(context, without: day, calendarID: calendarID)
            var series = seriesCopy(master)
            series = patch.applyingFields(to: series)
            series.recurrence = nil
            let (start, end) = context.newTimes(patch)
            series.start = start
            series.end = end
            let movedDay = day.shifted(by: context.dayDelta(to: start))
            var dayRule = rule
            dayRule.byDay = [RRule.Day(movedDay)]
            dayRule.until = convertUntil(rule.until, toAllDay: start.isAllDay, zone: zone)
            if rule.count != nil { dayRule.count = max(1, context.remaining.filter { $0.weekday == day }.count) }
            series.recurrence = [dayRule.line] + context.set.otherLines
            mutations.append(.insert(calendarID: calendarID, event: series))
            return mutations
        }
    }

    // MARK: Delete

    public static func planDelete(master: CalendarEvent?, instance: CalendarEvent, scope: RecurrenceScope,
                                  calendarID: String, zone: TimeZone = .current) throws -> [CalendarMutation] {
        guard let master, let rule = master.rrule, instance.isRecurringInstance || master.id == instance.id else {
            return [.delete(calendarID: calendarID, eventID: instance.id)]
        }
        let zone = seriesZone(master, zone)
        let context = Context(master: master, rule: rule, instance: instance, zone: zone)
        switch scope {
        case .thisEvent:
            return [.delete(calendarID: calendarID, eventID: instance.id)]
        case .allEvents:
            return [.delete(calendarID: calendarID, eventID: master.id)]
        case .thisAndFollowing:
            if context.isFirstOccurrence { return [.delete(calendarID: calendarID, eventID: master.id)] }
            return [.patch(calendarID: calendarID, eventID: master.id, patch: EventPatch(recurrence: context.truncatedLines()))]
        case .everyWeekday(let day):
            guard splittableWeekday(rule: rule, instance: instance, zone: zone) == day else { throw RecurrenceEditError.scopeUnavailable }
            return restOfWeek(context, without: day, calendarID: calendarID)
        }
    }

    // MARK: Pieces

    /// Keeps the other weekdays going from this occurrence on: patch the master in place when nothing precedes it,
    /// otherwise truncate the master and insert the rest as a new series.
    private static func restOfWeek(_ context: Context, without day: Weekday, calendarID: String) -> [CalendarMutation] {
        let master = context.master
        var restRule = context.rule
        restRule.byDay = context.rule.byDay.filter { $0.weekday != day }
        let restOccurrences = context.remaining.filter { $0.weekday != day }
        if context.rule.count != nil { restRule.count = max(1, restOccurrences.count) }
        guard let firstRest = restOccurrences.first else {
            // Nothing else remains: behaves like "this and following" for the other days.
            if context.isFirstOccurrence { return [.delete(calendarID: calendarID, eventID: master.id)] }
            return [.patch(calendarID: calendarID, eventID: master.id, patch: EventPatch(recurrence: context.truncatedLines()))]
        }
        let restStart = context.masterStart(on: firstRest)
        let restEnd = endFor(start: restStart, likeStart: master.start, end: master.end)
        let restLines = [restRule.line] + context.set.otherLines
        if context.isFirstOccurrence {
            var patch = EventPatch(recurrence: restLines)
            if restStart != master.start {
                patch.start = restStart
                patch.end = restEnd
            }
            return [.patch(calendarID: calendarID, eventID: master.id, patch: patch)]
        }
        var rest = seriesCopy(master)
        rest.start = restStart
        rest.end = restEnd
        rest.recurrence = restLines
        return [
            .patch(calendarID: calendarID, eventID: master.id, patch: EventPatch(recurrence: context.truncatedLines())),
            .insert(calendarID: calendarID, event: rest),
        ]
    }

    /// The patch for "all events": fields, plus shifted start/end and BYDAY when the instance moved.
    private static func masterPatch(_ context: Context, _ patch: EventPatch) -> EventPatch {
        var result = patch
        result.start = nil
        result.end = nil
        let (newStart, newEnd) = context.newTimes(patch)
        guard newStart != context.instance.start || newEnd != context.instance.end else { return result }
        let start = shift(context.master.start, from: context.instance.start, to: newStart, zone: context.zone)
        result.start = start
        result.end = endFor(start: start, likeStart: newStart, end: newEnd)
        if patch.recurrence == nil {
            let days = context.instance.start.civilDate(in: context.zone).days(to: newStart.civilDate(in: context.zone))
            let rule = shiftedRule(context.rule, days: days, toAllDay: newStart.isAllDay, zone: context.zone)
            if rule != context.rule { result.recurrence = [rule.line] + context.set.otherLines }
        }
        return result
    }

    struct Context {
        let master: CalendarEvent
        let rule: RRule
        let set: RecurrenceSet
        let instance: CalendarEvent
        let zone: TimeZone
        /// The clicked occurrence's unmodified start.
        let original: EventDateTime
        /// Occurrences (as civil dates, in order) from this one on, within COUNT / UNTIL — bounded to 10 years.
        let remaining: [CivilDate]
        /// How many occurrences the rule produced before this one (for COUNT arithmetic).
        let producedBefore: Int

        init(master: CalendarEvent, rule: RRule, instance: CalendarEvent, zone: TimeZone) {
            self.master = master
            self.rule = rule
            self.set = RecurrenceSet(lines: master.recurrence ?? [])
            self.instance = instance
            self.zone = zone
            let original = RecurrenceEditPlanner.originalStart(instance)
            self.original = original
            let allDay = master.start.isAllDay
            let seriesStart = master.start.instant(in: zone)
            let cut = original.instant(in: zone)
            let before = rule.occurrences(start: seriesStart, zone: zone, isAllDay: allDay, until: cut)
            producedBefore = before.count
            let horizon = Calendar.gregorian(zone).date(byAdding: .year, value: 10, to: cut) ?? cut
            let all = rule.occurrences(start: seriesStart, zone: zone, isAllDay: allDay, until: horizon, limit: 5000)
            remaining = all.filter { $0 >= cut }.map { CivilDate($0, in: zone) }
        }

        var isFirstOccurrence: Bool { producedBefore == 0 }

        /// The instance's times after the patch.
        func newTimes(_ patch: EventPatch) -> (EventDateTime, EventDateTime) {
            let start = patch.start ?? instance.start
            let end = patch.end ?? (patch.start != nil ? RecurrenceEditPlanner.endFor(start: start, likeStart: instance.start, end: instance.end) : instance.end)
            return (start, end)
        }

        func dayDelta(to newStart: EventDateTime) -> Int {
            original.civilDate(in: zone).days(to: newStart.civilDate(in: zone))
        }

        /// The master's start moved to `day`, keeping its time of day.
        func masterStart(on day: CivilDate) -> EventDateTime {
            let from = master.start.civilDate(in: zone)
            return RecurrenceEditPlanner.shiftDays(master.start, by: from.days(to: day), zone: zone)
        }

        /// The master's recurrence ending just before this occurrence (COUNT → UNTIL).
        func truncatedLines() -> [String] {
            var truncated = rule
            truncated.count = nil
            if master.start.isAllDay {
                truncated.until = .date(original.civilDate(in: zone).adding(days: -1))
            } else {
                truncated.until = .dateTime(original.instant(in: zone).addingTimeInterval(-1))
            }
            return [truncated.line] + set.otherLines
        }
    }

    static func seriesZone(_ master: CalendarEvent, _ fallback: TimeZone) -> TimeZone { master.start.zone ?? fallback }

    static func originalStart(_ instance: CalendarEvent) -> EventDateTime { instance.originalStartTime ?? instance.start }

    /// A fresh insertable copy of a series (server-assigned fields cleared).
    static func seriesCopy(_ master: CalendarEvent) -> CalendarEvent {
        var copy = master
        copy.id = ""
        copy.iCalUID = nil
        copy.htmlLink = nil
        copy.created = nil
        copy.updated = nil
        copy.sequence = nil
        copy.recurringEventId = nil
        copy.originalStartTime = nil
        copy.creator = nil
        copy.organizer = nil
        copy.hangoutLink = nil
        copy.conferenceData = nil
        copy.attendeesOmitted = nil
        copy.status = "confirmed"
        return copy
    }

    /// `end` for a new `start`, keeping the duration (or day span) of `likeStart … end`.
    static func endFor(start: EventDateTime, likeStart: EventDateTime, end: EventDateTime) -> EventDateTime {
        if start.isAllDay {
            let span = (likeStart.date.flatMap { s in end.date.map { s.days(to: $0) } }) ?? 1
            return .allDay((start.date ?? CivilDate(year: 1970, month: 1, day: 1)).adding(days: max(1, span)))
        }
        let duration: TimeInterval
        if let s = likeStart.dateTime, let e = end.dateTime { duration = e.timeIntervalSince(s) } else { duration = 3600 }
        return .timed((start.dateTime ?? Date()).addingTimeInterval(duration), timeZone: start.timeZone)
    }

    /// Moves `value` by whole days (wall-clock time kept).
    static func shiftDays(_ value: EventDateTime, by days: Int, zone: TimeZone) -> EventDateTime {
        if value.isAllDay { return .allDay((value.date ?? CivilDate(year: 1970, month: 1, day: 1)).adding(days: days)) }
        guard let instant = value.dateTime else { return value }
        let moved = Calendar.gregorian(value.zone ?? zone).date(byAdding: .day, value: days, to: instant) ?? instant
        return .timed(moved, timeZone: value.timeZone)
    }

    /// Applies the wall-clock change `old → new` (days + time of day, or a switch between all-day and timed) to `value`.
    static func shift(_ value: EventDateTime, from old: EventDateTime, to new: EventDateTime, zone: TimeZone) -> EventDateTime {
        let days = old.civilDate(in: zone).days(to: new.civilDate(in: zone))
        let day = value.civilDate(in: zone).adding(days: days)
        if new.isAllDay { return .allDay(day) }
        let calendar = Calendar.gregorian(zone)
        let newSeconds = secondsIntoDay(new, zone: zone)
        let seconds: Int
        if old.isAllDay || value.isAllDay {
            seconds = newSeconds
        } else {
            seconds = secondsIntoDay(value, zone: zone) + newSeconds - secondsIntoDay(old, zone: zone)
        }
        let midnight = day.startDate(in: zone)
        let instant = calendar.date(byAdding: .second, value: seconds, to: midnight) ?? midnight
        return .timed(instant, timeZone: new.timeZone ?? value.timeZone)
    }

    static func secondsIntoDay(_ value: EventDateTime, zone: TimeZone) -> Int {
        guard let instant = value.dateTime else { return 0 }
        let parts = Calendar.gregorian(zone).dateComponents([.hour, .minute, .second], from: instant)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    /// Moves BYDAY weekdays (and a single BYMONTHDAY) by `days`; converts UNTIL between date and date-time forms.
    static func shiftedRule(_ rule: RRule, days: Int, toAllDay: Bool, zone: TimeZone) -> RRule {
        var shifted = rule
        if days != 0 {
            shifted.byDay = rule.byDay.map { RRule.Day($0.weekday.shifted(by: days), ordinal: $0.ordinal) }
            if rule.frequency == .monthly, rule.byMonthDay.count == 1, let day = rule.byMonthDay.first, day > 0 {
                let moved = day + days
                if (1...28).contains(moved) { shifted.byMonthDay = [moved] }
            }
        }
        shifted.until = convertUntil(rule.until, toAllDay: toAllDay, zone: zone)
        return shifted
    }

    static func convertUntil(_ until: RRuleUntil?, toAllDay: Bool, zone: TimeZone) -> RRuleUntil? {
        switch (until, toAllDay) {
        case (.dateTime(let instant), true): return .date(CivilDate(instant, in: zone))
        case (.date(let date), false): return .dateTime(date.adding(days: 1).startDate(in: zone).addingTimeInterval(-1))
        default: return until
        }
    }
}

extension Weekday {
    /// The weekday `days` later (negative: earlier).
    public func shifted(by days: Int) -> Weekday {
        let index = ((calendarWeekday - 1 + days) % 7 + 7) % 7
        return Weekday.allCases[index]
    }
}
