import Foundation
import ScreenCaptureKit
import Speech
import CoreMedia
import AVFoundation

/// Audio stays in memory. No video output is registered and no recording is saved.
final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onText: (([String], String, Double) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onFailure: ((String) -> Void)?
    var onMode: ((String) -> Void)?
    private let queue = DispatchQueue(label: "kotoba.audio", qos: .userInitiated)
    private var stream: SCStream?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var assembler = TranscriptAssembler()
    private var latest = ""
    private var running = false
    private var started = Date()
    private var sessionStarted = Date()
    private var lastVoice = Date()
    private var lastMeter = Date.distantPast
    private var errorCount = 0
    private var localOnly = true
    private var localSpeech: LocalSpeech?

    func start(config: AppConfig) async throws {
        var engine: SFSpeechRecognizer?
        if config.localOnly {
            let local = LocalSpeech(); localSpeech = local
            local.onText = { [weak self] complete, live, elapsed in DispatchQueue.main.async { self?.onText?(complete, live, elapsed) } }
            local.onProgress = { [weak self] text in DispatchQueue.main.async { self?.onMode?(text) } }
            local.onFailure = { [weak self] text in DispatchQueue.main.async { self?.onFailure?(text) } }
            do { try await local.prepare(localeID: config.locale) }
            catch { await local.finish(); localSpeech = nil; throw error }
        } else {
            let authorization = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard authorization == .authorized else { throw AppError.message("需要语音识别权限。请到系统设置 → 隐私与安全性 → 语音识别，允许 Kotoba 后重试。") }
            engine = SFSpeechRecognizer(locale: Locale(identifier: config.locale))
            guard engine?.isAvailable == true else { throw AppError.message("系统语音识别当前不可用，请检查网络或稍后重试。") }
        }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) }
        catch { throw AppError.message("未能取得声音采集权限。请到系统设置 → 隐私与安全性 → 屏幕与系统音频录制，允许 Kotoba；若系统要求，请退出并重新打开应用。") }
        try Task.checkCancellation()
        guard let display = content.displays.first else { throw AppError.message("没有可用的显示器，无法建立系统音频流。") }
        let filter: SCContentFilter
        if config.audioSource == "system" {
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        } else {
            let apps = content.applications.filter { $0.bundleIdentifier == config.audioSource || $0.bundleIdentifier.hasPrefix(config.audioSource + ".") }
            guard !apps.isEmpty else { throw AppError.message("没有找到正在运行的 \(config.sourceName)。请先打开浏览器，或在设置中选择其他声音来源。") }
            filter = SCContentFilter(display: display, including: apps, exceptingWindows: [])
        }
        let sc = SCStreamConfiguration()
        sc.capturesAudio = true
        sc.excludesCurrentProcessAudio = true
        sc.sampleRate = Int(localSpeech?.format?.sampleRate ?? 16_000)
        sc.channelCount = 1
        sc.width = 2
        sc.height = 2
        sc.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        sc.queueDepth = 3
        sc.showsCursor = false
        let capture = SCStream(filter: filter, configuration: sc, delegate: self)
        try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        queue.sync {
            recognizer = engine
            localOnly = config.localOnly
            started = Date()
            lastVoice = Date()
            errorCount = 0
            running = true
            if localSpeech == nil { beginRequest() }
        }
        stream = capture
        do { try await capture.startCapture() }
        catch {
            await stop()
            throw AppError.message("无法开始采集：\(error.localizedDescription)")
        }
        onMode?(config.localOnly ? "设备端识别" : "Apple 识别")
    }

    func stop() async {
        queue.sync {
            running = false
            flush()
            generation = UUID()
            request?.endAudio()
            task?.cancel()
            request = nil
            task = nil
        }
        let previous = stream
        stream = nil
        try? await previous?.stopCapture()
        let local = localSpeech; localSpeech = nil
        await local?.finish()
    }

    private func beginRequest() {
        dispatchPrecondition(condition: .onQueue(queue))
        generation = UUID()
        let id = generation
        task?.cancel()
        request?.endAudio()
        assembler = TranscriptAssembler()
        latest = ""
        sessionStarted = Date()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = localOnly
        req.addsPunctuation = true
        req.taskHint = .dictation
        req.contextualStrings = ["日本語", "住所", "知っています", "知りません"]
        request = req
        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            self.queue.async {
                guard self.running, self.generation == id else { return }
                if let result {
                    self.latest = result.bestTranscription.formattedString
                    let sentences = self.assembler.update(self.latest, final: result.isFinal)
                    self.emit(sentences)
                    self.errorCount = 0
                    if result.isFinal { self.beginRequest(); return }
                }
                if let error {
                    let ns = error as NSError
                    self.flush()
                    if ns.code == 1110 || ns.code == 203 || ns.code == 216 { self.beginRequest(); return }
                    self.errorCount += 1
                    if self.errorCount < 3 { self.beginRequest() }
                    else {
                        self.running = false
                        DispatchQueue.main.async { self.onFailure?("语音识别中断（\(ns.code)）。请检查识别语言、网络和权限，然后重新开始。") }
                    }
                }
            }
        }
    }
    private func emit(_ complete: [String]) {
        let live = assembler.live
        let elapsed = Date().timeIntervalSince(started)
        DispatchQueue.main.async { self.onText?(complete, live, elapsed) }
    }
    private func flush() {
        if !latest.isEmpty { emit(assembler.update(latest, final: true)) }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, running, sampleBuffer.isValid else { return }
        let now = Date()
        let rms = Self.rms(sampleBuffer)
        if rms > 0.007 { lastVoice = now }
        if now.timeIntervalSince(lastMeter) > 0.12 {
            lastMeter = now
            DispatchQueue.main.async { self.onLevel?(min(1, rms * 9)) }
        }
        if let localSpeech { localSpeech.append(sampleBuffer); return }
        // Commit a phrase after a genuine pause, and rotate before Apple's
        // per-request time limits even if the speaker never pauses.
        if (!assembler.live.isEmpty && now.timeIntervalSince(lastVoice) > 1.25 && now.timeIntervalSince(sessionStarted) > 1.5)
            || now.timeIntervalSince(sessionStarted) > 45 {
            flush()
            beginRequest()
        }
        request?.appendAudioSampleBuffer(sampleBuffer)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard stream === self.stream else { return }
        DispatchQueue.main.async { self.onFailure?("声音采集已停止：\(error.localizedDescription)") }
    }
    static func rms(_ sample: CMSampleBuffer) -> Double {
        guard let description = sample.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              let block = sample.dataBuffer else { return 0 }
        var pointer: UnsafeMutablePointer<Int8>?
        var length = 0
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil, dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let pointer else { return 0 }
        var sum = 0.0
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 && asbd.mBitsPerChannel == 32 {
            let n = min(length / 4, 4096)
            guard n > 0 else { return 0 }
            let values = UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self)
            for i in 0..<n { let value = Double(values[i]); sum += value * value }
            return sqrt(sum / Double(n))
        } else if asbd.mBitsPerChannel == 16 {
            let n = min(length / 2, 4096)
            guard n > 0 else { return 0 }
            let values = UnsafeRawPointer(pointer).assumingMemoryBound(to: Int16.self)
            for i in 0..<n { let value = Double(values[i]) / 32768; sum += value * value }
            return sqrt(sum / Double(n))
        }
        return 0
    }
}
