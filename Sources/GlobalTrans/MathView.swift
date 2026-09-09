import AppKit
import MarkdownUI
import SwiftMath
import SwiftUI

struct MathView: NSViewRepresentable {
    var equation: String
    var fontSize: CGFloat = 15
    var labelMode: MTMathUILabelMode = .text
    var textAlignment: MTTextAlignment = .left

    private var verticalInset: CGFloat {
        labelMode == .display ? 8 : 5
    }

    func makeNSView(context: Context) -> MTMathUILabel {
        let view = MTMathUILabel()
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: MTMathUILabel, context: Context) {
        apply(to: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTMathUILabel, context: Context) -> CGSize? {
        apply(to: nsView)
        nsView.layoutSubtreeIfNeeded()
        var size = nsView.fittingSize
        if size.width <= 0 || size.height <= 0 {
            size = CGSize(width: max(fontSize * 2, 24), height: fontSize + verticalInset * 2)
        }
        size.height = max(size.height, fontSize + verticalInset * 2)
        if let maxWidth = proposal.width, maxWidth.isFinite, maxWidth > 0 {
            size.width = min(max(size.width, 1), maxWidth)
        }
        return size
    }

    private func apply(to view: MTMathUILabel) {
        view.latex = equation
        view.font = MTFontManager().latinModernFont(withSize: fontSize)
        view.textAlignment = textAlignment
        view.labelMode = labelMode
        view.textColor = .labelColor
        view.displayErrorInline = true
        view.contentInsets = NSEdgeInsets(
            top: verticalInset,
            left: 2,
            bottom: verticalInset,
            right: 2
        )
        view.invalidateIntrinsicContentSize()
        view.needsLayout = true
    }
}

enum MathImageRenderer {
    @MainActor
    static func image(latex: String, fontSize: CGFloat, dark: Bool) -> NSImage {
        let label = MTMathUILabel()
        label.wantsLayer = true
        label.layer?.isGeometryFlipped = true
        label.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        label.latex = latex
        label.font = MTFontManager().latinModernFont(withSize: fontSize)
        label.labelMode = .text
        label.textAlignment = .left
        label.textColor = .labelColor
        label.displayErrorInline = true
        label.contentInsets = NSEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)

        var fit = label.fittingSize
        if fit.width <= 0 || fit.height <= 0 {
            fit = CGSize(width: max(fontSize, 8), height: max(fontSize, 8))
        }
        let size = CGSize(width: ceil(fit.width), height: ceil(fit.height))
        label.frame = CGRect(origin: .zero, size: size)
        label.needsLayout = true
        label.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(Int((size.width * scale).rounded()), 1),
            pixelsHigh: max(Int((size.height * scale).rounded()), 1),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }
        rep.size = size
        label.cacheDisplay(in: label.bounds, to: rep)

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        let descent = (label.displayList?.descent ?? 0) + label.contentInsets.bottom
        let ascent = (label.displayList?.ascent ?? size.height) + label.contentInsets.top
        image.alignmentRect = NSRect(
            x: 0,
            y: max(descent, 0),
            width: size.width,
            height: max(ascent, 1)
        )
        return image
    }
}

struct MathInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        if let payload = MathEmbed.decode(url) {
            let nsImage = await MainActor.run {
                MathImageRenderer.image(
                    latex: payload.latex,
                    fontSize: payload.fontSize,
                    dark: payload.dark
                )
            }
            return Image(nsImage: nsImage)
        }
        return try await DefaultInlineImageProvider.default.image(with: url, label: label)
    }
}

private struct MathBlockImage: View {
    let url: URL?

    var body: some View {
        if let url, let payload = MathEmbed.decode(url) {
            Image(
                nsImage: MathImageRenderer.image(
                    latex: payload.latex,
                    fontSize: payload.fontSize,
                    dark: payload.dark
                )
            )
        } else {
            DefaultImageProvider.default.makeImage(url: url)
        }
    }
}

struct MathBlockImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        MathBlockImage(url: url)
    }
}
