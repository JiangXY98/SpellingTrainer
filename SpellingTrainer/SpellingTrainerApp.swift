//
//  SpellingTrainerApp.swift
//  Spelling Trainer
//
//  macOS SwiftUI MVP: CSV import + QWERTY-style spelling practice (must retype whole word if wrong)
//
//  How to run:
//  1) Xcode -> File -> New -> Project... -> macOS -> App
//  2) Interface: SwiftUI, Language: Swift
//  3) Replace the generated .swift file content with this entire file
//  4) Build & Run
//
//  CSV format (UTF-8):
//    word,meaning
//    salience,"n. 显著性；突出性"
//    abstinence,"n. 戒断；禁欲"
//
//  Notes:
//  - Normalization: trim + lowercase
//  - Wrong answer: clears input and keeps the same target; brief feedback shown
//  - Wrong items are recycled after N other items (default 4)
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

@main
struct SpellingTrainerApp: App {
    @StateObject private var store = VocabStore()
    @StateObject private var engine = PracticeEngine()

    var body: some Scene {
        WindowGroup {
            RootView(store: store, engine: engine)
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView(store: store)
        }
    }
}

// MARK: - Models

struct VocabItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var word: String
    var meaning: String
    var createdAt: Date = Date()
    var lastTrainedAt: Date? = nil

    // Practice history
    var attemptCount: Int = 0
    var correctCount: Int = 0
    var wrongCount: Int = 0

    // Spaced repetition (simple Leitner-style scheduling)
    var nextReviewAt: Date? = nil        // nil means “due now”
    var intervalDays: Int = 1            // current interval in days
    var difficulty: Int = 3              // 1 (easy) .. 5 (hard)

    var source: String = ""              // e.g., "Huang and Xu, 2025, p. 1"
    var sourceURL: String = ""           // e.g., "zotero://select/library/items/8VLWXIV6"

    var normalizedWord: String {
        VocabStore.normalize(word)
    }
}

enum PracticeResult {
    case correct
    case wrong(expected: String)
}

enum PracticeMode: String, CaseIterable, Identifiable {
    case strict = "Strict"
    case copy = "Copy"

    var id: String { rawValue }
}

// MARK: - Persistence + Store

@MainActor
final class VocabStore: ObservableObject {
    @Published var items: [VocabItem] = []
    @Published var lastError: String? = nil

    @Published var useICloudSync: Bool = UserDefaults.standard.bool(forKey: "useICloudSync") {
        didSet {
            UserDefaults.standard.set(useICloudSync, forKey: "useICloudSync")
            refreshICloudAvailability()
            migrateVocabularyFileIfNeeded()
            load()
        }
    }

    @Published var iCloudAvailable: Bool = false

    private let fileName = "vocab.json"

    init() {
        refreshICloudAvailability()
        migrateVocabularyFileIfNeeded()
        load()
    }

    nonisolated static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: Disk IO

    private func appSupportURL() -> URL {
        let fm = FileManager.default
        let base = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("SpellingTrainer", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func refreshICloudAvailability() {
        iCloudAvailable = FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
    }

    private func iCloudBaseURL() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let docs = container.appendingPathComponent("Documents", isDirectory: true)
        let dir = docs.appendingPathComponent("SpellingTrainer", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func localVocabFileURL() -> URL {
        appSupportURL().appendingPathComponent(fileName)
    }

    private func iCloudVocabFileURL() -> URL? {
        iCloudBaseURL()?.appendingPathComponent(fileName)
    }

    private func activeVocabFileURL() -> URL {
        refreshICloudAvailability()
        if useICloudSync, let url = iCloudVocabFileURL() {
            return url
        }
        return localVocabFileURL()
    }

    private func migrateVocabularyFileIfNeeded() {
        let fm = FileManager.default
        let local = localVocabFileURL()
        let cloud = iCloudVocabFileURL()

        if useICloudSync {
            guard let cloud else { return }
            if !fm.fileExists(atPath: cloud.path), fm.fileExists(atPath: local.path) {
                try? fm.copyItem(at: local, to: cloud)
            }
        } else {
            guard let cloud else { return }
            if !fm.fileExists(atPath: local.path), fm.fileExists(atPath: cloud.path) {
                try? fm.copyItem(at: cloud, to: local)
            }
        }
    }

    private func vocabFileURL() -> URL {
        activeVocabFileURL()
    }

    func save() {
        do {
            refreshICloudAvailability()
            let data = try JSONEncoder().encode(items)
            try data.write(to: vocabFileURL(), options: [.atomic])
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
        }
    }

    func load() {
        do {
            refreshICloudAvailability()

            if useICloudSync, !iCloudAvailable {
                lastError = "iCloud Drive is unavailable. Using local storage."
            }

            let url = vocabFileURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                items = []
                return
            }
            let data = try Data(contentsOf: url)
            items = try JSONDecoder().decode([VocabItem].self, from: data)
        } catch {
            lastError = "Load failed: \(error.localizedDescription)"
        }
    }

    // MARK: CRUD

    func upsert(word: String, meaning: String, mergeMeaning: Bool = true) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }

        let key = Self.normalize(w)

        if let idx = items.firstIndex(where: { Self.normalize($0.word) == key }) {
            if mergeMeaning {
                let existing = items[idx].meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                if existing.isEmpty {
                    items[idx].meaning = m
                } else if !m.isEmpty, !existing.contains(m) {
                    // simple merge rule: append if new
                    items[idx].meaning = existing + "；" + m
                }
            } else {
                items[idx].meaning = m
            }
        } else {
            var it = VocabItem(word: w, meaning: m)
            // New items should be due immediately
            it.nextReviewAt = nil
            it.intervalDays = 1
            it.difficulty = 3
            items.append(it)
        }
        items.sort { $0.word.lowercased() < $1.word.lowercased() }
        save()
    }

