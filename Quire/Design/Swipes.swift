import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import ObjectiveC

// MARK: - Settings drawer

/// Where the settings layer is while a finger moves it: pulled in over the chats from the leading
/// edge, or pushed back out. Kept out of `AppModel` because it changes on every frame of a swipe;
/// only `RootView` reads it.
@Observable
final class SettingsDrawer {
    var width: CGFloat = 390
    /// How far settings has been pulled in over the chats (0…width) before it's open.
    private(set) var opening: CGFloat? = nil
    /// How far open settings has been pushed back toward the leading edge (≤ 0).
    private(set) var closing: CGFloat = 0
    /// Counts swipes, so the settle animation of one can't tidy up after the next.
    private var swipe = 0
    private var pushing = false

    // Chats → settings, left to right.

    func pullChanged(_ x: CGFloat, app: AppModel) {
        if opening == nil {
            swipe += 1
            // Always arrive at the top of settings, as the gear does.
            if !app.settingsPath.isEmpty { app.settingsPath = [] }
        }
        opening = min(max(x, 0), width)
    }

    func pullEnded(_ x: CGFloat, velocity v: CGFloat, app: AppModel) {
        guard let from = opening else { return }
        let id = swipe
        let opens = v > 500 || (x > width * 0.33 && v > -200)
        let to: CGFloat = opens ? width : 0
        withAnimation(Self.settle(from: from, to: to, velocity: v)) {
            opening = to
        } completion: { [self] in
            guard swipe == id else { return }
            // Already where it belongs, so hand over without a second slide.
            Self.instantly {
                if opens { app.openSettings() }
                opening = nil
            }
        }
    }

    // Settings → chats, right to left.

    func pushChanged(_ x: CGFloat) {
        if !pushing {
            pushing = true
            swipe += 1
        }
        closing = min(0, x)
    }

    func pushEnded(_ x: CGFloat, velocity v: CGFloat, app: AppModel) {
        pushing = false
        let id = swipe
        let closes = v < -500 || (-x > width * 0.33 && v < 200)
        let to: CGFloat = closes ? -width : 0
        withAnimation(Self.settle(from: closing, to: to, velocity: v)) {
            closing = to
        } completion: { [self] in
            guard swipe == id, closes else { return }
            Self.instantly {
                app.closeSettings()
                closing = 0
            }
        }
    }

    /// Carries on at the finger's speed and settles without a bounce, so a flick lands as quickly
    /// as it was thrown.
    private static func settle(from: CGFloat, to: CGFloat, velocity: CGFloat) -> Animation {
        if UIAccessibility.isReduceMotionEnabled { return .easeOut(duration: 0.2) }
        let distance = to - from
        guard abs(distance) > 1 else { return Motion.quick }
        let relative = max(-12, min(12, Double(velocity / distance)))
        return .interpolatingSpring(duration: 0.4, bounce: 0, initialVelocity: relative)
    }

    private static func instantly(_ body: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, body)
    }
}

extension Route {
    /// Screens where a swipe from anywhere, not just the edge, goes back. Settings pages hold
    /// sliders and a scrubbable chart, so they keep the edge swipe alone.
    nonisolated var swipesBackAnywhere: Bool {
        switch self {
        case .chat, .project, .memory: true
        case .settings, .section, .spending: false
        }
    }
}

// MARK: - Stack swipes

/// Sideways swipes that start anywhere on a screen rather than at its edge: going back, and pulling
/// a layer across (settings over the chats, or back off them). They're UIKit gesture recognizers
/// on the navigation controller around the view this sits behind, so they can go first ahead of
/// a list's scrolling and its rows' swipe actions, while still giving way to things that move
/// sideways themselves: sliders, switches, code that scrolls, text being selected.
struct StackSwipes: UIViewRepresentable {
    struct Pull {
        /// 1 for a left-to-right swipe, -1 for right-to-left.
        var direction: CGFloat
        var allowed: () -> Bool
        var changed: (_ translation: CGFloat) -> Void
        var ended: (_ translation: CGFloat, _ velocity: CGFloat) -> Void
    }

