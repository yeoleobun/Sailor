import AppKit
import QuartzCore

/// Renders the crisp monochrome Sailor Anchor template icon (matching assets/sailor-menubar.svg)
/// and provides a pendulum-swinging NSView pivoted at the top ring (eye) of the anchor.
enum AnchorIconRenderer {
    static let canvasSize = NSSize(width: 18, height: 18)
    /// Normalized anchor point (AppKit bottom-left origin) at the exact center of the top ring (9, 14.5).
    static let topRingAnchorPoint = CGPoint(x: 0.5, y: 14.5 / 18.0)

    /// Returns a crisp vector-drawn macOS template image (adapts automatically to Light & Dark Mode).
    static func makeTemplateImage() -> NSImage {
        let image = NSImage(size: canvasSize, flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Top Ring (Eye): cx=9, cy=3.5, r=1.55
            let ringRect = NSRect(x: 9.0 - 1.55, y: 3.5 - 1.55, width: 3.1, height: 3.1)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = 1.45
            ring.stroke()

            // Vertical Shank: (9, 5.1) -> (9, 14.7)
            let shank = NSBezierPath()
            shank.move(to: NSPoint(x: 9.0, y: 5.1))
            shank.line(to: NSPoint(x: 9.0, y: 14.7))
            shank.lineWidth = 1.55
            shank.lineCapStyle = .round
            shank.stroke()

            // Rounded Crossbar: (6.2, 7.8) -> (11.8, 7.8)
            let crossbar = NSBezierPath()
            crossbar.move(to: NSPoint(x: 6.2, y: 7.8))
            crossbar.line(to: NSPoint(x: 11.8, y: 7.8))
            crossbar.lineWidth = 1.5
            crossbar.lineCapStyle = .round
            crossbar.stroke()

            // Sweeping Bottom Arc: centered at (9, 9.5), radius 5.7, from ~170° down through 90° to ~10°
            // Matches M 3.3 10.4 A 5.7 5.7 0 0 0 14.7 10.4 (bottom at y ≈ 15.2)
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: 9.0, y: 9.45),
                radius: 5.75,
                startAngle: 171,
                endAngle: 9,
                clockwise: true
            )
            arc.lineWidth = 1.55
            arc.lineCapStyle = .round
            arc.stroke()

            // Left Pointed Fluke Tip (尖尖)
            let leftFluke = NSBezierPath()
            leftFluke.move(to: NSPoint(x: 3.1, y: 8.8))
            leftFluke.line(to: NSPoint(x: 4.7, y: 10.7))
            leftFluke.line(to: NSPoint(x: 2.0, y: 11.2))
            leftFluke.close()
            leftFluke.lineWidth = 0.45
            leftFluke.lineJoinStyle = .round
            leftFluke.fill()
            leftFluke.stroke()

            // Right Pointed Fluke Tip (尖尖)
            let rightFluke = NSBezierPath()
            rightFluke.move(to: NSPoint(x: 14.9, y: 8.8))
            rightFluke.line(to: NSPoint(x: 13.3, y: 10.7))
            rightFluke.line(to: NSPoint(x: 16.0, y: 11.2))
            rightFluke.close()
            rightFluke.lineWidth = 0.45
            rightFluke.lineJoinStyle = .round
            rightFluke.fill()
            rightFluke.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Custom view hosted inside `NSStatusBarButton` that pivots cleanly around the anchor's top ring
/// and plays a smooth damped pendulum swing whenever the network profile changes.
final class AnchorStatusIconView: NSView {
    private let imageView: NSImageView

    override init(frame frameRect: NSRect) {
        let iconImage = AnchorIconRenderer.makeTemplateImage()
        self.imageView = NSImageView(image: iconImage)
        super.init(frame: frameRect)

        wantsLayer = true
        imageView.wantsLayer = true
        imageView.imageScaling = .scaleProportionallyDown
        imageView.frame = NSRect(origin: .zero, size: AnchorIconRenderer.canvasSize)
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let clicks pass straight through to the parent NSStatusBarButton
        nil
    }

    override func layout() {
        super.layout()
        guard let iconLayer = imageView.layer else { return }

        let size = AnchorIconRenderer.canvasSize
        let originX = (bounds.width - size.width) / 2.0
        let originY = (bounds.height - size.height) / 2.0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.bounds = CGRect(origin: .zero, size: size)
        iconLayer.anchorPoint = AnchorIconRenderer.topRingAnchorPoint
        iconLayer.position = CGPoint(
            x: originX + size.width * AnchorIconRenderer.topRingAnchorPoint.x,
            y: originY + size.height * AnchorIconRenderer.topRingAnchorPoint.y
        )
        CATransaction.commit()
    }

    /// Plays a tactile damped pendulum swing pivoted from the top ring of the anchor.
    func triggerPendulumSwing() {
        layoutSubtreeIfNeeded()
        guard let iconLayer = imageView.layer else { return }

        iconLayer.removeAnimation(forKey: "pendulumSwing")

        let degrees: [CGFloat] = [0, -28, 22, -15, 9, -4.5, 2, 0]
        let radians = degrees.map { $0 * .pi / 180.0 }

        let anim = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        anim.values = radians
        anim.keyTimes = [0.0, 0.14, 0.32, 0.50, 0.66, 0.80, 0.91, 1.0]
        anim.duration = 1.35
        anim.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeInEaseOut),
            count: radians.count - 1
        )
        anim.isRemovedOnCompletion = true
        iconLayer.add(anim, forKey: "pendulumSwing")
    }
}
