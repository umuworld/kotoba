import Foundation

struct Subtitle: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var source: String = "实时识别"
    var timeLabel: String { Self.clock(start) }
    static func clock(_ time: TimeInterval) -> String {
        let t = max(0, Int(time))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%02d:%02d", t / 60, t % 60)
    }
}

struct Grammar: Codable, Identifiable {
    var title: String
    var explanation: String
    var example: String?
    var id: String { title + explanation }
}
struct Vocabulary: Codable, Identifiable {
    var word: String
    var reading: String
    var meaning: String
    var level: String
    var id: String { word + reading }
}
struct Analysis: Codable {
    var translation: String
    var grammar: [Grammar]
    var vocabulary: [Vocabulary]
    var nuance: String?

    static func decode(_ text: String) throws -> Analysis {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") else {
            throw AppError.message("AI 没有返回完整的解析数据，请重试或检查模型设置。")
        }
        do {
            let value = try JSONDecoder().decode(Analysis.self, from: Data(cleaned[start...end].utf8))
            guard !value.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppError.message("翻译内容为空，请重试。")
            }
            return value
        } catch { throw AppError.message("AI 返回的解析格式不完整，请重试或换一个模型。") }
    }
}
struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    var role: String
    var content: String
}
struct SavedNote: Identifiable, Codable {
    var id = UUID()
    var text: String
    var analysis: Analysis
    var date = Date()
}
enum APIFormat: String, Codable, CaseIterable, Identifiable {
    case chatCompletions, responses, anthropic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .chatCompletions: return "Chat Completions（兼容接口）"
        case .responses: return "OpenAI Responses"
        case .anthropic: return "Anthropic Messages"
        }
    }
    var suffix: String {
        switch self { case .chatCompletions: return "chat/completions"; case .responses: return "responses"; case .anthropic: return "messages" }
    }
}
struct AIProfile: Codable, Equatable {
    var baseURL: String
    var model: String
    var format: APIFormat
}
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case deepSeek, openAI, claude, gemini, qwen, kimi, openRouter, ollama, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .openAI: return "OpenAI"
        case .claude: return "Claude · Anthropic"
        case .gemini: return "Gemini · Google"
        case .qwen: return "通义千问 · 阿里云"
        case .kimi: return "Kimi · 月之暗面"
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama · 本机模型"
        case .custom: return "自定义服务"
        }
    }
    var preset: AIProfile {
        switch self {
        case .deepSeek: return AIProfile(baseURL: "https://api.deepseek.com", model: "deepseek-flash", format: .chatCompletions)
        case .openAI: return AIProfile(baseURL: "https://api.openai.com/v1", model: "gpt-4.1-mini", format: .responses)
        case .claude: return AIProfile(baseURL: "https://api.anthropic.com/v1", model: "claude-sonnet-4-6", format: .anthropic)
        case .gemini: return AIProfile(baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", model: "gemini-3.8-flash", format: .chatCompletions)
        case .qwen: return AIProfile(baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", format: .chatCompletions)
        case .kimi: return AIProfile(baseURL: "https://api.moonshot.cn/v1", model: "kimi-k3", format: .chatCompletions)
        case .openRouter: return AIProfile(baseURL: "https://openrouter.ai/api/v1", model: "", format: .chatCompletions)
        case .ollama: return AIProfile(baseURL: "http://localhost:11434/v1", model: "", format: .chatCompletions)
        case .custom: return AIProfile(baseURL: "", model: "", format: .chatCompletions)
        }
    }
    var hint: String {
        switch self {
        case .ollama: return "先启动 Ollama，再填写已下载的模型名称。本机服务无需 API Key。"
        case .openRouter: return "填写你在 OpenRouter 选择的完整模型 ID（服务商/模型名）。"
        case .qwen: return "预设地址为中国内地地域；其他地域请按你的阿里云账户修改地址。"
        case .custom: return "填写 API 基础地址、模型名，并选择该服务实际支持的接口格式。"
        default: return "模型名可自由修改，以服务商账户的可用模型为准。需要 API 平台密钥，聊天会员不等于 API 额度。"
        }
    }
}
struct AppConfig: Codable {
    var baseURL = "https://api.deepseek.com"
    var model = "deepseek-flash"
    var audioSource = "com.google.Chrome"
    var locale = "ja-JP"
    var localOnly = true
    var fontSize: Double = 19
    // Retained for decoding older settings; clear glass is no longer used under text.
    var glassClear = false
    var readingOpacity: Double = 0.96
    var frostTint: Double = 0
    var frostStyleVersion = 2
    var pinned = true
    var provider: AIProvider = .deepSeek
    var apiFormat: APIFormat = .chatCompletions
    var profiles: [String: AIProfile] = [:]

    init() {}
    enum CodingKeys: String, CodingKey {
        case baseURL, model, audioSource, locale, localOnly, fontSize, glassClear, readingOpacity, frostTint, frostStyleVersion, pinned, provider, apiFormat, profiles
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? baseURL
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? model
        audioSource = try c.decodeIfPresent(String.self, forKey: .audioSource) ?? audioSource
        locale = try c.decodeIfPresent(String.self, forKey: .locale) ?? locale
        localOnly = try c.decodeIfPresent(Bool.self, forKey: .localOnly) ?? localOnly
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize
        glassClear = try c.decodeIfPresent(Bool.self, forKey: .glassClear) ?? glassClear
        readingOpacity = min(1, max(0.90, try c.decodeIfPresent(Double.self, forKey: .readingOpacity) ?? 0.96))
        let savedTint = try c.decodeIfPresent(Double.self, forKey: .frostTint) ?? 0
        let savedStyle = try c.decodeIfPresent(Int.self, forKey: .frostStyleVersion) ?? 1
        // Migrate only the previous default; preserve manually adjusted tint.
        frostTint = savedStyle < 2 && abs(savedTint - 0.12) < 0.001 ? 0 : min(0.40, max(0, savedTint))
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? pinned
        provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? (URL(string: baseURL)?.host == "api.deepseek.com" ? .deepSeek : .custom)
        apiFormat = try c.decodeIfPresent(APIFormat.self, forKey: .apiFormat) ?? .chatCompletions
        profiles = try c.decodeIfPresent([String: AIProfile].self, forKey: .profiles) ?? [:]
    }
    var aiProfile: AIProfile { AIProfile(baseURL: baseURL, model: model, format: apiFormat) }
    mutating func rememberProfile() { profiles[provider.rawValue] = aiProfile }
    mutating func selectProvider(_ next: AIProvider) {
        rememberProfile()
        provider = next
        useProfile(profiles[next.rawValue] ?? next.preset)
    }
    mutating func useProfile(_ profile: AIProfile) {
        baseURL = profile.baseURL; model = profile.model; apiFormat = profile.format
    }

    func endpoint() throws -> URL {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var c = URLComponents(string: raw), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.scheme == "https" || (c.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw AppError.message("服务地址须为 HTTPS；本机服务可用 http://localhost 或 http://127.0.0.1。")
        }
        var path = c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Accept a base URL or any supported full endpoint; never append twice.
        for format in APIFormat.allCases {
            if path == format.suffix { path = ""; break }
            if path.hasSuffix("/" + format.suffix) { path = String(path.dropLast(format.suffix.count + 1)); break }
        }
        path += path.isEmpty ? apiFormat.suffix : "/" + apiFormat.suffix
        c.path = "/" + path
        guard let url = c.url else { throw AppError.message("服务地址格式不正确。") }
        return url
    }
    var keyAccount: String { (try? endpoint().absoluteString) ?? baseURL }
    var sourceName: String {
        switch audioSource {
        case "com.google.Chrome": return "Chrome"
        case "com.apple.Safari": return "Safari"
        case "com.microsoft.edgemac": return "Edge"
        default: return "系统声音"
        }
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum SubtitleParser {
    static func parse(_ input: String) -> [Subtitle] {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\u{feff}", with: "")
        let blocks = normalized.components(separatedBy: "\n\n")
        var result: [Subtitle] = []
        let timed = normalized.contains("-->")
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            if let i = lines.firstIndex(where: { $0.contains("-->") }) {
                let times = lines[i].components(separatedBy: "-->")
                guard times.count == 2, let start = timestamp(times[0]), let end = timestamp(times[1]), end >= start else { continue }
                let text = clean(lines.dropFirst(i + 1).joined(separator: "\n"))
                if !text.isEmpty { result.append(Subtitle(text: text, start: start, end: end, source: "导入字幕")) }
            } else if !timed {
                for line in lines {
                    let text = clean(line)
                    if text.isEmpty || text == "WEBVTT" { continue }
                    let time = Double(result.count * 4)
                    result.append(Subtitle(text: text, start: time, end: time + 4, source: "手动文本"))
                }
            }
        }
        return result.sorted { $0.start < $1.start }
    }
    static func timestamp(_ text: String) -> Double? {
        guard let token = text.trimmingCharacters(in: .whitespaces).split(separator: " ").first else { return nil }
        let parts = token.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var value = 0.0
        for p in parts { guard let n = Double(p), n >= 0, n.isFinite else { return nil }; value = value * 60 + n }
        return value
    }
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func srt(_ rows: [Subtitle]) -> String {
        func stamp(_ value: Double) -> String {
            let ms = max(0, Int(value * 1000))
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
        }
        return rows.enumerated().map { i, s in "\(i + 1)\n\(stamp(s.start)) --> \(stamp(max(s.end, s.start + 0.3)))\n\(s.text)" }.joined(separator: "\n\n") + "\n"
    }
}

/// A recognition request revises its entire transcript. Return only new, complete
/// sentences; leave the final unfinished sentence available for live display.
struct TranscriptAssembler {
    private(set) var committed = ""
    private(set) var live = ""
    mutating func update(_ cumulative: String, final: Bool = false) -> [String] {
        let text = cumulative.trimmingCharacters(in: .whitespacesAndNewlines)
        var rest: String
        if text.hasPrefix(committed) { rest = String(text.dropFirst(committed.count)) }
        else if text.count >= committed.count { rest = String(text.dropFirst(committed.count)) }
        else { return [] }
        var output: [String] = []
        while let end = rest.firstIndex(where: { "。！？!?\n".contains($0) }) {
            let boundary = rest.index(after: end)
            let piece = String(rest[..<boundary])
            committed += piece
            rest = String(rest[boundary...])
            let clean = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { output.append(clean) }
        }
        if final && !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output.append(rest.trimmingCharacters(in: .whitespacesAndNewlines))
            committed += rest
            rest = ""
        }
        live = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return output
    }
}