    /// A pull that works on the stack's first screen.
    var pull: Pull? = nil
    /// Whether a swipe from anywhere goes back from the screen on top. Nil keeps the edge only.
    var backAllowed: (() -> Bool)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(goesBack: backAllowed != nil) }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        let coordinator = context.coordinator
        probe.onAttach = { [weak coordinator] nav in coordinator?.attach(to: nav) }
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        context.coordinator.pull = pull
        context.coordinator.backAllowed = backAllowed
    }

    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Finds the navigation controller once it's on screen.
    final class Probe: UIView {
        var onAttach: (UINavigationController) -> Void = { _ in }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var responder: UIResponder? = next
            while let r = responder {
                if let vc = r as? UIViewController, let nav = vc as? UINavigationController ?? vc.navigationController {
                    onAttach(nav)
                    return
                }
                responder = r.next
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var pull: Pull?
        var backAllowed: (() -> Bool)?
        private let goesBack: Bool
        private weak var nav: UINavigationController?
        private let pullPan = UIPanGestureRecognizer()
        private let backPan = UIPanGestureRecognizer()
        private weak var touched: UIView?

        init(goesBack: Bool) {
            self.goesBack = goesBack
            super.init()
            pullPan.addTarget(self, action: #selector(pulled(_:)))
            for pan in [pullPan, backPan] {
                pan.delegate = self
                pan.maximumNumberOfTouches = 1
            }
        }

        func attach(to nav: UINavigationController) {
            guard self.nav !== nav else { return }
            detach()
            self.nav = nav
            nav.view.addGestureRecognizer(pullPan)
            // Going back drives the navigation controller's own interactive pop, so it tracks the
            // finger, can be abandoned midway, and keeps the path in step, exactly like the edge
            // swipe. If that can't be found, nothing changes and the edge swipe still works.
            if goesBack, let handler = Self.popHandler(of: nav) {
                backPan.addTarget(handler.target, action: handler.action)
                nav.view.addGestureRecognizer(backPan)
                // The system's own content swipe would compete for the same pop.
                Self.contentPop(of: nav)?.isEnabled = false
            }
        }

        func detach() {
            pullPan.view?.removeGestureRecognizer(pullPan)
            backPan.view?.removeGestureRecognizer(backPan)
            backPan.removeTarget(nil, action: nil)
            if goesBack, let nav { Self.contentPop(of: nav)?.isEnabled = true }
            nav = nil
        }

        /// Measured in the window: the screen under the finger moves with it, so its own
        /// coordinates would understate how far the finger has gone.
        @objc private func pulled(_ pan: UIPanGestureRecognizer) {
            guard let pull else { return }
            switch pan.state {
            case .began, .changed:
                pull.changed(pan.translation(in: nil).x)
            case .ended:
                pull.ended(pan.translation(in: nil).x, pan.velocity(in: nil).x)
            case .cancelled, .failed:
                pull.ended(0, 0)
            default:
                break
            }
        }

        // MARK: Delegate

        /// Whether this swipe means anything right now: pulls on the stack's first screen, going
        /// back on a screen above it that wants it.
        private func allowed(_ g: UIGestureRecognizer) -> Bool {
            guard let nav, nav.transitionCoordinator == nil else { return false }
            if g === pullPan { return nav.viewControllers.count == 1 && (pull?.allowed() ?? false) }
            return nav.viewControllers.count > 1 && (backAllowed?() ?? false)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard allowed(g), let view = touch.view, !Self.claims(view) else { return false }
            touched = view
            return true
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer, let view = nav?.view else { return false }
            let direction: CGFloat = g === pullPan ? (pull?.direction ?? 1) : 1
            let v = pan.velocity(in: view)
            let d = hypot(v.x, v.y) > 80 ? v : pan.translation(in: view)
            // Clearly sideways and the right way; anything steeper is scrolling.
            guard d.x * direction > 0, abs(d.x) > abs(d.y) * 1.4 else { return false }
            if let touched, Self.scrollsSideways(from: touched, direction: direction) { return false }
            // A row showing its swipe actions closes on a swipe back, as it always has.
            if let screen = nav?.topViewController?.view, Self.rowActionsOpen(in: screen) { return false }
            return true
        }

        /// Scrolling and row swipes on the screen wait to see whether a touch is one of these.
        /// Each of these fails at once when it isn't, so nothing waits long.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard other !== pullPan, other !== backPan, other is UIPanGestureRecognizer, allowed(g),
                  let nav, let host = other.view, host is UIScrollView else { return false }
            return host.isDescendant(of: nav.view)
        }

        /// The edge swipe keeps the edge.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            g === backPan && other === nav?.interactivePopGestureRecognizer
        }

        // MARK: Hit rules

        /// Controls that move sideways under the finger, and text that's being edited or selected.
        private static func claims(_ view: UIView) -> Bool {
            var v: UIView? = view
            while let u = v {
                if u is UISlider || u is UISwitch || u is UISegmentedControl { return true }
                if let t = u as? UITextView, t.isFirstResponder || t.selectedRange.length > 0 { return true }
                if let t = u as? UITextField, t.isFirstResponder { return true }
                v = u.superview
            }
            return false
        }

        /// Something under the finger (a code block, a table, a strip of attachments) that can still
        /// scroll the way the swipe goes. At its end, the swipe is ours again.
        private static func scrollsSideways(from view: UIView, direction: CGFloat) -> Bool {
            var v: UIView? = view
            while let u = v {
                if let s = u as? UIScrollView, s.contentSize.width > s.bounds.width + 1 {
                    let inset = s.adjustedContentInset
                    let canScroll = direction > 0
                        ? s.contentOffset.x > -inset.left + 1
                        : s.contentOffset.x < s.contentSize.width - s.bounds.width + inset.right - 1
                    if canScroll { return true }
                }
                v = u.superview
            }
            return false
        }

        /// Whether a row in a list on screen has its swipe actions showing. A swipe right then
        /// belongs to the list, which closes them, as it always has. A row showing its actions has
        /// been slid sideways, which is what this looks for; the private names of the views behind
        /// the buttons are only a second opinion, since they change between releases.
        private static func rowActionsOpen(in screen: UIView) -> Bool {
            lists(in: screen).contains { list in
                let cells: [UIView] = (list as? UICollectionView)?.visibleCells ?? (list as? UITableView)?.visibleCells ?? []
                for cell in cells {
                    var parts: [UIView] = [cell] + cell.subviews
                    if let content = (cell as? UICollectionViewCell)?.contentView ?? (cell as? UITableViewCell)?.contentView {
                        parts += content.subviews
                    }
                    for part in parts where !part.isHidden && part.alpha > 0.01 && part.bounds.width > 40 {
                        let frame = part.convert(part.bounds, to: list)
                        if frame.minX < -8 || frame.maxX > list.bounds.width + 8 { return true }
                    }
                }
                return showsSwipeActions(list, depth: 0)
            }
        }

        /// The lists in a screen, found breadth first without looking inside them.
        private static func lists(in root: UIView) -> [UIScrollView] {
            var found: [UIScrollView] = []
            var queue: [UIView] = [root]
            var seen = 0
            while !queue.isEmpty, seen < 2000 {
                let v = queue.removeFirst()
                seen += 1
                if let list = v as? UIScrollView, list is UICollectionView || list is UITableView {
                    found.append(list)
                } else {
                    queue += v.subviews
                }
            }
            return found
        }

        private static func showsSwipeActions(_ view: UIView, depth: Int) -> Bool {
            if depth > 0, !view.isHidden, view.bounds.width > 1 {
                let name = String(describing: type(of: view))
                if name.contains("SwipeActionPullView") || name.contains("SwipeActionStandardButton") { return true }
            }
            guard depth < 6 else { return false }
            return view.subviews.contains { showsSwipeActions($0, depth: depth + 1) }
        }

        // MARK: Navigation internals

        /// iOS 26's swipe-from-anywhere recognizer, where there is one.
        private static func contentPop(of nav: UINavigationController) -> UIGestureRecognizer? {
            let key = "interactiveContentPopGestureRecognizer"
            guard nav.responds(to: NSSelectorFromString(key)) else { return nil }
            return nav.value(forKey: key) as? UIGestureRecognizer
        }

        /// The object behind the navigation controller's interactive pop, and the message it takes
        /// from a pan. Every step is checked first, so on a system that differs this returns nil
        /// rather than sending anything that isn't understood.
        private static func popHandler(of nav: UINavigationController) -> (target: NSObject, action: Selector)? {
            let action = NSSelectorFromString("handleNavigationTransition:")
            guard let ivar = class_getInstanceVariable(UIGestureRecognizer.self, "_targets") else { return nil }
            let sources = [contentPop(of: nav), nav.interactivePopGestureRecognizer].compactMap { $0 }
            for source in sources {
                guard let targets = object_getIvar(source, ivar) as? NSArray else { continue }
                for case let entry as NSObject in targets {
                    guard class_getInstanceVariable(type(of: entry), "_target") != nil,
                          let target = entry.value(forKey: "target") as? NSObject,
                          target.responds(to: action) else { continue }
                    return (target, action)
                }
            }
            return nil
        }
    }
}

