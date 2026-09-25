import Foundation
import Speech
import AVFoundation
import CoreMedia

/// macOS 26's long-form, on-device recognizer. Models are managed by Apple;
/// unavailable assets are prepared once, with visible download progress.
final class LocalSpeech: @unchecked Sendable {
    var onText: (([String], String, Double) -> Void)?
    var onProgress: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    private(set) var format: AVAudioFormat?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var observation: NSKeyValueObservation?
    private var converter: AVAudioConverter?
    private var stopped = false
    private var conversionFailed = false

    func prepare(localeID: String) async throws {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw AppError.message("这台 Mac 的本地语音模型暂不支持所选语言。可换一种语言，或在设置中允许 Apple 在线识别。")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        let status = await AssetInventory.status(forModules: [transcriber])
        onProgress?(status == .installed ? "准备设备端识别…" : "正在准备语言模型，首次需要下载…")
        // Keep this app's selected languages reserved across sessions so the
        // system doesn't discard a just-downloaded model after every pause.
        try await AssetInventory.reserve(locale: locale)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            observation = installation.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
                let percent = Int(progress.fractionCompleted * 100)
                self?.onProgress?(percent > 0 ? "下载语言模型 \(percent)%" : "正在下载语言模型…")
            }
            try await withTaskCancellationHandler {
                try await installation.downloadAndInstall()
            } onCancel: { installation.progress.cancel() }
            observation = nil
        }
        try Task.checkCancellation()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw AppError.message("无法建立本地识别的音频格式。") }
        self.format = format
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        let (inputs, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(400))
        self.continuation = continuation
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, !Task.isCancelled else { return }
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let time = CMTimeGetSeconds(CMTimeRangeGetEnd(result.range))
                    if result.isFinal {
                        var splitter = TranscriptAssembler()
                        self.onText?(splitter.update(text, final: true), "", time.isFinite ? time : 0)
                    } else { self.onText?([], text, time.isFinite ? time : 0) }
                }
            } catch {
                guard let self, !Task.isCancelled, !self.stopped else { return }
                self.onFailure?("设备端语音识别中断：\(error.localizedDescription)")
            }
        }
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: inputs)
        onProgress?("设备端识别")
    }

    // Called serially by ScreenCaptureKit's audio queue.
    func append(_ sample: CMSampleBuffer) {
        guard !conversionFailed, let target = format, let description = sample.formatDescription else { return }
        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: description)
        let count = AVAudioFrameCount(sample.numSamples)
        guard count > 0, let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: count) else { return }
        input.frameLength = count
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(count), into: input.mutableAudioBufferList) == noErr else { failConversion(); return }
        let output: AVAudioPCMBuffer
        if sourceFormat == target { output = input }
        else {
            if converter?.inputFormat != sourceFormat { converter = AVAudioConverter(from: sourceFormat, to: target) }
            guard let converter, let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(ceil(Double(count) * target.sampleRate / sourceFormat.sampleRate)) + 32) else { failConversion(); return }
            var fed = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, flag in
                if fed { flag.pointee = .noDataNow; return nil }
                fed = true; flag.pointee = .haveData; return input
            }
            guard status != .error, error == nil else { failConversion(); return }
            guard converted.frameLength > 0 else { return }
            output = converted
        }
        if case .dropped = continuation?.yield(AnalyzerInput(buffer: output)) {
            conversionFailed = true
            onFailure?("本机识别处理速度不足，音频队列已满。请关闭占用较高的应用后重新开始。")
        }
    }
    private func failConversion() { conversionFailed = true; onFailure?("无法转换浏览器音频格式，请暂停后重试。") }

    func finish() async {
        guard !stopped else { return }
        stopped = true
        continuation?.finish(); continuation = nil
        if let analyzer {
            do { try await analyzer.finalizeAndFinishThroughEndOfInput(); await resultsTask?.value }
            catch { resultsTask?.cancel() }
            await analyzer.cancelAndFinishNow()
        }
        resultsTask?.cancel(); resultsTask = nil; analyzer = nil
    }
}
