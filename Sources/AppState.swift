import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

@MainActor final class AppState: ObservableObject {
    @Published var config = AppConfig()
    @Published var subtitles: [Subtitle] = []
    @Published var live = ""
    @Published var status = "准备好，开始听日语"
    @Published var isListening = false
    @Published var isStarting = false
    @Published var audioLevel = 0.0
    @Published var captureError: String?
    @Published var selectedIDs: Set<UUID> = []
    @Published var selectedText = ""
    @Published var analysis: Analysis?
    @Published var analyzing = false
    @Published var analysisError: String?
    @Published var chat: [ChatMessage] = []
    @Published var answering = false
    @Published var chatError: String?
    @Published var notes: [SavedNote] = []
    @Published var followLatest = true
    @Published var demo = false
    @Published var toast: String?
    var showAnalysis: (() -> Void)?
    var showSettings: (() -> Void)?
    var settingsChanged: (() -> Void)?
    private var audio: AudioCapture?
    private var captureTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var chatTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var speech = AVSpeechSynthesizer()
    private var selectionGeneration = UUID()
    private var captureGeneration = UUID()
    private var anchor: UUID?
    private var offset = 0.0
    private var phraseStart = 0.0
    private var cache: [String: Analysis] = [:]
    private var beforeDemo: [Subtitle]?
    let storage: URL

