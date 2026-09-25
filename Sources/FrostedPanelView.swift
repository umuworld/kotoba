import AppKit

/// Unlike dynamic Liquid Glass, this material has a public, fixed activity state.
/// The compositor blurs the windows behind us; we never capture their pixels.
final class FrostedPanelView: NSView {
    let backdrop = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 26
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        autoresizingMask = [.width, .height]
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.width, .height]
        backdrop.blendingMode = .behindWindow
        backdrop.material = .hudWindow
        backdrop.state = .active
        backdrop.isEmphasized = false
        addSubview(backdrop)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