// MARK: - Optical centring

/// An SF Symbol placed by its ink rather than its frame. Some symbols are framed around their main
/// shape and let a part reach outside it (square.and.pencil's pencil runs past the square), so a
/// round button centres the square and the drawing as a whole sits off to one side. This measures
/// where the ink's centre of mass falls, once per symbol, and moves the symbol back by that much.
struct OpticalSymbol: View {
    let name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        let shift = Self.shift(for: name)
        Image(systemName: name)
            .offset(x: shift.width, y: shift.height)
    }

    private static var cache: [String: CGSize] = [:]

    /// Measures ahead of time, at launch, so no screen has to stop and draw a symbol offscreen
    /// while it's being laid out.
    static func prepare(_ names: String...) {
        for name in names { _ = shift(for: name) }
    }

    private static func shift(for name: String) -> CGSize {
        if let s = cache[name] { return s }
        let s = measure(name) ?? .zero
        cache[name] = s
        return s
    }

    private static func measure(_ name: String) -> CGSize? {
        let scale: CGFloat = 3
        // Even padding all round, so the canvas centre is the frame centre, with room for any ink
        // that reaches outside the frame.
        let renderer = ImageRenderer(content: Image(systemName: name)
            .font(.system(size: 17))
            .imageScale(.large)
            .padding(8))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var total = 0.0, sx = 0.0, sy = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let a = Double(pixels[(y * w + x) * 4 + 3])
                guard a > 0 else { continue }
                total += a
                sx += a * (Double(x) + 0.5)
                sy += a * (Double(y) + 0.5)
            }
        }
        guard total > 0 else { return nil }
        let dx = (sx / total - Double(w) / 2) / Double(scale)
        let dy = (sy / total - Double(h) / 2) / Double(scale)
        // Leave a symbol that's already centred alone, and never move one by more than a hair.
        func correction(_ d: Double) -> CGFloat { abs(d) < 0.25 ? 0 : CGFloat(max(-2, min(2, -d))) }
        return CGSize(width: correction(dx), height: correction(dy))
    }
}