    init(storage: URL? = nil, restore: Bool = true) {
        self.storage = storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kotoba", isDirectory: true)
        if restore { load() }
    }
    private func load() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: storage.appendingPathComponent("settings.json")), let settings = try? decoder.decode(AppConfig.self, from: data) { config = settings }
        if let data = try? Data(contentsOf: storage.appendingPathComponent("subtitles.json")), let rows = try? decoder.decode([Subtitle].self, from: data) {
            subtitles = Array(rows.suffix(2000)); if !rows.isEmpty { status = "上次记录 · \(subtitles.count) 句" }
        }
        if let data = try? Data(contentsOf: storage.appendingPathComponent("notes.json")), let saved = try? decoder.decode([SavedNote].self, from: data) { notes = saved }
    }
    func persist() {
        guard !demo else { return }
        do {
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: storage.appendingPathComponent("settings.json"), options: .atomic)
            try encoder.encode(Array(subtitles.suffix(2000))).write(to: storage.appendingPathComponent("subtitles.json"), options: .atomic)
            try encoder.encode(notes).write(to: storage.appendingPathComponent("notes.json"), options: .atomic)
        } catch { toast = "本地保存失败：\(error.localizedDescription)" }
    }
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(nanoseconds: 500_000_000); if !Task.isCancelled { persist() } }
    }
    func applyConfig(_ newConfig: AppConfig, newKey: String?, newKeys: [String: String] = [:]) throws {
        _ = try newConfig.endpoint()
        for (account, key) in newKeys { try KeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: account) }
        if let newKey { try KeyStore.save(newKey.trimmingCharacters(in: .whitespacesAndNewlines), account: newConfig.keyAccount) }
        let changed = config.aiProfile != newConfig.aiProfile || newKey != nil || !newKeys.isEmpty
        config = newConfig
        config.rememberProfile()
        cache = [:]
        if changed {
            analysisTask?.cancel(); chatTask?.cancel(); selectionGeneration = UUID()
            analyzing = false; answering = false
            if !demo {
                analysis = nil; chat = []; chatError = nil
                analysisError = selectedText.isEmpty ? nil : "AI 设置已更新，点击重试使用新服务分析。"
            }
        }
        // Settings are saved even if the user is previewing the sample.
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try JSONEncoder().encode(config).write(to: storage.appendingPathComponent("settings.json"), options: .atomic)
        settingsChanged?()
    }
    func togglePinned() { config.pinned.toggle(); settingsChanged?(); persist() }
    func toggleCapture() { if isListening || isStarting { stopCapture() } else { startCapture() } }
    func startCapture() {
        guard !isListening, !isStarting else { return }
        if demo { exitDemo() }
        captureError = nil; isStarting = true; status = "正在连接声音…"
        let token = UUID(); captureGeneration = token
        let capture = AudioCapture(); audio = capture
        offset = (subtitles.last?.end ?? -1) + 1; phraseStart = offset
        capture.onText = { [weak self] complete, live, elapsed in
            guard let self, self.captureGeneration == token else { return }
            let end = self.offset + elapsed
            for text in complete {
                self.subtitles.append(Subtitle(text: text, start: self.phraseStart, end: max(self.phraseStart + 0.3, end)))
                self.phraseStart = end
            }
            if self.subtitles.count > 2000 { self.subtitles.removeFirst(self.subtitles.count - 2000) }
            self.live = live
            if !complete.isEmpty { self.scheduleSave() }
        }
        capture.onLevel = { [weak self] value in guard self?.captureGeneration == token else { return }; self?.audioLevel = value }
        capture.onMode = { [weak self] mode in
            Task { @MainActor in guard let self, self.captureGeneration == token else { return }; self.status = "\(self.config.sourceName) · \(mode)" }
        }
        capture.onFailure = { [weak self] message in
            guard let self, self.captureGeneration == token else { return }
            self.stopCapture(); self.captureError = message
        }
        let settings = config
        captureTask = Task {
            do {
                try await capture.start(config: settings)
                guard !Task.isCancelled, captureGeneration == token else { await capture.stop(); return }
                isStarting = false; isListening = true
            } catch {
                await capture.stop()
                guard captureGeneration == token else { return }
                isStarting = false; isListening = false; status = "未开始识别"
                if !(error is CancellationError) { captureError = error.localizedDescription }
            }
        }
    }
    func stopCapture() {
        captureTask?.cancel()
        let previous = audio; audio = nil
        isListening = false; isStarting = false; audioLevel = 0
        status = demo ? "示例模式 · 未采集声音" : subtitles.isEmpty ? "准备好，开始听日语" : "已暂停 · \(subtitles.count) 句"
        Task { await previous?.stop(); persist() }
    }
    func select(_ subtitle: Subtitle, extending: Bool) {
        if extending, let anchor, let a = subtitles.firstIndex(where: { $0.id == anchor }), let b = subtitles.firstIndex(where: { $0.id == subtitle.id }) {
            selectedIDs = Set(subtitles[min(a, b)...max(a, b)].map(\.id))
        } else { selectedIDs = [subtitle.id]; anchor = subtitle.id }
        let text = subtitles.filter { selectedIDs.contains($0.id) }.map(\.text).joined(separator: "\n")
        guard text.count <= 6000 else { selectedIDs = [subtitle.id]; selectedText = subtitle.text; prepareAnalysis(); return }
        selectedText = text; prepareAnalysis()
    }
    private func prepareAnalysis() {
        analysisTask?.cancel(); chatTask?.cancel()
        selectionGeneration = UUID(); chat = []; answering = false; chatError = nil
        analysis = nil; analysisError = nil; analyzing = false
        showAnalysis?()
        if demo {
            analysis = Self.demoAnalysis
            if selectedText != "私の住所を知っていますか。" {
                analysis = nil
                analysisError = "示例模式：请点击「私の住所を知っていますか。」查看完整示例。分析自己的内容请导入字幕或开始识别。"
            }
            return
        }
        analyze()
    }
    func analyze() {
        guard !selectedText.isEmpty else { return }
        analysisTask?.cancel()
        let text = selectedText
        let token = selectionGeneration
        if let cached = cache[text] { analysis = cached; analysisError = nil; return }
        analyzing = true; analysisError = nil
        let service = AIService(config: config, key: KeyStore.read(account: config.keyAccount))
        analysisTask = Task {
            do {
                let value = try await service.analyze(text)
                guard !Task.isCancelled, token == selectionGeneration else { return }
                analysis = value; cache[text] = value; analyzing = false
            } catch {
                guard !Task.isCancelled, token == selectionGeneration else { return }
                analyzing = false; analysisError = error.localizedDescription
            }
        }
    }
    func ask(_ question: String) {
        let question = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !question.isEmpty, !answering else { return }
        chatError = nil
        if demo { chatError = "这是界面示例。导入或识别真实字幕、配置 API Key 后即可提问。"; return }
        chat.append(ChatMessage(role: "user", content: question))
        sendChat()
    }
    func retryChat() { guard chat.last?.role == "user", !answering else { return }; sendChat() }
    private func sendChat() {
        chatError = nil; answering = true
        let token = selectionGeneration, text = selectedText, value = analysis, history = chat
        let service = AIService(config: config, key: KeyStore.read(account: config.keyAccount))
        chatTask = Task {
            do {
                let reply = try await service.ask(text: text, analysis: value, history: history)
                guard !Task.isCancelled, token == selectionGeneration else { return }
                chat.append(ChatMessage(role: "assistant", content: reply)); answering = false
            } catch {
                guard !Task.isCancelled, token == selectionGeneration else { return }
                chatError = error.localizedDescription; answering = false
            }
        }
    }
    func clearSelection() {
        selectionGeneration = UUID(); analysisTask?.cancel(); chatTask?.cancel()
        selectedIDs = []; selectedText = ""; analysis = nil; chat = []; analyzing = false; answering = false
    }
    func bookmark() {
        guard let analysis else { return }
        if notes.contains(where: { $0.text == selectedText }) { toast = "这句话已经收藏"; return }
        notes.insert(SavedNote(text: selectedText, analysis: analysis), at: 0)
        persist(); toast = "已加入学习笔记，可从菜单导出"
    }
    func speak(_ text: String) {
        speech.stopSpeaking(at: .immediate)
        let phrase = AVSpeechUtterance(string: text)
        phrase.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        phrase.rate = 0.42
        speech.speak(phrase)
    }
    func importText(_ text: String) {
        guard !isListening && !isStarting else { captureError = "请先暂停识别，再导入字幕。"; return }
        let parsed = SubtitleParser.parse(text)
        guard !parsed.isEmpty else { captureError = "没有找到有效字幕。支持 SRT、VTT，或每行一句的文本。"; return }
        if demo { exitDemo() }
        clearSelection(); subtitles.append(contentsOf: parsed)
        subtitles = Array(subtitles.suffix(2000)); status = "已导入 · \(parsed.count) 句"; captureError = nil
        persist()
    }
    func chooseSubtitleFile() {
        let panel = NSOpenPanel(); panel.title = "导入日语字幕"; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText, UTType(filenameExtension: "vtt") ?? .plainText, .plainText]
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                guard data.count < 5_000_000 else { throw AppError.message("字幕文件过大，请导入小于 5 MB 的文件。") }
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .shiftJIS) else { throw AppError.message("无法识别文件编码，请另存为 UTF-8。") }
                self?.importText(text)
            } catch { self?.captureError = error.localizedDescription }
        }
    }
    func loadDemo() {
        guard !isListening && !isStarting else { return }
        if !demo { beforeDemo = subtitles }
        demo = true; clearSelection(); captureError = nil
        subtitles = [Subtitle(text: "ここに住んでいます。", start: 492, end: 497, source: "示例"),
            Subtitle(text: "私の住所を知っていますか。", start: 498, end: 503, source: "示例"),
            Subtitle(text: "はい、知っています。", start: 505, end: 509, source: "示例"),
            Subtitle(text: "いいえ、知りません。", start: 511, end: 515, source: "示例")]
        status = "示例模式 · 未采集声音"
    }
    private func exitDemo() {
        subtitles = beforeDemo ?? []; beforeDemo = nil; demo = false; clearSelection()
    }
    func clearTranscript() {
        guard !isListening && !isStarting else { return }
        let alert = NSAlert(); alert.messageText = "清空当前字幕？"; alert.informativeText = "收藏的学习笔记会保留。需要的字幕可先从菜单导出。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "清空")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        demo = false; beforeDemo = nil; subtitles = []; live = ""; clearSelection(); status = "准备好，开始听日语"; persist()
    }
    func exportSubtitles() { save(SubtitleParser.srt(subtitles), name: "Kotoba-字幕.srt") }
    func exportNotes() {
        let text = "# Kotoba 学习笔记\n\n" + notes.map { note in
            "## \(note.text)\n\n\(note.analysis.translation)\n\n" + note.analysis.grammar.map { "### \($0.title)\n\n\($0.explanation)\n\n\($0.example ?? "")" }.joined(separator: "\n\n") + "\n\n" + note.analysis.vocabulary.map { "- \($0.word)（\($0.reading)）：\($0.meaning) · \($0.level)（参考）" }.joined(separator: "\n")
        }.joined(separator: "\n\n---\n\n")
        save(text, name: "Kotoba-学习笔记.md")
    }
    private func save(_ text: String, name: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { self?.toast = "导出失败：\(error.localizedDescription)" }
        }
    }
    static let demoAnalysis = Analysis(translation: "你知道我的住址吗？", grammar: [
        Grammar(title: "知っています", explanation: "「知る」的て形＋います，表示知道这一持续的状态。否定通常用「知りません」。", example: "その人を知っています。\n我认识那个人。"),
        Grammar(title: "〜か", explanation: "句末的「か」表示礼貌的疑问。这里在询问对方是否知道。", example: nil)
    ], vocabulary: [Vocabulary(word: "住所", reading: "じゅうしょ", meaning: "住址；地址", level: "N4"), Vocabulary(word: "知る", reading: "しる", meaning: "知道；知晓", level: "N5")], nuance: "这是礼貌体表达。「住所」指具体地址，也可根据上下文译为住址。")
}
