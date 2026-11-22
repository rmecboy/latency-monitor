import UIKit
import CoreMedia
import CoreVideo

enum PiPRenderer {
    private static let bgColor = UIColor(red: 20/255, green: 23/255, blue: 31/255, alpha: 1.0)
    private static let dividerColor = UIColor(white: 1.0, alpha: 0.14)
    private static let nameColor = UIColor(red: 241/255, green: 245/255, blue: 249/255, alpha: 1.0)
    private static let geoColor = UIColor(red: 203/255, green: 213/255, blue: 225/255, alpha: 1.0)
    private static let mutedColor = UIColor(red: 148/255, green: 163/255, blue: 184/255, alpha: 1.0)
    private static let badgeBg = UIColor(red: 30/255, green: 41/255, blue: 59/255, alpha: 1.0)
    private static let badgeFg = UIColor(red: 96/255, green: 165/255, blue: 250/255, alpha: 1.0)
    private static let greenColor = UIColor(red: 52/255, green: 211/255, blue: 153/255, alpha: 1.0)
    private static let amberColor = UIColor(red: 251/255, green: 191/255, blue: 36/255, alpha: 1.0)
    private static let redColor = UIColor(red: 248/255, green: 113/255, blue: 113/255, alpha: 1.0)

    static func latencyColor(for ms: Int) -> UIColor {
        if ms < 800 { return greenColor }
        if ms <= 1500 { return amberColor }
        return redColor
    }

    static func overallColor(results: [ProbeResult]) -> UIColor {
        guard !results.isEmpty else { return mutedColor }
        let ok = results.filter { $0.success }
        guard let best = ok.map({ $0.latencyMs }).min() else { return redColor }
        return latencyColor(for: best)
    }

    static func pixelSize(for style: PiPStyle) -> (width: Int, height: Int) {
        switch style {
        case .regionOnly: return (320, 96)
        case .miniBar: return (580, 96)
        case .detailCard: return (420, 248)
        }
    }

