import AppKit
import SwiftUI
import Speech

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        if CommandLine.arguments.contains("--trace-ui"), event.type == .leftMouseDown || event.type == .leftMouseUp {
            print("UI event \(event.type.rawValue) in \(title): \(event.locationInWindow); frame \(frame)")
            fflush(stdout)
        }
        super.sendEvent(event)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let state = AppState(restore: !CommandLine.arguments.contains("--preview"))
    private var transcript: FloatingPanel!
    private var analysisPanel: FloatingPanel?
    private var settingsWindow: NSWindow?
    private var pasteWindow: NSWindow?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        let frame = defaultFrame()
        transcript = makePanel(title: "Kotoba · 悬浮字幕", frame: frame, minSize: NSSize(width: 310, height: 360), autosave: "Kotoba.Transcript")
        let view = TranscriptView(state: state, close: { [weak self] in self?.hide() }, settings: { [weak self] in self?.showSettings() }, paste: { [weak self] in self?.showPaste() }, resetPosition: { [weak self] in self?.resetPosition() })
        install(view, into: transcript)
        state.showAnalysis = { [weak self] in self?.openAnalysis() }
        state.showSettings = { [weak self] in self?.showSettings() }
        state.settingsChanged = { [weak self] in self?.updateAppearance() }
        updateAppearance()
        show()
        if CommandLine.arguments.contains("--preview") {
            state.loadDemo()
            if CommandLine.arguments.contains("--analysis") { state.select(state.subtitles[1], extending: false) }
        }
    }
    private func defaultFrame() -> NSRect {
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: area.maxX - 385, y: area.maxY - min(760, area.height - 65) - 32, width: 360, height: min(760, area.height - 65))
    }
    private func makePanel(title: String, frame: NSRect, minSize: NSSize, autosave: String) -> FloatingPanel {
        let panel = FloatingPanel(contentRect: frame, styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = minSize
        panel.maxSize = NSSize(width: 2200, height: 1600)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.setFrameAutosaveName(autosave)
        if !panel.setFrameUsingName(autosave) { panel.setFrame(frame, display: false) }
        keepVisible(panel)
        return panel
    }
    private func keepVisible(_ panel: NSWindow) {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let width = min(panel.frame.width, area.width), height = min(panel.frame.height, area.height)
        let x = max(area.minX, min(panel.frame.minX, area.maxX - width))
        let y = max(area.minY, min(panel.frame.minY, area.maxY - height))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
    }
    private func install<V: View>(_ view: V, into window: NSWindow) {
        let surface = FrostedPanelView(frame: NSRect(origin: .zero, size: window.frame.size))
        let hosting = NSHostingView(rootView: ReadingSurface(state: state) { view })
        hosting.frame = surface.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        // Keep text outside the effect's vibrant subview hierarchy.
        surface.addSubview(hosting)
        window.contentView = surface
    }
    @objc func show() { transcript.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func hide() { state.stopCapture(); transcript.orderOut(nil); closeAnalysis() }
    @objc func toggleListen() { show(); state.toggleCapture() }
    @objc func showSettings() {
        settingsWindow?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 790), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Kotoba 设置"; window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 580, height: 680)
        window.contentView = NSHostingView(rootView: SettingsView(state: state, draft: state.config, close: { [weak window] in window?.close() }))
        window.level = .floating; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
    private func showPaste() {
        pasteWindow?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 440), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "添加字幕"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PasteView(state: state, close: { [weak window] in window?.close() }))
        window.level = .floating; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        pasteWindow = window
    }
    private func openAnalysis() {
        if analysisPanel == nil {
            let screen = transcript.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
            let frame = NSRect(x: max(screen.minX, transcript.frame.minX - 810), y: max(screen.minY, transcript.frame.maxY - 650), width: min(800, screen.width - 40), height: min(650, screen.height - 45))
            let panel = makePanel(title: "Kotoba · 句子解析", frame: frame, minSize: NSSize(width: 630, height: 430), autosave: "Kotoba.Analysis")
            install(AnalysisView(state: state, close: { [weak self] in self?.closeAnalysis() }, settings: { [weak self] in self?.showSettings() }), into: panel)
            analysisPanel = panel
        }
        positionAnalysis()
        updateAppearance()
        analysisPanel?.makeKeyAndOrderFront(nil)
    }
    private func positionAnalysis() {
        guard let panel = analysisPanel, let screen = transcript.screen?.visibleFrame else { return }
        let x = transcript.frame.minX - panel.frame.width - 10
        panel.setFrameOrigin(NSPoint(x: max(screen.minX + 6, x), y: max(screen.minY + 6, min(transcript.frame.maxY - panel.frame.height, screen.maxY - panel.frame.height))))
    }
    private func closeAnalysis() { analysisPanel?.orderOut(nil); state.clearSelection() }
    private func resetPosition() { transcript.setFrame(defaultFrame(), display: true, animate: true); positionAnalysis() }
    private func updateAppearance() {
        transcript?.level = state.config.pinned ? .floating : .normal
        analysisPanel?.level = state.config.pinned ? .floating : .normal
    }
    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === transcript, analysisPanel?.isVisible == true { positionAnalysis() }
    }
    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === transcript, analysisPanel?.isVisible == true { positionAnalysis() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === transcript { hide(); return false }
        if sender === analysisPanel { closeAnalysis(); return false }
        return true
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationWillTerminate(_ notification: Notification) { state.stopCapture(); state.persist() }
    private func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "显示字幕窗口", action: #selector(show), keyEquivalent: "0").target = self
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Kotoba", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: "Kotoba 悬浮字幕")
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "显示字幕窗口", action: #selector(show), keyEquivalent: "").target = self
        menu.addItem(withTitle: state.isListening ? "暂停识别" : "开始聆听", action: #selector(toggleListen), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Kotoba", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
}

if CommandLine.arguments.contains("--core-test") {
    do { try SelfTests.run(); print("All headless core tests passed."); exit(0) }
    catch { fputs("Core test failed: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--self-test") {
    do { try SelfTests.run(); try MainActor.assumeIsolated { try SelfTests.state() }; print("All core tests passed."); exit(0) }
    catch { fputs("Test failed: \(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--network-test") {
    Task {
        do { try await SelfTests.network(); print("All API integration tests passed."); exit(0) }
        catch { fputs("API test failed: \(error)\n", stderr); exit(1) }
    }
    dispatchMain()
}
if CommandLine.arguments.contains("--capabilities") {
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    print("Japanese recognizer available: \(recognizer?.isAvailable ?? false)")
    print("Japanese on-device recognition supported: \(recognizer?.supportsOnDeviceRecognition ?? false)")
    print("Speech authorization status (0=not requested, 3=authorized): \(SFSpeechRecognizer.authorizationStatus().rawValue)")
    print("Screen/audio permission currently granted: \(CGPreflightScreenCaptureAccess())")
    exit(0)
}
if CommandLine.arguments.contains("--modern-capabilities") {
    Task {
        print("SpeechTranscriber available: \(SpeechTranscriber.isAvailable)")
        print("Supported locales: \(await SpeechTranscriber.supportedLocales.map(\.identifier).joined(separator: ", "))")
        print("Installed locales: \(await SpeechTranscriber.installedLocales.map(\.identifier).joined(separator: ", "))")
        exit(0)
    }
    dispatchMain()
}
if let index = CommandLine.arguments.firstIndex(of: "--speech-test"), CommandLine.arguments.count > index + 1 {
    setbuf(stdout, nil)
    let path = CommandLine.arguments[index + 1]
    Task {
        do { try await SelfTests.speechFile(URL(fileURLWithPath: path)); print("Local speech integration test passed."); exit(0) }
        catch { fputs("Local speech test failed: \(error)\n", stderr); exit(1) }
    }
    dispatchMain()
}
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
