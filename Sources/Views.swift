import SwiftUI
import AppKit

/// A light tint over real, focus-independent backdrop blur; not an opaque sheet.
struct ReadingSurface<Content: View>: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency ? 1 : state.config.frostTint))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26)
                            .strokeBorder(.white.opacity(0.38), lineWidth: 0.8)
                            .padding(0.5)
                    }
                    .allowsHitTesting(false)
            }
    }
}

struct CircleTool: View {
    var icon: String
    var help: String
    var active = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 14, weight: .medium)).frame(width: 30, height: 30)
            .foregroundStyle(active ? Color.blue : Color.primary.opacity(0.75))
            .background(active ? Color.blue.opacity(0.13) : Color.primary.opacity(0.035), in: Circle()) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.20), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.27), lineWidth: 0.7)) }
}
struct ResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> GripView { GripView() }
    func updateNSView(_ nsView: GripView, context: Context) {}
    final class GripView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
            for i in [4.0, 8.0, 12.0] {
                let path = NSBezierPath(); path.lineWidth = 1.3
                path.move(to: NSPoint(x: bounds.maxX - i, y: 3)); path.line(to: NSPoint(x: bounds.maxX - 3, y: i)); path.stroke()
            }
        }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let initial = window.frame, origin = window.convertPoint(toScreen: event.locationInWindow)
            while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if event.type == .leftMouseUp { break }
                let point = window.convertPoint(toScreen: event.locationInWindow)
                let width = max(window.minSize.width, min(window.maxSize.width, initial.width + point.x - origin.x))
                let height = max(window.minSize.height, min(window.maxSize.height, initial.height - point.y + origin.y))
                window.setFrame(NSRect(x: initial.minX, y: initial.maxY - height, width: width, height: height), display: true)
            }
        }
    }
}