    static func makeSampleBuffer(
        style: PiPStyle,
        mode: ProbeMode,
        results: [ProbeResult],
        geo: GeoInfo?
    ) -> CMSampleBuffer? {
        let size = pixelSize(for: style)
        guard let pixelBuffer = renderPixelBuffer(
            width: size.width,
            height: size.height,
            style: style,
            mode: mode,
            results: results,
            geo: geo
        ) else {
            return nil
        }

        var formatDesc: CMVideoFormatDescription?
        let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard fmtStatus == noErr, let desc = formatDesc else { return nil }

        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 1),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: desc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let buffer = sampleBuffer else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return buffer
    }

    private static func renderPixelBuffer(
        width: Int,
        height: Int,
        style: PiPStyle,
        mode: ProbeMode,
        results: [ProbeResult],
        geo: GeoInfo?
    ) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]

        var pxBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pxBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pxBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let ctx = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        // Flip to standard UIKit top-left origin
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        bgColor.setFill()
        ctx.fill(rect)

        switch style {
        case .regionOnly:
            drawRegionOnly(in: rect, results: results, geo: geo)
        case .miniBar:
            drawMiniBar(in: rect, results: results, geo: geo)
        case .detailCard:
            drawDetailCard(in: rect, mode: mode, results: results, geo: geo)
        }

        return buffer
    }

    private static func drawDot(center: CGPoint, radius: CGFloat, color: UIColor) {
        let path = UIBezierPath(
            ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        )
        color.setFill()
        path.fill()
    }

    private static func drawRegionOnly(in rect: CGRect, results: [ProbeResult], geo: GeoInfo?) {
        let dotColor = overallColor(results: results)
        let text = geo?.displayText ?? "定位中..."
        let textColor = (geo?.success == false) ? redColor : nameColor

        let font = UIFont.systemFont(ofSize: 32, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let nsText = text as NSString
        let textSize = nsText.size(withAttributes: attrs)
        let dotRadius: CGFloat = 9
        let gap: CGFloat = 14
        let totalW = min(rect.width - 28, dotRadius * 2 + gap + textSize.width)
        let startX = max(14, (rect.width - totalW) / 2)

        drawDot(center: CGPoint(x: startX + dotRadius, y: rect.midY), radius: dotRadius, color: dotColor)

        let drawRect = CGRect(
            x: startX + dotRadius * 2 + gap,
            y: (rect.height - textSize.height) / 2,
            width: rect.width - (startX + dotRadius * 2 + gap) - 12,
            height: textSize.height
        )
        nsText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
    }

    private static func drawMiniBar(in rect: CGRect, results: [ProbeResult], geo: GeoInfo?) {
        let dotColor = overallColor(results: results)
        let geoText = geo?.displayText ?? "定位中..."
        let geoTextColor = (geo?.success == false) ? redColor : geoColor

        var x: CGFloat = 20
        drawDot(center: CGPoint(x: x + 7, y: rect.midY), radius: 7, color: dotColor)
        x += 22

        let geoFont = UIFont.systemFont(ofSize: 22, weight: .semibold)
        let geoAttrs: [NSAttributedString.Key: Any] = [.font: geoFont, .foregroundColor: geoTextColor]
        let geoSize = (geoText as NSString).size(withAttributes: geoAttrs)
        let maxGeoW: CGFloat = 165
        let geoW = min(maxGeoW, geoSize.width)
        (geoText as NSString).draw(
            with: CGRect(x: x, y: (rect.height - geoSize.height) / 2, width: geoW, height: geoSize.height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: geoAttrs,
            context: nil
        )
        x += geoW + 14

        // Divider
        dividerColor.setFill()
        UIRectFill(CGRect(x: x, y: 24, width: 2, height: rect.height - 48))
        x += 16

        let nameFont = UIFont.systemFont(ofSize: 20, weight: .medium)
        let valFont = UIFont.monospacedDigitSystemFont(ofSize: 21, weight: .bold)

        let items = results.isEmpty
            ? [
                ProbeResult(targetId: "g", name: "Google", shortName: "G", success: false, latencyMs: -1, detail: ""),
                ProbeResult(targetId: "cf", name: "Cloudflare", shortName: "CF", success: false, latencyMs: -1, detail: ""),
                ProbeResult(targetId: "oci", name: "Oracle", shortName: "OCI", success: false, latencyMs: -1, detail: "")
              ]
            : results

        for (idx, item) in items.enumerated() {
            if idx > 0 { x += 14 }
            let valText: String
            let valColor: UIColor
            if results.isEmpty {
                valText = "--"
                valColor = mutedColor
            } else if !item.success {
                valText = "超时"
                valColor = redColor
            } else {
                valText = "\(item.latencyMs)"
                valColor = latencyColor(for: item.latencyMs)
            }

            let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: mutedColor]
            let nSize = (item.shortName as NSString).size(withAttributes: nameAttrs)
            (item.shortName as NSString).draw(at: CGPoint(x: x, y: (rect.height - nSize.height) / 2), withAttributes: nameAttrs)
            x += nSize.width + 6

            let valAttrs: [NSAttributedString.Key: Any] = [.font: valFont, .foregroundColor: valColor]
            let vSize = (valText as NSString).size(withAttributes: valAttrs)
            (valText as NSString).draw(at: CGPoint(x: x, y: (rect.height - vSize.height) / 2), withAttributes: valAttrs)
            x += vSize.width
        }
    }

    private static func drawDetailCard(in rect: CGRect, mode: ProbeMode, results: [ProbeResult], geo: GeoInfo?) {
        let padX: CGFloat = 22
        var y: CGFloat = 16

        // Header
        drawDot(center: CGPoint(x: padX + 6, y: y + 12), radius: 6, color: overallColor(results: results))

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: mutedColor
        ]
        ("LATENCY" as NSString).draw(at: CGPoint(x: padX + 20, y: y + 2), withAttributes: titleAttrs)

        let badgeText = mode.rawValue as NSString
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .bold),
            .foregroundColor: badgeFg
        ]
        let bSize = badgeText.size(withAttributes: badgeAttrs)
        let badgeRect = CGRect(x: rect.width - padX - bSize.width - 14, y: y, width: bSize.width + 14, height: bSize.height + 6)
        badgeBg.setFill()
        UIBezierPath(roundedRect: badgeRect, cornerRadius: 6).fill()
        badgeText.draw(at: CGPoint(x: badgeRect.minX + 7, y: badgeRect.minY + 3), withAttributes: badgeAttrs)

        y += 34
        dividerColor.setFill()
        UIRectFill(CGRect(x: padX, y: y, width: rect.width - padX * 2, height: 1.5))
        y += 12

        // Rows
        let items = results.isEmpty
            ? [
                ProbeResult(targetId: "g", name: "Google", shortName: "G", success: false, latencyMs: -1, detail: ""),
                ProbeResult(targetId: "cf", name: "Cloudflare", shortName: "CF", success: false, latencyMs: -1, detail: ""),
                ProbeResult(targetId: "oci", name: "Oracle", shortName: "OCI", success: false, latencyMs: -1, detail: "")
              ]
            : results

        let nameFont = UIFont.systemFont(ofSize: 22, weight: .medium)
        let valFont = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)

        for item in items {
            let valText: String
            let valColor: UIColor
            if results.isEmpty {
                valText = "-- ms"
                valColor = mutedColor
            } else if !item.success {
                valText = "超时"
                valColor = redColor
            } else {
                valText = "\(item.latencyMs) ms"
                valColor = latencyColor(for: item.latencyMs)
            }

            drawDot(center: CGPoint(x: padX + 6, y: y + 14), radius: 6, color: valColor)

            let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: nameColor]
            (item.name as NSString).draw(at: CGPoint(x: padX + 22, y: y), withAttributes: nameAttrs)

            let valAttrs: [NSAttributedString.Key: Any] = [.font: valFont, .foregroundColor: valColor]
            let vSize = (valText as NSString).size(withAttributes: valAttrs)
            (valText as NSString).draw(at: CGPoint(x: rect.width - padX - vSize.width, y: y), withAttributes: valAttrs)

            y += 40
        }

        y += 4
        dividerColor.setFill()
        UIRectFill(CGRect(x: padX, y: y, width: rect.width - padX * 2, height: 1.5))
        y += 12

        // Geo footer (NO IP)
        let geoText = "地域：" + (geo?.displayText ?? "定位中...")
        let geoTextColor = (geo?.success == false) ? redColor : geoColor
        let geoAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 19, weight: .medium),
            .foregroundColor: geoTextColor
        ]
        (geoText as NSString).draw(
            with: CGRect(x: padX, y: y, width: rect.width - padX * 2, height: 28),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: geoAttrs,
            context: nil
        )
    }
}
