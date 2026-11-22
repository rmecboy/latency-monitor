import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import SwiftUI
import UIKit

final class SampleBufferHostView: UIView {
    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }

    var displayLayer: AVSampleBufferDisplayLayer {
        return layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 20.0 / 255.0, green: 23.0 / 255.0, blue: 31.0 / 255.0, alpha: 1.0)
        displayLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PiPPreviewRepresentable: UIViewRepresentable {
    let hostView: SampleBufferHostView

    func makeUIView(context: Context) -> SampleBufferHostView {
        return hostView
    }

    func updateUIView(_ uiView: SampleBufferHostView, context: Context) {}
}

final class PiPManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    @Published var isPiPActive: Bool = false
    @Published var statusMessage: String = ""

    let hostView = SampleBufferHostView(frame: CGRect(x: 0, y: 0, width: 240, height: 138))
    private var pipController: AVPictureInPictureController?
    private var isConfigured = false

    override init() {
        super.init()
    }

    func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        configureAudioSession()

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            DispatchQueue.main.async {
                self.statusMessage = "当前设备不支持画中画"
            }
            return
        }

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: hostView.displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = true
        self.pipController = controller
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Ignore audio session activation issues in simulator/background
        }
    }

    func togglePiP(
        targets: [TargetItem],
        results: [String: ProbeResult],
        details: [String: String],
        geoText: String,
        geoDetail: String,
        geoSuccess: Bool,
        showGeo: Bool,
        mode: String,
        compactHorizontal: Bool
    ) {
        configureIfNeeded()
        configureAudioSession()

        guard let controller = pipController else {
            DispatchQueue.main.async {
                self.statusMessage = "当前设备不支持画中画悬浮窗"
            }
            return
        }

        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            return
        }

        // Push a fresh frame before starting PiP so AVSampleBufferDisplayLayer is ready
        updateFrame(
            targets: targets,
            results: results,
            details: details,
            geoText: geoText,
            geoDetail: geoDetail,
            geoSuccess: geoSuccess,
            showGeo: showGeo,
            mode: mode,
            compactHorizontal: compactHorizontal
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if controller.isPictureInPicturePossible {
                controller.startPictureInPicture()
            } else {
                self.statusMessage = "请稍等 1 秒后再次点击开启画中画"
            }
        }
    }

    func updateFrame(
        targets: [TargetItem],
        results: [String: ProbeResult],
        details: [String: String],
        geoText: String,
        geoDetail: String,
        geoSuccess: Bool,
        showGeo: Bool,
        mode: String,
        compactHorizontal: Bool
    ) {
        let image = renderCardImage(
            targets: targets,
            results: results,
            details: details,
            geoText: geoText,
            geoDetail: geoDetail,
            geoSuccess: geoSuccess,
            showGeo: showGeo,
            mode: mode,
            compactHorizontal: compactHorizontal
        )

        guard let sampleBuffer = makeSampleBuffer(from: image) else { return }

        DispatchQueue.main.async {
            let layer = self.hostView.displayLayer
            if #available(iOS 17.0, *) {
                let renderer = layer.sampleBufferRenderer
                if renderer.status == .failed {
                    renderer.flush()
                }
                renderer.enqueue(sampleBuffer)
            } else {
                if layer.status == .failed {
                    layer.flush()
                }
                layer.enqueue(sampleBuffer)
            }
        }
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = true
            self.statusMessage = "画中画悬浮窗已开启（切回桌面或其他 App 仍悬浮显示）"
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = false
            self.statusMessage = ""
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        DispatchQueue.main.async {
            self.isPiPActive = false
            self.statusMessage = "启动画中画失败：\(error.localizedDescription)"
        }
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {}

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        return false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    // MARK: - Frame Rendering

    private func latencyUIColor(result: ProbeResult?) -> UIColor {
        guard let res = result else {
            return UIColor(red: 148.0 / 255.0, green: 163.0 / 255.0, blue: 184.0 / 255.0, alpha: 1.0)
        }
        if !res.success {
            return UIColor(red: 248.0 / 255.0, green: 113.0 / 255.0, blue: 113.0 / 255.0, alpha: 1.0)
        }
        if res.latencyMs < 800 {
            return UIColor(red: 52.0 / 255.0, green: 211.0 / 255.0, blue: 153.0 / 255.0, alpha: 1.0)
        }
        if res.latencyMs <= 1500 {
            return UIColor(red: 251.0 / 255.0, green: 191.0 / 255.0, blue: 36.0 / 255.0, alpha: 1.0)
        }
        return UIColor(red: 248.0 / 255.0, green: 113.0 / 255.0, blue: 113.0 / 255.0, alpha: 1.0)
    }

    private func renderCardImage(
        targets: [TargetItem],
        results: [String: ProbeResult],
        details: [String: String],
        geoText: String,
        geoDetail: String,
        geoSuccess: Bool,
        showGeo: Bool,
        mode: String,
        compactHorizontal: Bool
    ) -> UIImage {
        if compactHorizontal {
            return renderHorizontalBar(targets: targets, results: results, geoText: geoText, geoSuccess: geoSuccess, showGeo: showGeo)
        }
        return renderVerticalCard(targets: targets, results: results, details: details,
                                  geoText: geoText, geoDetail: geoDetail,
                                  geoSuccess: geoSuccess, showGeo: showGeo, mode: mode)
    }

    private func renderVerticalCard(
        targets: [TargetItem],
        results: [String: ProbeResult],
        details: [String: String],
        geoText: String,
        geoDetail: String,
        geoSuccess: Bool,
        showGeo: Bool,
        mode: String
    ) -> UIImage {
        let padX: CGFloat = 26
        let rowH: CGFloat = 74
        let headerH: CGFloat = 74
        let geoBlockH: CGFloat = showGeo ? 92 : 0
        let size = CGSize(width: 480, height: headerH + rowH * CGFloat(max(1, targets.count)) + geoBlockH)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let bgColor = UIColor(red: 20.0 / 255.0, green: 23.0 / 255.0, blue: 31.0 / 255.0, alpha: 1.0)
            let mutedColor = UIColor(red: 148.0 / 255.0, green: 163.0 / 255.0, blue: 184.0 / 255.0, alpha: 1.0)
            let detailColor = UIColor(red: 148.0 / 255.0, green: 163.0 / 255.0, blue: 184.0 / 255.0, alpha: 1.0)
            let nameColor = UIColor(red: 241.0 / 255.0, green: 245.0 / 255.0, blue: 249.0 / 255.0, alpha: 1.0)
            let dividerColor = UIColor(white: 1.0, alpha: 0.14)
            let badgeBg = UIColor(red: 30.0 / 255.0, green: 41.0 / 255.0, blue: 59.0 / 255.0, alpha: 1.0)
            let badgeFg = UIColor(red: 96.0 / 255.0, green: 165.0 / 255.0, blue: 250.0 / 255.0, alpha: 1.0)
            let geoPinColor = UIColor(red: 56.0 / 255.0, green: 189.0 / 255.0, blue: 248.0 / 255.0, alpha: 1.0)
            let geoTextColor = UIColor(red: 203.0 / 255.0, green: 213.0 / 255.0, blue: 225.0 / 255.0, alpha: 1.0)
            let greenColor = UIColor(red: 52.0 / 255.0, green: 211.0 / 255.0, blue: 153.0 / 255.0, alpha: 1.0)

            bgColor.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            var y: CGFloat = 22

            // Header
            greenColor.setFill()
            cg.fillEllipse(in: CGRect(x: padX, y: y + 7, width: 12, height: 12))

            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: mutedColor
            ]
            NSString(string: "LATENCY").draw(at: CGPoint(x: padX + 22, y: y), withAttributes: headerAttrs)

            let badgeRect = CGRect(x: size.width - padX - 88, y: y - 1, width: 88, height: 28)
            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 8)
            badgeBg.setFill()
            badgePath.fill()

            let badgeParagraph = NSMutableParagraphStyle()
            badgeParagraph.alignment = .center
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 17, weight: .bold),
                .foregroundColor: badgeFg,
                .paragraphStyle: badgeParagraph
            ]
            NSString(string: mode.uppercased()).draw(in: CGRect(x: badgeRect.minX, y: badgeRect.minY + 4, width: badgeRect.width, height: 22), withAttributes: badgeAttrs)

            y += 38
            dividerColor.setFill()
            cg.fill(CGRect(x: padX, y: y, width: size.width - padX * 2, height: 2))
            y += 14

            // Rows + per-target detail line
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 27, weight: .medium),
                .foregroundColor: nameColor
            ]
            let detailAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: detailColor
            ]
            let rightParagraph = NSMutableParagraphStyle()
            rightParagraph.alignment = .right

            for target in targets {
                let res = results[target.id]
                let color = latencyUIColor(result: res)

                color.setFill()
                cg.fillEllipse(in: CGRect(x: padX, y: y + 11, width: 14, height: 14))

                NSString(string: target.name).draw(at: CGPoint(x: padX + 26, y: y), withAttributes: nameAttrs)

                let valStr: String
                if let r = res {
                    valStr = r.success ? "\(r.latencyMs) ms" : "超时"
                } else {
                    valStr = "-- ms"
                }

                let valAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold),
                    .foregroundColor: color,
                    .paragraphStyle: rightParagraph
                ]
                NSString(string: valStr).draw(
                    in: CGRect(x: size.width - padX - 180, y: y, width: 180, height: 36),
                    withAttributes: valAttrs
                )

                if let detail = details[target.id], !detail.isEmpty {
                    NSString(string: detail).draw(
                        in: CGRect(x: padX + 26, y: y + 38, width: size.width - padX * 2 - 26, height: 18),
                        withAttributes: detailAttrs
                    )
                }

                y += rowH
            }

            if showGeo {
                y += 2
                dividerColor.setFill()
                cg.fill(CGRect(x: padX, y: y, width: size.width - padX * 2, height: 2))
                y += 12

                let pinColor = geoSuccess ? geoPinColor : mutedColor
                pinColor.setFill()
                cg.fillEllipse(in: CGRect(x: padX, y: y + 8, width: 14, height: 14))

                let geoAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                    .foregroundColor: geoSuccess ? geoTextColor : mutedColor
                ]
                NSString(string: geoText).draw(
                    in: CGRect(x: padX + 24, y: y, width: size.width - padX * 2 - 24, height: 30),
                    withAttributes: geoAttrs
                )

                if !geoDetail.isEmpty {
                    NSString(string: geoDetail).draw(
                        in: CGRect(x: padX + 24, y: y + 32, width: size.width - padX * 2 - 24, height: 18),
                        withAttributes: detailAttrs
                    )
                }
            }
        }
    }

    private func renderHorizontalBar(
        targets: [TargetItem],
        results: [String: ProbeResult],
        geoText: String,
        geoSuccess: Bool,
        showGeo: Bool
    ) -> UIImage {
        let size = CGSize(width: 640, height: 120)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let bgColor = UIColor(red: 20.0 / 255.0, green: 23.0 / 255.0, blue: 31.0 / 255.0, alpha: 1.0)
            let nameColor = UIColor(red: 241.0 / 255.0, green: 245.0 / 255.0, blue: 249.0 / 255.0, alpha: 1.0)
            let geoPinColor = UIColor(red: 56.0 / 255.0, green: 189.0 / 255.0, blue: 248.0 / 255.0, alpha: 1.0)
            let geoTextColor = UIColor(red: 203.0 / 255.0, green: 213.0 / 255.0, blue: 225.0 / 255.0, alpha: 1.0)
            let dividerColor = UIColor(white: 1.0, alpha: 0.16)

            bgColor.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let topY: CGFloat = showGeo ? 18 : 42

            if showGeo {
                geoPinColor.setFill()
                cg.fillEllipse(in: CGRect(x: 24, y: topY + 6, width: 12, height: 12))
                let geoAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                    .foregroundColor: geoTextColor
                ]
                NSString(string: geoText).draw(
                    in: CGRect(x: 46, y: topY - 2, width: size.width - 70, height: 30),
                    withAttributes: geoAttrs
                )

                dividerColor.setFill()
                cg.fill(CGRect(x: 24, y: 56, width: size.width - 48, height: 2))
            }

            let rowY: CGFloat = showGeo ? 70 : 42
            let colWidth = (size.width - 48) / CGFloat(max(1, targets.count))

            for (index, target) in targets.enumerated() {
                let x = 24 + CGFloat(index) * colWidth
                let res = results[target.id]
                let color = latencyUIColor(result: res)

                color.setFill()
                cg.fillEllipse(in: CGRect(x: x, y: rowY + 9, width: 12, height: 12))

                let short = target.name == "Google" ? "G" : (target.name == "Cloudflare" ? "CF" : (target.name == "Oracle" ? "OCI" : target.name))
                let valStr: String
                if let r = res {
                    valStr = r.success ? "\(r.latencyMs)ms" : "超时"
                } else {
                    valStr = "--"
                }

                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 23, weight: .medium),
                    .foregroundColor: nameColor
                ]
                let valAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 23, weight: .bold),
                    .foregroundColor: color
                ]

                let labelSize = NSString(string: short).size(withAttributes: nameAttrs)
                NSString(string: short).draw(at: CGPoint(x: x + 20, y: rowY), withAttributes: nameAttrs)
                NSString(string: valStr).draw(at: CGPoint(x: x + 28 + labelSize.width, y: rowY), withAttributes: valAttrs)
            }
        }
    }

    private func makeSampleBuffer(from image: UIImage) -> CMSampleBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var pixelBufferOpt: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBufferOpt
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOpt else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var formatDescOpt: CMVideoFormatDescription?
        let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescOpt
        )
        guard fmtStatus == noErr, let formatDesc = formatDescOpt else { return nil }

        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 1),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid
        )

        var sampleBufferOpt: CMSampleBuffer?
        let sbStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBufferOpt
        )
        guard sbStatus == noErr, let sampleBuffer = sampleBufferOpt else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        return sampleBuffer
    }
}
