import Foundation
import UIKit
import SwiftUI
import AVKit
import AVFoundation
import CoreMedia

final class SampleBufferDisplayView: UIView {
    override class var layerClass: AnyClass {
        AVSampleBufferDisplayLayer.self
    }

    var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }
}

struct PiPPreviewContainer: UIViewRepresentable {
    let manager: PiPManager

    func makeUIView(context: Context) -> SampleBufferDisplayView {
        manager.displayView
    }

    func updateUIView(_ uiView: SampleBufferDisplayView, context: Context) {
        manager.renderFrame()
    }
}

final class PiPManager: NSObject, ObservableObject {
    @Published var isPiPActive: Bool = false
    @Published var isPiPPossible: Bool = false
    @Published var statusMessage: String = "准备就绪"
    @Published var results: [ProbeResult] = []
    @Published var geoInfo: GeoInfo?

    let config: AppConfig
    let displayView: SampleBufferDisplayView = {
        let v = SampleBufferDisplayView()
        v.backgroundColor = UIColor(red: 20/255, green: 23/255, blue: 31/255, alpha: 1.0)
        v.displayLayer.videoGravity = .resizeAspect
        return v
    }()

    private var pipController: AVPictureInPictureController?
    private var pipPossibleObservation: NSKeyValueObservation?
    private var tickTimer: Timer?
    private var lastProbeTime: TimeInterval = 0
    private var lastGeoTime: TimeInterval = 0
    private var isProbing = false
    private var isFetchingGeo = false

    init(config: AppConfig) {
        self.config = config
        super.init()
        setupAudioSession()
        setupPiP()
        startLoops()
    }

    deinit {
        tickTimer?.invalidate()
        pipPossibleObservation?.invalidate()
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            statusMessage = "音频会话初始化失败: \(error.localizedDescription)"
        }
    }

    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            statusMessage = "当前设备不支持画中画"
            isPiPPossible = false
            return
        }

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayView.displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = true
        self.pipController = controller

        pipPossibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, change in
            DispatchQueue.main.async {
                self?.isPiPPossible = change.newValue ?? false
            }
        }

        renderFrame()
    }

    func togglePiP() {
        guard let controller = pipController else {
            statusMessage = "画中画控制器未就绪"
            return
        }
        setupAudioSession()
        renderFrame()

        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    func refreshNow() {
        triggerProbe()
        triggerGeoFetch()
    }

    func applyStyleChange() {
        displayView.displayLayer.flush()
        renderFrame()
        pipController?.invalidatePlaybackState()
    }

    private func startLoops() {
        triggerProbe()
        triggerGeoFetch()

        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.onTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func onTick() {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastProbeTime >= Double(max(2, config.intervalSeconds)) {
            triggerProbe()
        }
        if now - lastGeoTime >= 15.0 {
            triggerGeoFetch()
        }
        renderFrame()
    }

    private func triggerProbe() {
        guard !isProbing else { return }
        isProbing = true
        lastProbeTime = CFAbsoluteTimeGetCurrent()

        let targets = config.targets
        let mode = config.mode

        Task {
            let newResults = await LatencyProber.probeAll(targets: targets, mode: mode, timeoutSec: 3.0)
            await MainActor.run {
                self.results = newResults
                self.isProbing = false
                self.renderFrame()
            }
        }
    }

    private func triggerGeoFetch() {
        guard !isFetchingGeo else { return }
        isFetchingGeo = true
        lastGeoTime = CFAbsoluteTimeGetCurrent()

        Task {
            let info = await GeoLocationFetcher.fetch(timeoutSec: 3.5)
            await MainActor.run {
                self.geoInfo = info
                self.isFetchingGeo = false
                self.renderFrame()
            }
        }
    }

    func renderFrame() {
        let layer = displayView.displayLayer
        if layer.status == .failed {
            layer.flush()
        }
        guard let sampleBuffer = PiPRenderer.makeSampleBuffer(
            style: config.pipStyle,
            mode: config.mode,
            results: results,
            geo: geoInfo
        ) else {
            return
        }

        if #available(iOS 17.0, *) {
            if layer.sampleBufferRenderer.isReadyForMoreMediaData {
                layer.sampleBufferRenderer.enqueue(sampleBuffer)
            }
        } else {
            if layer.isReadyForMoreMediaData {
                layer.enqueue(sampleBuffer)
            }
        }
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = true
            self.statusMessage = "画中画悬浮窗运行中"
            self.renderFrame()
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = false
            self.statusMessage = "画中画已关闭"
        }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async {
            self.isPiPActive = false
            self.statusMessage = "启动失败: \(error.localizedDescription)"
        }
    }
}

extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        // Use the PiP center toggle button to switch between compact region-only pill and detailed latency card!
        DispatchQueue.main.async {
            self.config.pipStyle = (self.config.pipStyle == .detailCard) ? .regionOnly : .detailCard
            self.applyStyleChange()
            self.refreshNow()
        }
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        DispatchQueue.main.async {
            self.renderFrame()
        }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.refreshNow()
            completionHandler()
        }
    }
}