struct TranscriptView: View {
    @ObservedObject var state: AppState
    var close: () -> Void
    var settings: () -> Void
    var paste: () -> Void
    var resetPosition: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "captions.bubble").font(.system(size: 18, weight: .medium)).foregroundStyle(.blue)
                Text("悬浮字幕").font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 2)
                CircleTool(icon: state.config.pinned ? "pin.fill" : "pin", help: "置顶窗口", active: state.config.pinned) { state.togglePinned() }
                Menu {
                    Button("导入字幕文件…") { state.chooseSubtitleFile() }.disabled(state.isListening || state.isStarting)
                    Button("粘贴日语文本…", action: paste).disabled(state.isListening || state.isStarting)
                    Divider()
                    Button("导出当前字幕…") { state.exportSubtitles() }.disabled(state.subtitles.isEmpty)
                    Button("导出收藏笔记（\(state.notes.count)）…") { state.exportNotes() }.disabled(state.notes.isEmpty)
                    Divider()
                    Button("体验示例") { state.loadDemo() }.disabled(state.isListening || state.isStarting)
                    Button("清空字幕…") { state.clearTranscript() }.disabled(state.isListening || state.isStarting || state.subtitles.isEmpty)
                    Button("恢复窗口位置", action: resetPosition)
                    Button("设置…", action: settings)
                    Divider()
                    Button("退出 Kotoba") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("字幕与导出菜单")
                CircleTool(icon: "xmark", help: "隐藏窗口；可从菜单栏重新打开", action: close)
            }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14).background(WindowDragArea())

            HStack(spacing: 7) {
                Circle().fill(state.isListening ? Color.green : state.demo ? Color.orange : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                Text(state.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 1)
                if state.isStarting { ProgressView().controlSize(.small) }
                else if state.isListening {
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(0..<5) { i in Capsule().fill(.blue.opacity(0.7)).frame(width: 2.5, height: 3 + state.audioLevel * Double(8 + (i % 3) * 5)) }
                    }.frame(height: 18).animation(.easeOut(duration: 0.12), value: state.audioLevel)
                }
            }.padding(.horizontal, 23).padding(.bottom, 12)

            if let error = state.captureError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("打开设置", action: settings)
                        Button("关闭提示") { state.captureError = nil }
                    }.font(.system(size: 11))
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16).padding(.bottom, 8)
            }

            if state.subtitles.isEmpty && state.live.isEmpty {
                VStack(spacing: 18) {
                    Spacer()
                    Image(systemName: "waveform").font(.system(size: 37, weight: .ultraLight)).foregroundStyle(.blue.opacity(0.75))
                        .frame(width: 78, height: 78).background(.blue.opacity(0.065), in: RoundedRectangle(cornerRadius: 26))
                    Text(state.isListening ? "正在听，播放一段日语吧" : "把日语留在身边").font(.system(size: 18, weight: .medium))
                    Text(state.isListening ? "识别到的句子会逐步出现在这里。\n如果一直没有文字，请检查声音来源和识别语言。" : "将这个窗口拖到视频右侧。\n开始聆听后，点击一句话就能深入学习。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                    if !state.isListening {
                        Button("先看看示例") { state.loadDemo() }.buttonStyle(.plain).foregroundStyle(.blue).font(.system(size: 12))
                    }
                    Spacer()
                }.padding(22).frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            ForEach(state.subtitles) { subtitle in
                                Button {
                                    state.select(subtitle, extending: NSEvent.modifierFlags.contains(.shift))
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(subtitle.timeLabel).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                        Text(subtitle.text).font(.system(size: state.config.fontSize, weight: state.selectedIDs.contains(subtitle.id) ? .medium : .regular))
                                            .lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                                    }.padding(.horizontal, 15).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(state.selectedIDs.contains(subtitle.id) ? Color.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(state.selectedIDs.contains(subtitle.id) ? Color.blue.opacity(0.25) : .clear, lineWidth: 1))
                                        .contentShape(RoundedRectangle(cornerRadius: 16))
                                }.buttonStyle(.plain).id(subtitle.id).help("点击分析；按住 Shift 点击可选择多句")
                                    .contextMenu {
                                        Button("复制句子") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(subtitle.text, forType: .string) }
                                        Button("朗读") { state.speak(subtitle.text) }
                                    }
                            }
                            if !state.live.isEmpty {
                                Text(state.live + " …").font(.system(size: state.config.fontSize)).foregroundStyle(.secondary)
                                    .lineSpacing(6).padding(15).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("latest")
                        }.padding(.horizontal, 10).padding(.bottom, 16)
                    }.scrollIndicators(.hidden)
                        .onChange(of: state.subtitles.count) { _, _ in if state.followLatest { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("latest", anchor: .bottom) } } }
                        .onChange(of: state.live) { _, _ in if state.followLatest { proxy.scrollTo("latest", anchor: .bottom) } }
                        .onChange(of: state.followLatest) { _, value in if value { proxy.scrollTo("latest", anchor: .bottom) } }
                }
            }

            VStack(spacing: 11) {
                Rectangle().fill(Color.primary.opacity(0.065)).frame(height: 0.5)
                HStack(spacing: 10) {
                    Button { state.toggleCapture() } label: {
                        HStack(spacing: 7) { Image(systemName: state.isListening || state.isStarting ? "pause.fill" : "waveform"); Text(state.isListening || state.isStarting ? "暂停" : "开始聆听") }
                            .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 9)
                            .foregroundStyle(.white).background(.blue.gradient, in: Capsule())
                    }.buttonStyle(.plain).help("开始或暂停采集所选应用的声音")
                    Spacer(minLength: 0)
                    CircleTool(icon: "arrow.down.to.line", help: "自动跟随最新字幕", active: state.followLatest) { state.followLatest.toggle() }
                    CircleTool(icon: "slider.horizontal.3", help: "设置", action: settings)
                }
                HStack {
                    Text(state.demo ? "示例内容 · 未连接识别或 AI" : "点击一句深入学习 · Shift 连选多句").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    ResizeGrip().frame(width: 18, height: 16).help("拖动调整长宽，也可拖动任意窗口边缘")
                }
            }.padding(.horizontal, 20).padding(.bottom, 13)
        }.foregroundStyle(Color.primary)
    }
}