    func delete(_ item: VocabItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func resetStats() {
        for i in items.indices {
            items[i].attemptCount = 0
            items[i].correctCount = 0
            items[i].wrongCount = 0
            items[i].lastTrainedAt = nil

            // Reset scheduling
            items[i].nextReviewAt = nil
            items[i].intervalDays = 1
            items[i].difficulty = 3
        }
        save()
    }
    // MARK: SRS helpers

    func isDue(_ item: VocabItem, now: Date = Date()) -> Bool {
        guard let t = item.nextReviewAt else { return true } // nil means due now
        return t <= now
    }

    func dueCount(now: Date = Date()) -> Int {
        items.filter { isDue($0, now: now) }.count
    }

    private func extractZoteroSource(from snippet: String) -> String {
        // Try to capture the first bracketed citation like: [Huang and Xu, 2025, p. 1]
        let pattern = "\\[([^\\]]+)\\]"
        if let r = try? NSRegularExpression(pattern: pattern) {
            if let m = r.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)) {
                if let rr = Range(m.range(at: 1), in: snippet) {
                    return String(snippet[rr]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return ""
    }
    
    private func extractZoteroURL(from snippet: String) -> String {
        // Prefer zotero://select/... if present; otherwise take the first zotero:// URL.
        // Examples in copied text:
        // (zotero://select/library/items/XXXXXXXX)
        // (zotero://open-pdf/library/items/YYYYYYYY?page=...)
        let patternSelect = "zotero://select/[^)\\s]+"
        if let r = try? NSRegularExpression(pattern: patternSelect) {
            if let m = r.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)) {
                if let rr = Range(m.range(at: 0), in: snippet) {
                    return String(snippet[rr]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        let patternAny = "zotero://[^)\\s]+"
        if let r2 = try? NSRegularExpression(pattern: patternAny) {
            if let m2 = r2.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)) {
                if let rr2 = Range(m2.range(at: 0), in: snippet) {
                    return String(snippet[rr2]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return ""
    }

    // MARK: Export

    func exportCSVString() -> String {
        // RFC4180-ish: quote fields that contain comma, quote, or newline.
        func q(_ s: String) -> String {
            let needs = s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")
            if !needs { return s }
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }

        let iso = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("word,meaning,source,sourceURL,attemptCount,correctCount,wrongCount,intervalDays,difficulty,nextReviewAt,createdAt,lastTrainedAt")

        for it in items {
            let next = it.nextReviewAt.map { iso.string(from: $0) } ?? ""
            let created = iso.string(from: it.createdAt)
            let last = it.lastTrainedAt.map { iso.string(from: $0) } ?? ""

            let row = [
                q(it.word),
                q(it.meaning),
                q(it.source),
                q(it.sourceURL),
                String(it.attemptCount),
                String(it.correctCount),
                String(it.wrongCount),
                String(it.intervalDays),
                String(it.difficulty),
                q(next),
                q(created),
                q(last)
            ].joined(separator: ",")

            lines.append(row)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    func exportJSONString(pretty: Bool = true) -> String? {
        do {
            let enc = JSONEncoder()
            if pretty { enc.outputFormatting = [.prettyPrinted, .sortedKeys] }
            let data = try enc.encode(items)
            return String(data: data, encoding: .utf8)
        } catch {
            lastError = "Export JSON failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Import

    func importCSV(from url: URL, mergeMeaning: Bool = true) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let rows = CSV.parse(text: text)
            guard !rows.isEmpty else { return }

            // Heuristic: if header contains "word" and "meaning", skip it.
            var startIndex = 0
            if let first = rows.first, first.count >= 2 {
                let c0 = Self.normalize(first[0])
                let c1 = Self.normalize(first[1])
                if c0.contains("word") && (c1.contains("meaning") || c1.contains("definition") || c1.contains("trans")) {
                    startIndex = 1
                }
            }

            var imported = 0
            for r in rows.dropFirst(startIndex) {
                guard r.count >= 2 else { continue }
                let w = r[0]
                let m = r[1]
                if Self.normalize(w).isEmpty { continue }
                upsert(word: w, meaning: m, mergeMeaning: mergeMeaning)
                imported += 1
            }
            lastError = "Imported \(imported) rows."
        } catch {
            lastError = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: Zotero Clipboard Import

    func importZoteroClipboard(mergeMeaning: Bool = true) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            lastError = "Clipboard does not contain text."
            return
        }
        importZoteroText(text, mergeMeaning: mergeMeaning)
    }

    private func cleanZoteroMeaning(word: String, rawMeaning: String) -> String {
        var m = rawMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !m.isEmpty else { return m }

        // Many Zotero dictionary clips repeat the headword at the start of the quoted meaning,
        // e.g. "satisfactory 英 ...". Remove that duplicated prefix.
        let lowerM = m.lowercased()
        let lowerW = w.lowercased()
        if lowerM.hasPrefix(lowerW) {
            let idx = m.index(m.startIndex, offsetBy: min(m.count, w.count))
            // Only strip if the next character looks like a delimiter (space / punctuation / bracket / Chinese phonetic markers)
            if idx < m.endIndex {
                let next = m[idx]
                let delimiters: Set<Character> = [" ", "\t", "\n", "\r", "[", "(", "（", "【", "{", "-", "—", ":", "：", ";", "；", ",", "，", ".", "。", "!", "?", "“", "\"", "英", "美"]
                if delimiters.contains(next) {
                    m = String(m[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                // meaning is exactly the word
                m = ""
            }
        }
        return m
    }

    func importZoteroText(_ text: String, mergeMeaning: Bool = true) {
        var count = 0

        // Pattern for lines like:
        // “word” (...) "definition"
        let pattern = "“([^”]+)”[^\"]*\\\"([^\\\"]+)\\\""
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            for m in matches {
                if let r1 = Range(m.range(at: 1), in: text),
                   let r2 = Range(m.range(at: 2), in: text) {

                    let word = String(text[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let rawMeaning = String(text[r2]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let meaning = cleanZoteroMeaning(word: word, rawMeaning: rawMeaning)

                    if !Self.normalize(word).isEmpty {
                        // capture source from the matched snippet
                        let snippet = (text as NSString).substring(with: m.range)
                        let src = extractZoteroSource(from: snippet)
                        let zotURL = extractZoteroURL(from: snippet)

                        upsert(word: word, meaning: meaning, mergeMeaning: mergeMeaning)

                        if !src.isEmpty || !zotURL.isEmpty {
                            let key = Self.normalize(word)
                            if let idx = items.firstIndex(where: { Self.normalize($0.word) == key }) {
                                if !src.isEmpty, items[idx].source.isEmpty { items[idx].source = src }
                                if !zotURL.isEmpty, items[idx].sourceURL.isEmpty { items[idx].sourceURL = zotURL }
                            }
                        }

                        count += 1
                    }
                }
            }
        }

        // fallback for: “word” ... 🔤meaning🔤
        let pattern2 = "“([^”]+)”[^\\n]*?🔤([^🔤]+)🔤"
        if let regex2 = try? NSRegularExpression(pattern: pattern2) {
            let matches = regex2.matches(in: text, range: NSRange(text.startIndex..., in: text))

            for m in matches {
                if let r1 = Range(m.range(at: 1), in: text),
                   let r2 = Range(m.range(at: 2), in: text) {

                    let word = String(text[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let meaning = String(text[r2]).trimmingCharacters(in: .whitespacesAndNewlines)

                    if !Self.normalize(word).isEmpty {
                        let snippet = (text as NSString).substring(with: m.range)
                        let src = extractZoteroSource(from: snippet)
                        let zotURL = extractZoteroURL(from: snippet)

                        upsert(word: word, meaning: meaning, mergeMeaning: mergeMeaning)

                        if !src.isEmpty || !zotURL.isEmpty {
                            let key = Self.normalize(word)
                            if let idx = items.firstIndex(where: { Self.normalize($0.word) == key }) {
                                if !src.isEmpty, items[idx].source.isEmpty { items[idx].source = src }
                                if !zotURL.isEmpty, items[idx].sourceURL.isEmpty { items[idx].sourceURL = zotURL }
                            }
                        }

                        count += 1
                    }
                }
            }
        }

        if count == 0 {
            lastError = "No Zotero vocabulary detected in pasted text."
        } else {
            lastError = "Imported \(count) items from Zotero clipboard."
        }
    }
}

// MARK: - CSV Parser (minimal, RFC4180-ish)

enum CSV {
    static func parse(text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            // ignore totally empty trailing row
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                rows.append(row)
            }
            row = []
        }

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if inQuotes {
                if c == "\"" {
                    // escaped quote?
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    endField()
                } else if c == "\n" {
                    endField()
                    endRow()
                } else if c == "\r" {
                    // handle \r\n
                    if i + 1 < chars.count, chars[i + 1] == "\n" {
                        i += 1
                    }
                    endField()
                    endRow()
                } else {
                    field.append(c)
                }
            }
            i += 1
        }

        // finalize
        endField()
        if !row.isEmpty {
            endRow()
        }
        // trim fields
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
    }
}

// MARK: - Practice Engine

@MainActor
final class PracticeEngine: ObservableObject {
    @Published var current: VocabItem? = nil
    @Published var input: String = ""
    @Published var statusText: String = ""
    @Published var statusKind: StatusKind = .neutral

    @Published var totalAttempts: Int = 0
    @Published var correctAttempts: Int = 0
    @Published var wrongAttempts: Int = 0
    @Published var streak: Int = 0

    @Published var startedAt: Date? = nil
    @Published var totalTypedChars: Int = 0
    @Published var mode: PracticeMode = .strict
    @Published var showMeaning: Bool = true

    enum StatusKind { case neutral, ok, bad }

    private var queue: [VocabItem] = []
    private var recycle: [(item: VocabItem, afterK: Int)] = [] // wrong items reappear after K other items

    var recycleDelay: Int = 4

    func start(with items: [VocabItem]) {
        resetSession()
        let now = Date()

        // Load user settings (with sane defaults)
        let ud = UserDefaults.standard
        let maxNew = max(0, ud.object(forKey: "maxNewPerSession") as? Int ?? ud.integer(forKey: "maxNewPerSession")).nonZeroOr(default: 10)
        let maxReview = max(1, ud.object(forKey: "maxReviewPerSession") as? Int ?? ud.integer(forKey: "maxReviewPerSession")).nonZeroOr(default: 30)

        // Due-first scheduling
        let dueAll = items.filter { $0.nextReviewAt == nil || ($0.nextReviewAt ?? now) <= now }

        // Split: new vs review
        var dueNew = dueAll.filter { $0.attemptCount == 0 }
        var dueReview = dueAll.filter { $0.attemptCount > 0 }

        // Prioritize harder / older due items
        dueNew.sort {
            let t0 = $0.nextReviewAt ?? .distantPast
            let t1 = $1.nextReviewAt ?? .distantPast
            if t0 != t1 { return t0 < t1 }
            return $0.word.lowercased() < $1.word.lowercased()
        }

        dueReview.sort {
            let t0 = $0.nextReviewAt ?? .distantPast
            let t1 = $1.nextReviewAt ?? .distantPast
            if t0 != t1 { return t0 < t1 }
            if $0.difficulty != $1.difficulty { return $0.difficulty > $1.difficulty }
            return $0.attemptCount < $1.attemptCount
        }

        if !dueAll.isEmpty {
            let newBatch = Array(dueNew.prefix(maxNew))
            let reviewBatch = Array(dueReview.prefix(maxReview))
            queue = (newBatch + reviewBatch).shuffled()
        } else {
            // No due items: maintenance batch
            queue = Array(items.shuffled().prefix(min(maxReview, items.count)))
        }

        advance()
    }
    func resetSession() {
        current = nil
        input = ""
        statusText = ""
        statusKind = .neutral
        totalAttempts = 0
        correctAttempts = 0
        wrongAttempts = 0
        streak = 0
        startedAt = nil
        totalTypedChars = 0
        queue = []
        recycle = []
    }

    func stop() {
        // End the current session without wiping session stats.
        current = nil
        input = ""
        statusText = ""
        statusKind = .neutral
        queue = []
        recycle = []
    }

    func wpm() -> Double {
        guard let start = startedAt else { return 0 }
        let seconds = Date().timeIntervalSince(start)
        guard seconds > 0 else { return 0 }
        // Rough: 5 chars = 1 "word"
        let words = Double(totalTypedChars) / 5.0
        return (words / seconds) * 60.0
    }

    func accuracy() -> Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(correctAttempts) / Double(totalAttempts)
    }

    func submit(store: VocabStore) -> PracticeResult {
        guard let cur = current else { return .wrong(expected: "") }
        if startedAt == nil { startedAt = Date() }

        let typed = input
        totalTypedChars += typed.count
        totalAttempts += 1

        let ok = VocabStore.normalize(typed) == cur.normalizedWord
        input = ""

        if ok {
            correctAttempts += 1
            streak += 1
            statusKind = .ok
            statusText = "Correct"
            storeUpdate(store, item: cur, correct: true)
            tickRecycle()
            advance()
            return .correct
        } else {
            wrongAttempts += 1
            streak = 0
            statusKind = .bad
            statusText = "Wrong → retype (expected: \(cur.word))"
            storeUpdate(store, item: cur, correct: false)

            // push to recycle so it comes back after recycleDelay items
            recycle.append((cur, recycleDelay))
            tickRecycle()
            // keep current the same to force immediate retype (qwerty-style)
            return .wrong(expected: cur.word)
        }
    }

    private func computeNextReview(now: Date, intervalDays: Int) -> Date {
        let days = max(1, intervalDays)
        return Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
    }

    private func storeUpdate(_ store: VocabStore, item: VocabItem, correct: Bool) {
        guard let idx = store.items.firstIndex(where: { $0.id == item.id }) else { return }
        let now = Date()
        store.items[idx].lastTrainedAt = now
        store.items[idx].attemptCount += 1

        // Simple scheduling rules:
        // - Correct: interval doubles; difficulty decreases (to min 1)
        // - Wrong: interval resets to 1; difficulty increases (to max 5)
        if correct {
            store.items[idx].correctCount += 1
            let nextInterval = min(365, max(1, store.items[idx].intervalDays) * 2)
            store.items[idx].intervalDays = nextInterval
            store.items[idx].difficulty = max(1, store.items[idx].difficulty - 1)
            store.items[idx].nextReviewAt = computeNextReview(now: now, intervalDays: nextInterval)
        } else {
            store.items[idx].wrongCount += 1
            store.items[idx].intervalDays = 1
            store.items[idx].difficulty = min(5, store.items[idx].difficulty + 1)
            store.items[idx].nextReviewAt = computeNextReview(now: now, intervalDays: 1)
        }

        store.save()
    }

    private func tickRecycle() {
        guard !recycle.isEmpty else { return }
        for i in recycle.indices {
            recycle[i].afterK -= 1
        }
        // when due, insert them near the front (but not immediate if queue non-empty)
        let due = recycle.filter { $0.afterK <= 0 }.map { $0.item }
        recycle.removeAll { $0.afterK <= 0 }
        if !due.isEmpty {
            // insert due items a few positions ahead
            let insertPos = min(2, queue.count)
            queue.insert(contentsOf: due.shuffled(), at: insertPos)
        }
    }

    private func advance() {
        if queue.isEmpty {
            current = nil
            statusKind = .neutral
            statusText = "Done. Import more words or restart."
            return
        }
        current = queue.removeFirst()
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var store: VocabStore

    @AppStorage("maxNewPerSession") private var maxNewPerSession: Int = 10
    @AppStorage("maxReviewPerSession") private var maxReviewPerSession: Int = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Session Limits") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Max new per session") {
                        Stepper(value: $maxNewPerSession, in: 0...200, step: 1) {
                            Text("\(maxNewPerSession)")
                                .monospacedDigit()
                                .frame(minWidth: 40, alignment: .trailing)
                        }
                    }

                    LabeledContent("Max reviews per session") {
                        Stepper(value: $maxReviewPerSession, in: 1...500, step: 1) {
                            Text("\(maxReviewPerSession)")
                                .monospacedDigit()
                                .frame(minWidth: 40, alignment: .trailing)
                        }
                    }

                    Text("New = words with 0 attempts. Reviews = due words with ≥1 attempt. Queue order: new first, then reviews.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Sync") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Use iCloud Drive sync", isOn: $store.useICloudSync)

                    HStack {
                        Text("Status")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(store.iCloudAvailable ? "Available" : "Unavailable")
                            .foregroundStyle(.secondary)
                    }

                    Text("When enabled, vocab.json is stored in the app’s iCloud Documents container. If iCloud is unavailable, the app falls back to local storage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Defaults") {
                HStack {
                    Button("Reset to defaults") {
                        maxNewPerSession = 10
                        maxReviewPerSession = 30
                        store.useICloudSync = false
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 540, height: 330)
        .onAppear {
            store.load()
        }
    }
}

private extension Int {
    func nonZeroOr(default d: Int) -> Int {
        self == 0 ? d : self
    }
}

// MARK: - UI


// MARK: - Detail Popover for Vocabulary

struct VocabDetailPopover: View {
    let item: VocabItem

    private var accPct: Int {
        guard item.attemptCount > 0 else { return 0 }
        return Int((Double(item.correctCount) / Double(item.attemptCount) * 100).rounded())
    }

    private func dateString(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.word)
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Meaning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.meaning.isEmpty ? "—" : item.meaning)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !item.source.isEmpty || !item.sourceURL.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let url = URL(string: item.sourceURL), !item.sourceURL.isEmpty {
                        Link(item.source.isEmpty ? "Open in Zotero" : item.source, destination: url)
                            .font(.callout)
                            .focusable(false)
                    } else {
                        Text(item.source)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }

            Divider()

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Attempts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(item.attemptCount)")
                        .font(.callout)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accuracy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(accPct)%")
                        .font(.callout)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Correct / Wrong")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(item.correctCount) / \(item.wrongCount)")
                        .font(.callout)
                        .fontWeight(.semibold)
                }
            }

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next review")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dateString(item.nextReviewAt))
                        .font(.callout)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Interval")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(item.intervalDays)d")
                        .font(.callout)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Difficulty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(item.difficulty)/5")
                        .font(.callout)
                }
            }

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dateString(item.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Last trained")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dateString(item.lastTrainedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 420)
    }
}

private extension VocabDetailPopover {
    func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}

struct RootView: View {
    @ObservedObject var store: VocabStore
    @ObservedObject var engine: PracticeEngine
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store, engine: engine, columnVisibility: $columnVisibility)
        } detail: {
            PracticeView(store: store, engine: engine, columnVisibility: $columnVisibility)
        }
    }
}

struct SidebarView: View {
    @ObservedObject var store: VocabStore
    @ObservedObject var engine: PracticeEngine
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @State private var selection: VocabItem.ID? = nil
    @State private var detailItem: VocabItem? = nil
    @State private var searchText: String = ""
    @State private var showingAdd = false
    @State private var mergeMeaningOnImport = true

    @State private var showingImporter = false
    @State private var importURL: URL? = nil

    private var filteredItems: [VocabItem] {
        let q = VocabStore.normalize(searchText)
        guard !q.isEmpty else { return store.items }
        return store.items.filter { it in
            let w = VocabStore.normalize(it.word)
            let m = VocabStore.normalize(it.meaning)
            let s = VocabStore.normalize(it.source)
            return w.contains(q) || m.contains(q) || s.contains(q)
        }
    }

    private func suggestFileName(_ ext: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return "spelling_trainer_export_\(f.string(from: Date())).\(ext)"
    }

    private func runSavePanel(defaultName: String, allowedExt: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [UTType(filenameExtension: allowedExt) ?? .data]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let resp = panel.runModal()
        guard resp == .OK, let url = panel.url else { return nil }
        return url
    }

    private func exportCSV() {
        guard !store.items.isEmpty else {
            store.lastError = "Nothing to export."
            return
        }
        guard let url = runSavePanel(defaultName: suggestFileName("csv"), allowedExt: "csv") else { return }
        do {
            let text = store.exportCSVString()
            try text.write(to: url, atomically: true, encoding: .utf8)
            store.lastError = "Exported CSV to \(url.lastPathComponent)"
        } catch {
            store.lastError = "Export CSV failed: \(error.localizedDescription)"
        }
    }

    private func exportJSON() {
        guard !store.items.isEmpty else {
            store.lastError = "Nothing to export."
            return
        }
        guard let url = runSavePanel(defaultName: suggestFileName("json"), allowedExt: "json") else { return }
        guard let text = store.exportJSONString(pretty: true) else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            store.lastError = "Exported JSON to \(url.lastPathComponent)"
        } catch {
            store.lastError = "Export JSON failed: \(error.localizedDescription)"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Vocabulary")
                    .font(.headline)
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a new word")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))

            List(filteredItems, selection: $selection) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.word)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)

                        if !item.meaning.isEmpty {
                            Text(item.meaning)
                                .font(.system(.caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Small due indicator
                    if store.isDue(item) {
                        Text("Due")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // Keep List selection and popover target aligned
                    selection = item.id
                    detailItem = item
                }
                .popover(
                    isPresented: Binding(
                        get: { detailItem?.id == item.id },
                        set: { show in
                            if !show, detailItem?.id == item.id { detailItem = nil }
                        }
                    ),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .trailing
                ) {
                    VocabDetailPopover(item: item)
                }
                .contextMenu {
                    Button("Delete") { store.delete(item) }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selection) { _, newSel in
                guard let newSel else { detailItem = nil; return }
                // If user navigates selection, keep the popover in sync
                if let it = filteredItems.first(where: { $0.id == newSel }) {
                    detailItem = it
                } else {
                    // selection points to an item not currently visible under the filter
                    detailItem = nil
                }
            }
            .onChange(of: searchText) { _, _ in
                if let d = detailItem, !filteredItems.contains(where: { $0.id == d.id }) {
                    detailItem = nil
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {

                Toggle("Merge meaning on import/upsert", isOn: $mergeMeaningOnImport)
                    .font(.caption)

                HStack {
                    Button("Import CSV…") { showingImporter = true }

                    Button("Paste Zotero") {
                        store.importZoteroClipboard(mergeMeaning: mergeMeaningOnImport)
                    }

                    Spacer()
                }

                HStack {
                    Button("Export CSV…") {
                        exportCSV()
                    }

                    Menu("Export") {
                        Button("Export JSON…") {
                            exportJSON()
                        }
                    }

                    Spacer()
                }

                if let msg = store.lastError {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    store.importCSV(from: url, mergeMeaning: mergeMeaningOnImport)
                }
            case .failure(let err):
                store.lastError = "File import cancelled/failed: \(err.localizedDescription)"
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddWordSheet { w, m in
                store.upsert(word: w, meaning: m, mergeMeaning: mergeMeaningOnImport)
            }
        }
    }
}

struct AddWordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var word: String = ""
    @State private var meaning: String = ""

    var onSave: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Word")
                .font(.headline)

            TextField("Word", text: $word)
                .textFieldStyle(.roundedBorder)

            TextField("Meaning (hint)", text: $meaning)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(word, meaning)
                    dismiss()
                }
                .disabled(word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520)
    }
}

struct PracticeView: View {
    @ObservedObject var store: VocabStore
    @ObservedObject var engine: PracticeEngine
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @FocusState private var inputFocused: Bool
    
    private func startSession() {
        engine.start(with: store.items)
        columnVisibility = .detailOnly
        inputFocused = true
    }

    private func stopSession() {
        engine.stop()
        columnVisibility = .all
        inputFocused = false
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            Spacer(minLength: 0)

            if let cur = engine.current {
                if engine.showMeaning {
                    meaningCard(cur)
                }
                inputCard(cur)
            } else {
                emptyState
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(28)
        .onAppear { inputFocused = true }
        .onChange(of: engine.current) { _, _ in inputFocused = true }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Spelling Practice")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Enter the full word. If wrong, retype the whole word.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            HStack(spacing: 10) {
                if engine.current != nil {
                    Button("Stop") {
                        stopSession()
                    }
                    statsPills
                }
            }
        }
    }

    private var statsPills: some View {
        HStack(spacing: 10) {
            pill("Due", "\(store.dueCount())")
            pill("Acc", String(format: "%.0f%%", engine.accuracy() * 100))
            pill("WPM", String(format: "%.1f", engine.wpm()))
            pill("Streak", "\(engine.streak)")
        }
        .font(.system(.caption, design: .rounded))
    }

    private func pill(_ k: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(k).foregroundStyle(.secondary)
            Text(v).fontWeight(.semibold)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)).shadow(radius: 1))
    }

    private func meaningCard(_ item: VocabItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hint / Meaning")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(item.meaning.isEmpty ? "—" : item.meaning)
                .font(.system(size: 28, weight: .regular, design: .rounded))
                .textSelection(.enabled)
                .lineLimit(nil)
            if let url = URL(string: item.sourceURL), !item.sourceURL.isEmpty {
                Link(item.source.isEmpty ? "Open in Zotero" : item.source, destination: url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .focusable(false)
                    .padding(.top, 6)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(NSColor.controlBackgroundColor)))
    }

    private func firstMismatchIndex(word: String, typed: String) -> Int? {
        let w = Array(word)
        let t = Array(typed)

        let n = min(w.count, t.count)
        var i = 0
        while i < n {
            if w[i] != t[i] { return i }
            i += 1
        }
        // If the typed string is longer than the word, treat the first extra char as mismatch.
        if t.count > w.count { return w.count }
        return nil
    }

    private func ghostText(word: String, typed: String) -> some View {
        let w = Array(word)
        let mismatch = firstMismatchIndex(word: word, typed: typed)

        let prefixCount = mismatch ?? min(w.count, Array(typed).count)
        let safePrefixCount = min(prefixCount, w.count)

        let prefix = String(w.prefix(safePrefixCount))

        var mid = ""
        var suffix = ""
        if let m = mismatch, m < w.count {
            mid = String(w[m])
            if m + 1 < w.count {
                suffix = String(w[(m + 1)...])
            }
        } else {
            if safePrefixCount < w.count {
                suffix = String(w[safePrefixCount...])
            }
        }

        return HStack(spacing: 0) {
            Text(prefix)
                .foregroundStyle(.primary)
                .opacity(0.35)
            Text(mid)
                .foregroundStyle(.red)
                .opacity(mismatch == nil ? 0.0 : 0.9)
                .underline(mismatch == nil ? false : true, color: .red)
            Text(suffix)
                .foregroundStyle(.secondary)
                .opacity(0.25)
        }
        .font(.system(size: 30, weight: .semibold, design: .monospaced))
        // IMPORTANT: match TextField padding exactly for perfect overlay alignment
        .padding(14)
    }

    private func inputCard(_ item: VocabItem) -> some View {
        VStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if engine.mode == .copy {
                    ghostText(word: item.word, typed: engine.input)
                }

                if engine.mode == .copy {
                    TextField("", text: $engine.input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .padding(14)
                        .focused($inputFocused)
                        .onSubmit {
                            _ = engine.submit(store: store)
                            inputFocused = true
                        }
                } else {
                    TextField("Type the word…", text: $engine.input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .padding(14)
                        .focused($inputFocused)
                        .onSubmit {
                            _ = engine.submit(store: store)
                            inputFocused = true
                        }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(borderColor, lineWidth: 2))

            // Error message below the box for copy mode, aligned left
            if engine.mode == .copy, let m = firstMismatchIndex(word: item.word, typed: engine.input) {
                Text("Error at position \(m + 1)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, 2)
            }

            HStack {
                statusBadge
                Spacer()
                Text("Correct \(engine.correctAttempts) | Wrong \(engine.wrongAttempts) | Attempts \(engine.totalAttempts)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(NSColor.controlBackgroundColor)))
    }

    private var borderColor: Color {
        switch engine.statusKind {
        case .neutral: return Color.secondary.opacity(0.4)
        case .ok: return Color.green.opacity(0.8)
        case .bad: return Color.red.opacity(0.8)
        }
    }

    private var statusBadge: some View {
        Group {
            if engine.statusText.isEmpty {
                Text(" ").font(.caption)
            } else {
                Text(engine.statusText)
                    .font(.caption)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(badgeFill))
            }
        }
    }

    private var badgeFill: Color {
        switch engine.statusKind {
        case .neutral: return Color.secondary.opacity(0.15)
        case .ok: return Color.green.opacity(0.18)
        case .bad: return Color.red.opacity(0.18)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("No active session.")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            Text(store.items.isEmpty ? "Import words first (CSV or Zotero paste), then start." : "Ready to practice your due words.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if engine.totalAttempts > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Last session")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        summaryPill("Attempts", "\(engine.totalAttempts)")
                        summaryPill("Acc", String(format: "%.0f%%", engine.accuracy() * 100))
                        summaryPill("WPM", String(format: "%.1f", engine.wpm()))
                        summaryPill("Streak", "\(engine.streak)")
                    }
                }
                .padding(.top, 4)
            }

            Button {
                startSession()
            } label: {
                Text("Start Practice")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.items.isEmpty)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(NSColor.controlBackgroundColor)))
    }

    private func summaryPill(_ k: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(k)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(v)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)).shadow(radius: 1))
    }

    private var footer: some View {
        HStack {
            Text("Tip: Keep words as plain letters to avoid punctuation/spacing ambiguity in spelling checks.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 14) {
                Toggle("显示释义", isOn: $engine.showMeaning)
                    .toggleStyle(.switch)
                    .font(.caption)

                Toggle("默写", isOn: Binding(
                    get: { engine.mode == .strict },
                    set: { on in
                        engine.mode = on ? .strict : .copy
                        // Reset input/feedback when switching mode to avoid confusing carryover
                        engine.input = ""
                        engine.statusText = ""
                        engine.statusKind = .neutral
                    }
                ))
                .toggleStyle(.switch)
                .font(.caption)
            }
        }
    }
}
