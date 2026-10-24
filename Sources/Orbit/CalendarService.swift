import AppKit
import Combine
import EventKit
import OrbitCore

struct AgendaEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let calendar: String
    let color: NSColor
    let meeting: URL?
}
@MainActor final class CalendarService: ObservableObject {
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var calendars: [(id: String, title: String)] = []
    @Published var message: String?
    @Published private(set) var allowed = false
    private let eventStore = EKEventStore()
    private let permissions: PermissionCenter
    private var observer: NSObjectProtocol?
    private var refreshed = Date.distantPast
    private var enabled = false
    private var selected: [String] = []
    init(permissions: PermissionCenter) {
        self.permissions = permissions
        allowed = permissions.isAllowed(.calendar)
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh(force: true) } }
    }
    func configure(_ options: ProductivityOptions) {
        let changed = enabled != (options.calendarEnabled == true) || selected != (options.calendarIDs ?? [])
        enabled = options.calendarEnabled == true; selected = options.calendarIDs ?? []
        if !enabled { events = []; calendars = []; return }
        refresh(force: changed)
    }
    var accessButtonTitle: String { permissions.status(.calendar) == .denied || permissions.status(.calendar) == .restricted ? "Open Calendar settings" : "Allow Calendar access" }
    var requestingAccess: Bool { permissions.requesting.contains(.calendar) }
    func requestAccess() { permissions.request(.calendar) }
    func refresh(force: Bool = false) {
        allowed = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        if message != permissions.errors[.calendar] { message = permissions.errors[.calendar] }
        guard enabled, allowed else { events = []; calendars = []; return }
        guard force || Date().timeIntervalSince(refreshed) > 60 else { return }; refreshed = Date()
        let all = eventStore.calendars(for: .event)
        calendars = all.map { ($0.calendarIdentifier, $0.title) }
        let chosen = selected.isEmpty ? all : all.filter { selected.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { events = []; return }
        let start = Calendar.current.startOfDay(for: Date()), end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        events = eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: chosen))
            .filter { $0.endDate > Date() && $0.status != .canceled }.sorted { $0.startDate < $1.startDate }.prefix(100).map { event in
                AgendaEvent(id: (event.eventIdentifier ?? UUID().uuidString) + String(event.startDate.timeIntervalSince1970), title: event.title ?? "Untitled event", start: event.startDate, end: event.endDate, allDay: event.isAllDay, calendar: event.calendar.title, color: NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue,
                    meeting: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: "\n")))
            }
    }
    var nextMeeting: AgendaEvent? { events.first { !$0.allDay && $0.meeting != nil && $0.end > Date() } }
    func openCalendar() { NSWorkspace.shared.open(URL(string: "ical://")!) }
    func join(_ event: AgendaEvent) { if let url = event.meeting, MeetingLink.allowed(url) { NSWorkspace.shared.open(url) } }
}
