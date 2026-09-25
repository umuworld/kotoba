import Foundation
import AVFoundation
import CoreMedia

enum SelfTests {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw AppError.message(message) }
        print("PASS \(message)")
    }
    static func run() throws {
        let srt = "1\r\n00:08:18,120 --> 00:08:23,500\r\n私の住所を\r\n知っていますか。\r\n\r\n2\r\n00:08:25,000 --> 00:08:28,000\r\nはい。\r\n"
        let parsed = SubtitleParser.parse(srt)
        try check(parsed.count == 2, "SRT parses CRLF and multiline cues")
        try check(abs(parsed[0].start - 498.12) < 0.001 && parsed[0].text.contains("\n"), "Cue timestamps and line breaks survive")
        let vtt = "WEBVTT\n\nNOTE a comment\nignored\n\ncue-1\n08:18.120 --> 08:23.500 align:start\n<v Teacher><b>住所</b>を知っていますか。\n"
        let v = SubtitleParser.parse(vtt)
        try check(v.count == 1 && v[0].text == "住所を知っていますか。", "VTT cue settings, tags and notes")
        try check(SubtitleParser.parse("1\nxx --> 00:02:00\n不正\n").isEmpty, "Malformed timed cues are rejected")
        try check(SubtitleParser.parse("1\n00:05.000 --> 00:01.000\n不正\n").isEmpty, "Negative cue duration is rejected")
        let roundTrip = SubtitleParser.parse(SubtitleParser.srt(parsed))
        try check(roundTrip.map(\.text) == parsed.map(\.text) && abs(roundTrip[0].start - parsed[0].start) < 0.002, "SRT export/import round trip")
        try check(SubtitleParser.parse("こんにちは。\n\n元気ですか。").count == 2, "Plain-text import")
        var a = TranscriptAssembler()
        try check(a.update("私の住所").isEmpty && a.live == "私の住所", "Partial recognition remains provisional")
        try check(a.update("私の住所を知っていますか。はい").count == 1 && a.live == "はい", "Complete sentence emits once")
        try check(a.update("私の住所を知っていますか。はい").isEmpty, "Repeated speech hypotheses do not duplicate")
        try check(a.update("私の住所を知っていますか。はい", final: true) == ["はい"], "Final remainder is flushed")
        let raw = "```json\n{\"translation\":\"你好\",\"grammar\":[],\"vocabulary\":[]}\n```"
        try check(try Analysis.decode(raw).translation == "你好", "Fenced JSON response decoding")
        do { _ = try Analysis.decode("{broken}"); throw AppError.message("Invalid JSON accepted") } catch AppError.message(let message) { try check(message != "Invalid JSON accepted", "Malformed AI output is rejected") }
        var config = AppConfig()
        try check(try config.endpoint().absoluteString == "https://api.deepseek.com/chat/completions", "Endpoint normalization")
        config.baseURL = "https://example.com/v1/"
        try check(try config.endpoint().path == "/v1/chat/completions", "Compatible API version path is preserved")
        config.baseURL = "https://example.com/v1/chat/completions"
        try check(try config.endpoint().path == "/v1/chat/completions", "Full endpoint is not duplicated")
        config.baseURL = "http://example.com"
        do { _ = try config.endpoint(); throw AppError.message("HTTP accepted") } catch AppError.message(let message) { try check(message != "HTTP accepted", "Remote HTTP endpoints rejected before sending secrets") }
        config.baseURL = "http://127.0.0.1:8765/v1"
        try check(try config.endpoint().host == "127.0.0.1", "Local model endpoint supported")
        let legacy = Data("{\"baseURL\":\"https://api.deepseek.com\",\"model\":\"my-model\",\"fontSize\":23,\"pinned\":false}".utf8)
        var migrated = try JSONDecoder().decode(AppConfig.self, from: legacy)
        try check(migrated.provider == .deepSeek && migrated.model == "my-model" && migrated.fontSize == 23 && !migrated.pinned, "Legacy settings migrate without losing user preferences")
        try check(migrated.keyAccount == AppConfig().keyAccount, "Legacy DeepSeek Keychain account remains unchanged")
        migrated.selectProvider(.openAI); migrated.model = "custom-openai-model"
        migrated.selectProvider(.claude)
        try check(try migrated.endpoint().absoluteString == "https://api.anthropic.com/v1/messages", "Claude native endpoint")
        migrated.selectProvider(.openAI)
        try check(migrated.model == "custom-openai-model" && migrated.apiFormat == .responses, "Switching restores each provider's edited model and format")
        migrated.selectProvider(.deepSeek)
        try check(migrated.model == "my-model", "Switching back restores migrated configuration")
        let restored = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(migrated))
        try check(restored.profiles[AIProvider.openAI.rawValue]?.model == "custom-openai-model", "Provider profiles persist across launches without keys")
        for provider in AIProvider.allCases where provider != .custom {
            config.selectProvider(provider)
            try check(try config.endpoint().path.hasSuffix(config.apiFormat.suffix), "\(provider.label) preset uses the correct endpoint")
        }
        config.baseURL = "https://example.com/v1/chat/completions"; config.apiFormat = .responses
        try check(try config.endpoint().path == "/v1/responses", "Changing protocol replaces an existing endpoint suffix")
        let responsesAccount = config.keyAccount
        config.apiFormat = .anthropic
        try check(config.keyAccount != responsesAccount, "Keys are isolated by protocol and endpoint")
        config = try JSONDecoder().decode(AppConfig.self, from: Data("{\"baseURL\":\"https://my-provider.example/v1\",\"model\":\"legacy-custom\"}".utf8))
        try check(config.provider == .custom && config.apiFormat == .chatCompletions && config.model == "legacy-custom", "Legacy third-party service remains a compatible custom profile")
        let oldGlass = try JSONDecoder().decode(AppConfig.self, from: Data("{\"glassClear\":true}".utf8))
        try check(oldGlass.frostTint == 0, "Original clear-glass settings migrate without extra opaque tint")
        let oldOpaque = try JSONDecoder().decode(AppConfig.self, from: Data("{\"readingOpacity\":1}".utf8))
        try check(oldOpaque.frostTint == 0, "Version 1.1.1 opaque backing does not override the new frosted default")
        let previousFrost = try JSONDecoder().decode(AppConfig.self, from: Data("{\"frostTint\":0.12}".utf8))
        try check(previousFrost.frostTint == 0, "Previous 12 percent default migrates to the lighter reference style")
        let manualFrost = try JSONDecoder().decode(AppConfig.self, from: Data("{\"frostTint\":0.12,\"frostStyleVersion\":2}".utf8))
        try check(manualFrost.frostTint == 0.12, "New manual tint choices remain adjustable and persist")
        let tooStrong = try JSONDecoder().decode(AppConfig.self, from: Data("{\"frostTint\":1}".utf8))
        try check(tooStrong.frostTint == 0.40, "Tint is bounded without removing the background blur")
        config.frostTint = 0.24
        let frosted = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        try check(frosted.frostTint == 0.24, "Frost tint preference persists")
    }
    static func network() async throws {
        var config = AppConfig(); config.baseURL = "http://127.0.0.1:18765/v1"; config.model = "test-success"
        for format in APIFormat.allCases {
            config.apiFormat = format; config.model = "test-success"
            let client = AIService(config: config, key: "fixture-token")
            let value = try await client.analyze("私の住所を知っていますか。")
            try check(value.translation == "你知道我的住址吗？", "\(format) real HTTP analysis with protocol-specific authentication and JSON")
            let reply = try await client.ask(text: "私の住所を知っていますか。", analysis: value, history: [ChatMessage(role: "user", content: "第一问"), ChatMessage(role: "assistant", content: "第一答"), ChatMessage(role: "user", content: "解释一下")])
            try check(reply == "这是一条测试回答。", "\(format) retains multi-turn conversation and sentence context")
            let ping = try await client.complete([["role": "user", "content": "请只回复 OK。"]])
            try check(ping == "OK", "\(format) settings connection test without a system message")
            for (model, expected) in [("test-401", "API Key"), ("test-429", "频繁"), ("test-malformed", "格式"), ("test-invalid-json", "格式"), ("test-truncated", "截断"), ("test-refused", "未能回答"), ("test-redirect", "跳转")] {
                config.model = model
                do { _ = try await AIService(config: config, key: "fixture-token").complete([["role": "user", "content": "test"]]); throw AppError.message("Unexpected success") }
                catch { try check(error.localizedDescription.contains(expected), "\(format) \(model) produces useful failure") }
            }
        }
        config.apiFormat = .chatCompletions; config.model = "test-local"
        let local = try await AIService(config: config, key: "").complete([["role": "user", "content": "请只回复 OK。"]])
        try check(local == "OK", "Local Ollama-compatible request works without an API key")
    }
    @MainActor static func state() throws {
        let surface = FrostedPanelView(frame: NSRect(x: 0, y: 0, width: 360, height: 600))
        try check(surface.backdrop.state == .active && surface.backdrop.blendingMode == .behindWindow, "Backdrop blur is fixed active, not coupled to window focus")
        try check(surface.backdrop.material == .hudWindow && !surface.backdrop.isEmphasized, "HUD material has no first-responder emphasis switching")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Kotoba-tests-" + UUID().uuidString)
        let app = AppState(storage: folder, restore: false)
        app.importText("最初の字幕です。\n二番目の字幕です。")
        try check(app.subtitles.count == 2, "Imported subtitles persist in app state")
        let saved = try Data(contentsOf: folder.appendingPathComponent("subtitles.json"))
        app.loadDemo()
        app.persist()
        try check(try Data(contentsOf: folder.appendingPathComponent("subtitles.json")) == saved, "Preview does not overwrite real history")
        app.select(app.subtitles[0], extending: false)
        app.select(app.subtitles[2], extending: true)
        try check(app.selectedIDs.count == 3, "Shift selection includes the full sentence range")
        app.importText("新しい字幕です。")
        try check(!app.demo && app.subtitles.count == 3 && app.subtitles[0].text == "最初の字幕です。", "Leaving preview restores original history before appending")
        let restored = AppState(storage: folder)
        try check(restored.subtitles.map(\.text) == app.subtitles.map(\.text), "History restores across app launches")
        app.loadDemo(); app.select(app.subtitles[1], extending: false)
        try check(app.analysis?.translation == "你知道我的住址吗？", "Demo analysis matches the selected sample")
        app.clearSelection()
        try check(app.selectedIDs.isEmpty && app.analysis == nil && app.chat.isEmpty, "Closing analysis clears contextual state")
    }
    static func speechFile(_ url: URL) async throws {
        final class Collected: @unchecked Sendable {
            let lock = NSLock()
            var values: [String] = []
            func append(_ text: [String]) { lock.lock(); defer { lock.unlock() }; values += text }
            func text() -> String { lock.lock(); defer { lock.unlock() }; return values.joined() }
        }
        let collected = Collected()
        let engine = LocalSpeech()
        engine.onProgress = { print($0) }
        engine.onText = { complete, live, _ in
            collected.append(complete)
            if !complete.isEmpty { print("FINAL: " + complete.joined()) }
            else if !live.isEmpty { print("LIVE: " + live) }
        }
        engine.onFailure = { print("RECOGNITION ERROR: " + $0) }
        try await engine.prepare(localeID: "ja-JP")
        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2048) else { throw AppError.message("No test buffer") }
            var frame: Int64 = 0
            while file.framePosition < file.length {
                try file.read(into: buffer, frameCount: 2048)
                var description: CMAudioFormatDescription?
                guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: buffer.format.streamDescription, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr else { throw AppError.message("Test format description failed") }
                var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(buffer.format.sampleRate)), presentationTimeStamp: CMTime(value: frame, timescale: Int32(buffer.format.sampleRate)), decodeTimeStamp: .invalid)
                var sample: CMSampleBuffer?
                guard CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: description, sampleCount: Int(buffer.frameLength), sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr, let sample else { throw AppError.message("Test sample buffer failed") }
                guard CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList) == noErr else { throw AppError.message("Test audio data copy failed") }
                engine.append(sample)
                frame += Int64(buffer.frameLength)
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            await engine.finish()
        } catch { await engine.finish(); throw error }
        let transcript = collected.text()
        try check(!transcript.isEmpty && transcript.contains("住所"), "Real on-device Japanese transcription recognizes the test sentence")
    }
}