struct AnalysisView: View {
    @ObservedObject var state: AppState
    var close: () -> Void
    var settings: () -> Void
    @State private var question = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(.blue)
                Text("句子解析").font(.system(size: 15, weight: .semibold))
                if state.demo { Text("示例").font(.system(size: 10)).padding(.horizontal, 7).padding(.vertical, 3).background(.orange.opacity(0.12), in: Capsule()) }
                Spacer()
                CircleTool(icon: "speaker.wave.2", help: "朗读选中的句子") { state.speak(state.selectedText) }
                CircleTool(icon: "bookmark", help: "收藏这条解析") { state.bookmark() }.disabled(state.analysis == nil)
                CircleTool(icon: "xmark", help: "关闭解析", action: close)
            }.padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 12).background(WindowDragArea())
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 14) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 17) {
                            Text(state.selectedText).font(.system(size: 22, weight: .medium)).lineSpacing(5).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                            if state.analyzing {
                                HStack(spacing: 9) { ProgressView().controlSize(.small); Text("正在理解这句话…").font(.system(size: 13)).foregroundStyle(.secondary) }.padding(.vertical, 20)
                            } else if let error = state.analysisError {
                                VStack(alignment: .leading, spacing: 13) {
                                    Text(error).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                                    HStack { Button("设置 AI", action: settings); Button("重试") { state.analyze() }.disabled(state.demo) }
                                }.padding(.vertical, 14)
                            } else if let analysis = state.analysis {
                                sectionTitle("中文翻译")
                                Text(analysis.translation).font(.system(size: 16)).lineSpacing(5).textSelection(.enabled)
                                Divider().opacity(0.4)
                                sectionTitle("语法分析")
                                ForEach(analysis.grammar) { grammar in
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(grammar.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.blue)
                                        Text(grammar.explanation).font(.system(size: 13)).lineSpacing(5)
                                        if let example = grammar.example, !example.isEmpty { Text(example).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).padding(.top, 2) }
                                    }.textSelection(.enabled)
                                }
                                Divider().opacity(0.4)
                                HStack { sectionTitle("JLPT 生词"); Spacer(); Text("等级为参考").font(.system(size: 10)).foregroundStyle(.tertiary) }
                                ForEach(analysis.vocabulary) { word in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text(word.word).font(.system(size: 16, weight: .medium))
                                            Text(word.reading).font(.system(size: 12)).foregroundStyle(.secondary)
                                            Spacer(minLength: 1)
                                            Text(word.level).font(.system(size: 10)).foregroundStyle(.blue).padding(.horizontal, 7).padding(.vertical, 3).background(.blue.opacity(0.075), in: Capsule())
                                        }
                                        Text(word.meaning).font(.system(size: 13)).foregroundStyle(.secondary)
                                    }.padding(11).background(.white.opacity(0.20), in: RoundedRectangle(cornerRadius: 12)).textSelection(.enabled)
                                }
                                if let nuance = analysis.nuance, !nuance.isEmpty { Text(nuance).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled) }
                            }
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    }.scrollIndicators(.hidden).frame(width: max(270, (geo.size.width - 14) * 0.57))
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.18), in: RoundedRectangle(cornerRadius: 19))
                    chatPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.padding(.horizontal, 16)
            HStack {
                if let toast = state.toast { Text(toast).font(.system(size: 10)).foregroundStyle(.blue).lineLimit(1).onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { state.toast = nil } } }
                else { Text("\(state.config.model) · 结合上下文学习").font(.system(size: 10)).foregroundStyle(.tertiary) }
                Spacer(); ResizeGrip().frame(width: 18, height: 16)
            }.padding(.horizontal, 20).padding(.vertical, 9)
        }.onChange(of: state.selectedText) { _, _ in question = "" }
    }
    func sectionTitle(_ text: String) -> some View { Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
    var chatPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("继续提问").font(.system(size: 15, weight: .semibold)); Spacer() }
            Text("围绕当前\(state.selectedIDs.count > 1 ? "段落" : "句子")").font(.system(size: 10)).foregroundStyle(.blue)
                .padding(.horizontal, 9).padding(.vertical, 5).background(.blue.opacity(0.07), in: Capsule())
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if state.chat.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("不懂的地方，接着问。").font(.system(size: 13)).foregroundStyle(.secondary)
                                ForEach(["这里的语气是什么？", "可以换一种说法吗？", "给我两个相似例句"], id: \.self) { prompt in
                                    Button { state.ask(prompt) } label: { Text(prompt).font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 8).background(.white.opacity(0.3), in: Capsule()) }.buttonStyle(.plain)
                                }
                            }.padding(.top, 15)
                        }
                        ForEach(state.chat) { message in
                            Text(message.content).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == "user" ? Color.blue.opacity(0.12) : Color.white.opacity(0.40), in: RoundedRectangle(cornerRadius: 14)).id(message.id)
                        }
                        if state.answering { HStack(spacing: 7) { ProgressView().controlSize(.small); Text("正在思考…").font(.system(size: 11)).foregroundStyle(.secondary) }.padding(.vertical, 5) }
                        if let error = state.chatError { VStack(alignment: .leading, spacing: 7) { Text(error).font(.system(size: 11)).foregroundStyle(.orange); Button("重试") { state.retryChat() }.font(.system(size: 11)).disabled(state.demo) } }
                        Color.clear.frame(height: 1).id("chatEnd")
                    }
                }.scrollIndicators(.hidden).onChange(of: state.chat.count) { _, _ in withAnimation { proxy.scrollTo("chatEnd", anchor: .bottom) } }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 6) {
                TextField("问问这句话…", text: $question, axis: .vertical).textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...4)
                    .onSubmit { sendQuestion() }.disabled(state.answering)
                Button(action: sendQuestion) { Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).frame(width: 30, height: 30).background(.blue.gradient, in: Circle()) }
                    .buttonStyle(.plain).disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.answering).help("发送问题")
            }.padding(10).background(.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 19))
        }.padding(16).background(Color(nsColor: .textBackgroundColor).opacity(0.14), in: RoundedRectangle(cornerRadius: 19))
    }
    func sendQuestion() { let text = question; question = ""; state.ask(text) }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State var draft: AppConfig
    @State private var keyDrafts: [String: String] = [:]
    @State private var deletedKeys: Set<String> = []
    @State private var message = ""
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    @State private var testID = UUID()
    private var keyBinding: Binding<String> {
        Binding(get: { keyDrafts[draft.keyAccount] ?? "" }, set: {
            cancelTest(); deletedKeys.remove(draft.keyAccount); keyDrafts[draft.keyAccount] = $0
        })
    }
    private var pendingKeys: [String: String] {
        var keys = keyDrafts.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for account in deletedKeys { keys[account] = "" }
        return keys
    }
    var close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack { VStack(alignment: .leading, spacing: 4) { Text("让日语，留在身边。").font(.system(size: 24, weight: .semibold)); Text("Kotoba 设置").font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "captions.bubble").font(.system(size: 32)).foregroundStyle(.blue) }.padding(25)
            Form {
                Section("字幕与声音") {
                    Picker("声音来源", selection: $draft.audioSource) {
                        Text("Google Chrome").tag("com.google.Chrome")
                        Text("Safari").tag("com.apple.Safari")
                        Text("Microsoft Edge").tag("com.microsoft.edgemac")
                        Text("所有系统声音").tag("system")
                    }
                    Picker("识别语言", selection: $draft.locale) { Text("日语").tag("ja-JP"); Text("中文（中文教学讲解）").tag("zh-CN"); Text("英语").tag("en-US") }
                    Toggle("仅设备端识别", isOn: $draft.localOnly)
                    Text("设备端识别不上传音频，首次使用会从 Apple 下载语言模型并显示进度。关闭后允许 Apple 在线识别。修改后暂停再开始即可生效。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Button("声音采集权限") { openPrivacy("Privacy_ScreenCapture") }
                        Button("语音识别权限") { openPrivacy("Privacy_SpeechRecognition") }
                    }
                }
                Section("AI 翻译与解析") {
                    Picker("AI 服务商", selection: Binding(get: { draft.provider }, set: { draft.selectProvider($0) })) {
                        ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
                    }
                    Text(draft.provider.hint).font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("服务地址", text: $draft.baseURL)
                    TextField("模型名称", text: $draft.model)
                    Picker("接口格式", selection: $draft.apiFormat) {
                        ForEach(APIFormat.allCases) { Text($0.label).tag($0) }
                    }
                    SecureField("API Key（留空使用此接口已存密钥）", text: keyBinding)
                    Text("切换服务会记住各自配置。密钥保存在 macOS 钥匙串，按完整接口地址隔离，不会自动带到其他接口。仅分析、提问或测试连接时发出 AI 请求；费用由服务商收取。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Button("恢复本服务预设") { draft.useProfile(draft.provider.preset) }
                        Button(testing ? "连接中…" : "测试连接") { testConnection() }.disabled(testing)
                        Button("删除此接口密钥") {
                            cancelTest(); keyDrafts[draft.keyAccount] = ""; deletedKeys.insert(draft.keyAccount)
                            message = "已标记删除此接口密钥；保存设置后生效。"
                        }
                    }.font(.system(size: 11))
                }
                Section("窗口外观") {
                    HStack { Text("字幕字号"); Slider(value: $draft.fontSize, in: 14...28, step: 1); Text("\(Int(draft.fontSize))").monospacedDigit().frame(width: 25) }
                    HStack {
                        Text("磨砂底色")
                        Slider(value: $draft.frostTint, in: 0...0.40, step: 0.02)
                        Text("\(Int((draft.frostTint * 100).rounded()))%").monospacedDigit().frame(width: 38)
                    }
                    Text("背景始终经过磨砂模糊，点击、输入或切换窗口都不会切换成通透玻璃。默认 0% 不额外叠加底色，尽量透出背景色彩；滑块只调底色浓淡，不改变模糊效果。系统开启“减少透明度”时使用实色底。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Toggle("保持窗口置顶", isOn: $draft.pinned)
                }
                Section("本地记录") {
                    Text("字幕与收藏保存在本机，最多保留最近 2,000 句。不会保存录音或视频。可从字幕窗菜单导出 SRT 与学习笔记。导入字幕按文件时间展示，不会控制或同步浏览器播放器。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            HStack {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                Spacer()
                Button("取消", action: close)
                Button("保存设置") {
                    do { try state.applyConfig(draft, newKey: nil, newKeys: pendingKeys); close() }
                    catch { message = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(minWidth: 580, minHeight: 660)
            .onChange(of: draft.aiProfile) { _, _ in cancelTest() }
            .onDisappear { cancelTest() }
    }
    func cancelTest() {
        testTask?.cancel(); testID = UUID(); testing = false
        message = ""
    }
    func testConnection() {
        testing = true; message = "正在向配置的服务发送一条测试请求…"
        let id = UUID(); testID = id
        let key = (pendingKeys[draft.keyAccount] ?? KeyStore.read(account: draft.keyAccount)).trimmingCharacters(in: .whitespacesAndNewlines)
        let client = AIService(config: draft, key: key)
        testTask = Task {
            do {
                _ = try await client.complete([["role": "user", "content": "请只回复 OK。"]])
                guard !Task.isCancelled, id == testID else { return }
                message = "\(client.config.provider.label) 连接成功，可以开始分析字幕了。"
            } catch {
                guard !Task.isCancelled, id == testID else { return }
                message = error.localizedDescription
            }
            testing = false
        }
    }
    func openPrivacy(_ pane: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) } }
}

struct PasteView: View {
    @ObservedObject var state: AppState
    @State private var text = ""
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("粘贴日语文本").font(.system(size: 20, weight: .semibold))
            Text("每行一句，也可直接粘贴 SRT / VTT 字幕。导入后点击句子即可分析。").font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(size: 16)).padding(8).background(.background, in: RoundedRectangle(cornerRadius: 12))
            HStack { Button("从剪贴板粘贴") { text = NSPasteboard.general.string(forType: .string) ?? "" }; Spacer(); Button("取消", action: close); Button("添加到字幕") { state.importText(text); close() }.buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(minWidth: 510, minHeight: 360)
    }
}
