import Foundation

public struct NotchNotificationOptions: Codable, Equatable {
    public var enabled = false
    public var expandAutomatically = true
    public var showPreview = true
    public var duration = 6.0
    public var includeCalls: Bool?
    public var callsEnabled: Bool { includeCalls ?? true }
    public init() {}
    public mutating func normalize() { duration = duration.isFinite ? min(15, max(3, duration)) : 6 }
}

/// In-memory display data only. Deliberately not Codable or persisted.
public struct NotchNotice: Identifiable, Equatable, Sendable {
    public var id: String
    public var app: String
    public var title: String
    public var body: String
    public var received: Date
    public var isSample: Bool
    public var sourceKey: String
    public var bundleID: String?
    public var isCall: Bool
    public var actions: [NoticeAction]
    public init(id: String, app: String, title: String, body: String, received: Date = Date(), isSample: Bool = false, sourceKey: String = "", bundleID: String? = nil, isCall: Bool = false, actions: [NoticeAction] = []) {
        self.id = id; self.app = app; self.title = title; self.body = body; self.received = received; self.isSample = isSample
        self.sourceKey = sourceKey; self.bundleID = bundleID; self.isCall = isCall; self.actions = actions
    }
    public var redacted: Self { var copy = self; copy.title = isCall ? "Incoming call" : "New notification"; copy.body = ""; return copy }
    public var compactDetail: String { body.isEmpty ? title : title.isEmpty ? body : title + ": " + body }
}

public struct NoticeAction: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: Kind
    public enum Kind: String, Sendable { case open, reply, reveal, answer, decline }
    public init(id: String, title: String, kind: Kind) { self.id = id; self.title = title; self.kind = kind }
    public static func kind(for label: String) -> Kind? {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "open", "show", "open app", "open notification": return .open
        case "reply", "reply…", "reply...": return .reply
        case "show in finder", "reveal in finder": return .reveal
        case "answer", "accept", "accept call", "answer call": return .answer
        case "decline", "decline call", "reject call": return .decline
        default: return nil
        }
    }
}

/// A bounded accessibility snapshot. It contains no native elements or actions.
public struct BannerNode: Sendable {
    public var key: String
    public var role: String
    public var subrole: String
    public var field: String
    public var text: String
    public var label: String
    public var visible: Bool
    public var children: [BannerNode]
    public var pressable: Bool
    public var exposedActions: [NoticeAction]
    public init(key: String = "", role: String = "AXGroup", subrole: String = "", field: String = "", text: String = "", label: String = "", visible: Bool = true, pressable: Bool = false, exposedActions: [NoticeAction] = [], children: [BannerNode] = []) {
        self.key = key; self.role = role; self.subrole = subrole; self.field = field; self.text = text; self.label = label; self.visible = visible; self.children = children
        self.pressable = pressable
        self.exposedActions = exposedActions
    }
}

public enum BannerParser {
    private static let cards: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
    private static let stacks: Set<String> = ["AXNotificationCenterBannerStack", "AXNotificationCenterAlertStack"]

    public static func notices(in roots: [BannerNode], now: Date) -> [NotchNotice] {
        var result: [NotchNotice] = []
        func visit(_ node: BannerNode, insideStack: Bool, depth: Int) {
            guard depth < 12, node.visible, result.count < 30 else { return }
            let isCard = cards.contains(node.subrole), isStack = stacks.contains(node.subrole)
            if isCard || isStack || insideStack {
                if let notice = decode(node, now: now) { result.append(notice); return }
            }
            for child in node.children { visit(child, insideStack: insideStack || isStack, depth: depth + 1) }
        }
        for root in roots { visit(root, insideStack: false, depth: 0) }
        return result
    }