// MARK: - Keyboard

/// A swipe down anywhere on a chat puts the keyboard away. It only ever watches: the thread still
/// scrolls under the same finger, and buttons, menus and text selection work as before. A pull
/// that starts upward or sideways is ignored, and each swipe acts once.
struct KeyboardSwipe: UIGestureRecognizerRepresentable {
    func makeUIGestureRecognizer(context: Context) -> DownSwipeRecognizer {
        let pan = DownSwipeRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: DownSwipeRecognizer, context: Context) {
        guard pan.state == .changed || pan.state == .ended, !pan.fired else { return }
        let t = pan.translation(in: pan.view)
        let v = pan.velocity(in: pan.view)
        // A decided pull, or a quick flick.
        guard t.y > 44 || (t.y > 16 && v.y > 650) else { return }
        pan.fired = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Recognises only a finger that sets off downward, and never stands in anything else's way.
final class DownSwipeRecognizer: UIPanGestureRecognizer {
    var fired = false
    private var origin: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if origin == nil { origin = touches.first?.location(in: view?.window) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let origin, let point = touches.first?.location(in: view?.window) {
            let dx = point.x - origin.x, dy = point.y - origin.y
            if max(abs(dx), abs(dy)) > 6 && (dy <= 0 || abs(dx) > dy) {
                state = .failed
                return
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        origin = nil
        fired = false
    }

    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }
}