    private static func decode(_ root: BannerNode, now: Date) -> NotchNotice? {
        guard root.role != "AXStaticText", root.role != "AXImage" else { return nil }
        var fields: [String: [String]] = [:], icons: [String] = [], count = 0
        var actions: [NoticeAction] = []
        func collect(_ node: BannerNode, depth: Int) {
            guard node.visible, depth < 12, count < 200 else { return }; count += 1
            let field = normalizedField(node.field)
            if node.role == "AXStaticText", ["header", "title", "subtitle", "body", ""].contains(field) {
                let value = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { fields[field, default: []].append(value) }
            }
            if node.role == "AXImage", !node.label.isEmpty { icons.append(String(node.label.prefix(100))) }
            if node.pressable, let kind = NoticeAction.kind(for: node.label), !actions.contains(where: { $0.kind == kind }) {
                actions.append(NoticeAction(id: node.key, title: node.label, kind: kind))
            }
            for action in node.exposedActions where !actions.contains(where: { $0.kind == action.kind }) { actions.append(action) }
            for child in node.children { collect(child, depth: depth + 1) }
        }
        collect(root, depth: 0)
        // Multiple titles/headers are multiple cards, never one combined message.
        guard count < 200, fields.values.allSatisfy({ $0.allSatisfy { $0.utf8.count <= 16_384 } }),
              (fields["title"]?.count ?? 0) <= 1, (fields["header"]?.count ?? 0) <= 1,
              (fields["body"]?.count ?? 0) <= 1, (fields["subtitle"]?.count ?? 0) <= 1 else { return nil }
        let title: String, body: String
        if let namedTitle = fields["title"]?.first {
            title = namedTitle
            body = [fields["subtitle"]?.first, fields["body"]?.first].compactMap { $0 }.joined(separator: "\n")
        } else if fields.keys.allSatisfy({ $0.isEmpty }), let plain = fields[""], (2...3).contains(plain.count) {
            title = plain[0]; body = plain.dropFirst().joined(separator: "\n")
        } else { return nil }
        let candidates = (fields["header"] ?? []) + icons
        let app = candidates.first(where: { $0 != title && $0 != body && !["notification", "notification center", "notifications"].contains($0.lowercased()) }) ?? ""
        // Store only an opaque content key for deduplication, not a second copy of the text.
        var hash = Hasher(); hash.combine(root.key); hash.combine(app); hash.combine(title); hash.combine(body)
        if root.pressable, !actions.contains(where: { $0.kind == .open }) { actions.insert(NoticeAction(id: root.key, title: "Open", kind: .open), at: 0) }
        return NotchNotice(id: String(hash.finalize()), app: String(app.prefix(100)), title: String(title.prefix(300)), body: String(body.prefix(1600)), received: now, sourceKey: root.key, actions: actions)
    }

    private static func normalizedField(_ field: String) -> String {
        let value = field.lowercased()
        if value.contains("subtitle") { return "subtitle" }
        if value == "header" || value.hasSuffix("appname") || value.hasSuffix("app-name") { return "header" }
        for key in ["header", "title", "body"] where value.hasSuffix(key) { return key }
        return field
    }

    /// A call window must expose both answer and decline. Ordinary app windows
    /// and outgoing/active calls must never be mistaken for incoming calls.
    public static func incomingCall(in root: BannerNode, app: String, bundleID: String, now: Date) -> NotchNotice? {
        var actions: [NoticeAction] = [], text: [String] = []
        func visit(_ node: BannerNode, depth: Int) {
            guard depth < 12, node.visible else { return }
            if node.role == "AXStaticText", !node.text.isEmpty, node.text.utf8.count < 2000 { text.append(node.text) }
            if node.pressable, let kind = NoticeAction.kind(for: node.label), [.answer, .decline].contains(kind), !actions.contains(where: { $0.kind == kind }) {
                actions.append(NoticeAction(id: node.key, title: kind == .answer ? "Answer" : "Decline", kind: kind))
            }
            for action in node.exposedActions where [.answer, .decline].contains(action.kind) && !actions.contains(where: { $0.kind == action.kind }) { actions.append(action) }
            for child in node.children { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        guard actions.contains(where: { $0.kind == .answer }), actions.contains(where: { $0.kind == .decline }) else { return nil }
        let caller = text.first { !["incoming call", "incoming video call", "incoming audio call", "facetime", "phone", "accept", "decline", "answer"].contains($0.lowercased()) } ?? "Incoming call"
        return NotchNotice(id: "call-\(root.key)", app: app, title: String(caller.prefix(300)), body: "Incoming call", received: now, sourceKey: root.key, bundleID: bundleID, isCall: true, actions: actions)
    }
}

public struct NotificationInbox {
    public private(set) var items: [NotchNotice] = []
    private var seen: [String] = []
    private var primeNext = true
    public init() {}
    /// First snapshot after enable/unlock/history browsing is a baseline, not new mail.
    public mutating func ingest(_ notices: [NotchNotice], showPreview: Bool) -> [NotchNotice] {
        var keys = Set(seen)
        let fresh = notices.filter { keys.insert($0.id).inserted }
        for notice in fresh { seen.append(notice.id) }
        seen = Array(seen.suffix(512))
        guard !primeNext else { primeNext = false; return [] }
        let displayed = fresh.map { showPreview ? $0 : $0.redacted }
        for notice in displayed { items.insert(notice, at: 0) }
        items = Array(items.prefix(30))
        return displayed
    }
    public mutating func discard(_ id: String) { items.removeAll { $0.id == id } }
    public mutating func clearDisplay() { items.removeAll() }
    public mutating func resumeWithBaseline() { primeNext = true }
    public mutating func reset() { items.removeAll(); seen.removeAll(); primeNext = true }
    public mutating func redact() { items = items.map(\.redacted) }
}
