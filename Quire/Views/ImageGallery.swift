import SwiftUI
import UIKit

/// Every image in the chat, full screen, the way Photos shows them: swipe sideways from one to the
/// next, pinch or double-tap to zoom (and drag around while zoomed), swipe down to put it away, tap
/// to hide or show the controls. A filmstrip along the bottom jumps straight to any of them.
struct ImageGallery: View {
    let images: [Attachment]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentId: String
    @State private var dragY: CGFloat = 0
    @State private var chrome = true
    @State private var sharing: UIImage? = nil

    /// How far down an image has to be dragged before letting go puts the gallery away.
    private static let dismissDistance: CGFloat = 110

    init(images: [Attachment], startId: String) {
        self.images = images
        _currentId = State(initialValue: images.contains { $0.id == startId } ? startId : (images.first?.id ?? startId))
    }

    private var index: Int { images.firstIndex { $0.id == currentId } ?? 0 }
    /// The backdrop thins as you drag the image away, showing the chat underneath.
    private var backdrop: Double { 1 - min(0.9, Double(abs(dragY)) / 420) }
    private var armed: Bool { abs(dragY) > Self.dismissDistance }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdrop)
                .ignoresSafeArea()

            GalleryPager(images: images, currentId: $currentId,
                         onSingleTap: {
                             withAnimation(reduceMotion ? nil : Motion.quick) { chrome.toggle() }
                         },
                         onDismissDrag: { dragY = $0 },
                         onDismissEnd: { dy, vy in
                             if abs(dy) > Self.dismissDistance || abs(vy) > 900 {
                                 dismiss()
                             } else {
                                 withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Motion.bouncy) { dragY = 0 }
                             }
                         })
                .ignoresSafeArea()
                .offset(y: dragY)
                .scaleEffect(reduceMotion ? 1 : 1 - min(0.15, abs(dragY) / 2200))
        }
        .overlay(alignment: .top) {
            if chrome {
                topBar
                    .opacity(backdrop)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if chrome && images.count > 1 {
                filmstrip
                    .opacity(backdrop)
                    .transition(.opacity)
            }
        }
        .statusBarHidden(!chrome)
        .presentationBackground(.clear)
        // A tick for each new image, and one as a swipe down passes the point where letting go
        // closes the gallery (and again if you pull back from it).
        .onChange(of: currentId) { Haptics.selection() }
        .onChange(of: armed) { Haptics.selection() }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let sharing { ShareSheet(items: [sharing]).presentationDetents([.medium, .large]) }
        }
        .accessibilityAction(.escape) { dismiss() }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Close")

            Spacer()

            if images.count > 1 {
                Text("\(index + 1) of \(images.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .glassEffect(.regular, in: .capsule)
                    .animation(Motion.quick, value: index)
            }

            Spacer()

            Button {
                guard let a = images.first(where: { $0.id == currentId }) else { return }
                Haptics.tap()
                Task { sharing = await ThumbnailCache.screenImage(for: a) }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Share or save")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(images) { a in
                        let on = a.id == currentId
                        Button {
                            withAnimation(reduceMotion ? nil : Motion.standard) { currentId = a.id }
                        } label: {
                            GalleryThumb(attachment: a)
                                .frame(width: on ? 46 : 38, height: 52)
                                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.white.opacity(on ? 0.9 : 0), lineWidth: 1.5))
                                .opacity(on ? 1 : 0.55)
                        }
                        .buttonStyle(.plain)
                        .id(a.id)
                        .accessibilityLabel("Image \((images.firstIndex(of: a) ?? 0) + 1)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .animation(reduceMotion ? nil : Motion.quick, value: currentId)
            }
            .glassEffect(.regular, in: .capsule)
            .frame(maxWidth: CGFloat(images.count) * 44 + 60)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
            .onAppear { proxy.scrollTo(currentId, anchor: .center) }
            .onChange(of: currentId) { _, id in
                withAnimation(reduceMotion ? nil : Motion.standard) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

/// A small square of an image, decoded off the main thread.
private struct GalleryThumb: View {
    let attachment: Attachment
    @State private var image: UIImage? = nil

    var body: some View {
        Color.white.opacity(0.08)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: attachment.id) {
                if let hit = ThumbnailCache.cachedThumbnail(for: attachment) { image = hit; return }
                image = await ThumbnailCache.thumbnail(for: attachment)
            }
    }
}

// MARK: - Pager

/// The images side by side in a UIKit paging scroll view, each in a zooming scroll view of its own:
/// the arrangement Photos-style viewers use, where pinching, panning a zoomed image and paging hand
/// over to each other cleanly. Paging and the swipe down both take one finger, so a two-finger pinch
/// only ever zooms.
private struct GalleryPager: UIViewRepresentable {
    let images: [Attachment]
    @Binding var currentId: String
    var onSingleTap: () -> Void
    var onDismissDrag: (CGFloat) -> Void
    var onDismissEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GalleryPagerView {
        let v = GalleryPagerView(images: images)
        let coordinator = context.coordinator
        v.onPageChange = { [weak coordinator] i in coordinator?.pageChanged(to: i) }
        v.show(index: images.firstIndex { $0.id == currentId } ?? 0, animated: false)
        apply(to: v)
        return v
    }

    func updateUIView(_ v: GalleryPagerView, context: Context) {
        context.coordinator.parent = self
        apply(to: v)
        // A jump from the filmstrip.
        if let i = images.firstIndex(where: { $0.id == currentId }), i != v.currentIndex {
            v.show(index: i, animated: true)
        }
    }

    private func apply(to v: GalleryPagerView) {
        v.onSingleTap = onSingleTap
        v.onDismissDrag = onDismissDrag
        v.onDismissEnd = onDismissEnd
    }

    final class Coordinator {
        var parent: GalleryPager

        init(_ parent: GalleryPager) { self.parent = parent }

        func pageChanged(to i: Int) {
            guard parent.images.indices.contains(i) else { return }
            let id = parent.images[i].id
            if parent.currentId != id { parent.currentId = id }
        }
    }
}

final class GalleryPagerView: UIView, UIScrollViewDelegate {
    var onPageChange: ((Int) -> Void)?
    var onSingleTap: (() -> Void)?
    var onDismissDrag: ((CGFloat) -> Void)?
    var onDismissEnd: ((CGFloat, CGFloat) -> Void)?
    private(set) var currentIndex = 0

    private let pager = UIScrollView()
    private var pages: [ZoomPage] = []
    private var pendingIndex: Int? = nil
    private var laidOutSize: CGSize = .zero
    /// A jump from the filmstrip is under way: the pages it passes on the way aren't "current".
    private var jumping = false
    /// The dark strip between images while you swipe, as in Photos.
    private let gap: CGFloat = 20

    init(images: [Attachment]) {
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .clear

        pager.isPagingEnabled = true
        pager.showsHorizontalScrollIndicator = false
        pager.showsVerticalScrollIndicator = false
        pager.alwaysBounceVertical = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.decelerationRate = .fast
        pager.delegate = self
        pager.panGestureRecognizer.maximumNumberOfTouches = 1
        addSubview(pager)

        for a in images {
            let page = ZoomPage(attachment: a)
            page.onSingleTap = { [weak self] in self?.onSingleTap?() }
            page.onDismissDrag = { [weak self] in self?.onDismissDrag?($0) }
            page.onDismissEnd = { [weak self] in self?.onDismissEnd?($0, $1) }
            pager.addSubview(page)
            pages.append(page)
        }
    }

    required init?(coder: NSCoder) { return nil }

    func show(index: Int, animated: Bool) {
        guard pages.indices.contains(index) else { return }
        currentIndex = index
        guard bounds.width > 0 else {
            pendingIndex = index
            return
        }
        jumping = animated
        pager.setContentOffset(CGPoint(x: CGFloat(index) * (bounds.width + gap), y: 0), animated: animated)
        loadAround(index)
        if !animated { settle() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        let w = bounds.width
        let h = bounds.height
        let stride = w + gap
        pager.frame = CGRect(x: -gap / 2, y: 0, width: stride, height: h)
        for (i, page) in pages.enumerated() {
            page.frame = CGRect(x: CGFloat(i) * stride + gap / 2, y: 0, width: w, height: h)
        }
        pager.contentSize = CGSize(width: stride * CGFloat(pages.count), height: h)
        let target = pendingIndex ?? currentIndex
        pendingIndex = nil
        currentIndex = target
        pager.contentOffset = CGPoint(x: CGFloat(target) * stride, y: 0)
        loadAround(target)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let stride = bounds.width + gap
        guard stride > gap else { return }
        let i = min(max(0, Int((scrollView.contentOffset.x / stride).rounded())), pages.count - 1)
        if jumping {
            loadAround(i)
            return
        }
        if i != currentIndex {
            currentIndex = i
            loadAround(i)
            onPageChange?(i)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        jumping = false
        loadAround(currentIndex)
        settle()
    }

    /// Your own swipe takes over from a jump still animating.
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { jumping = false }

    /// Images swiped away from go back to fitting the screen once the swipe has finished, as in
    /// Photos (not during it, which would make them jump while still in view).
    private func settle() {
        for (i, page) in pages.enumerated() where i != currentIndex {
            page.resetZoom()
        }
    }

    /// Only the image on screen and its neighbours hold a decoded image; the rest let theirs go.
    private func loadAround(_ i: Int) {
        for (j, page) in pages.enumerated() {
            if abs(j - i) <= 1 { page.load() } else { page.unload() }
        }
    }
}

// MARK: - One zoomable image

final class ZoomPage: UIScrollView, UIScrollViewDelegate {
    let attachment: Attachment
    var onSingleTap: (() -> Void)?
    var onDismissDrag: ((CGFloat) -> Void)?
    var onDismissEnd: ((CGFloat, CGFloat) -> Void)?

    private let imageView = UIImageView()
    private let dismissPan = UIPanGestureRecognizer()
    private let gestures = PageGestures()
    private var fittedTo: CGSize = .zero
    private var loading: Task<Void, Never>? = nil

    init(attachment: Attachment) {
        self.attachment = attachment
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        imageView.accessibilityLabel = attachment.name
        imageView.accessibilityIgnoresInvertColors = true
        addSubview(imageView)

        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        single.require(toFail: double)
        addGestureRecognizer(single)

        dismissPan.maximumNumberOfTouches = 1
        dismissPan.addTarget(self, action: #selector(panned(_:)))
        dismissPan.delegate = gestures
        addGestureRecognizer(dismissPan)
    }

    required init?(coder: NSCoder) { return nil }

    // MARK: Image

    func load() {
        guard imageView.image == nil, loading == nil else { return }
        if let sharp = ThumbnailCache.cachedScreenImage(for: attachment) {
            setImage(sharp)
            return
        }
        // The thumbnail at once if it's there, then the sharp image as soon as it's decoded.
        if let thumb = ThumbnailCache.cachedThumbnail(for: attachment) { setImage(thumb) }
        let a = attachment
        loading = Task { [weak self] in
            let sharp = await ThumbnailCache.screenImage(for: a)
            guard let self, !Task.isCancelled else { return }
            self.loading = nil
            self.setImage(sharp)
        }
    }

    func unload() {
        loading?.cancel()
        loading = nil
        guard imageView.image != nil else { return }
        resetZoom()
        imageView.image = nil
        fittedTo = .zero
    }

    func resetZoom() {
        if zoomScale > minimumZoomScale + 0.001 { setZoomScale(minimumZoomScale, animated: false) }
    }

    private func setImage(_ image: UIImage?) {
        guard let image else { return }
        // A sharper copy of the same picture: swap it in without refitting, so a zoom already under
        // way isn't snapped back.
        if let old = imageView.image, old.size.height > 0, image.size.height > 0,
           abs(old.size.width / old.size.height - image.size.width / image.size.height) < 0.01 {
            imageView.image = image
            return
        }
        imageView.image = image
        fittedTo = .zero
        setNeedsLayout()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedTo, let img = imageView.image, img.size.width > 0, img.size.height > 0,
           bounds.width > 0, bounds.height > 0 {
            fittedTo = bounds.size
            zoomScale = minimumZoomScale
            let scale = min(bounds.width / img.size.width, bounds.height / img.size.height)
            let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: size)
            contentSize = size
        }
        centre()
    }

    /// Keeps the image in the middle on whichever axis it's smaller than the screen.
    private func centre() {
        let w = max(0, (bounds.width - contentSize.width) / 2)
        let h = max(0, (bounds.height - contentSize.height) / 2)
        let inset = UIEdgeInsets(top: h, left: w, bottom: h, right: w)
        if contentInset != inset { contentInset = inset }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centre() }

    /// A pinch that starts while the image is being dragged down calls the drag off.
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        if dismissPan.state == .began || dismissPan.state == .changed {
            dismissPan.isEnabled = false
            dismissPan.isEnabled = true
        }
    }

    // MARK: Gestures

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        Haptics.tap()
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let p = g.location(in: imageView)
            let s: CGFloat = 2.5
            let size = CGSize(width: bounds.width / s, height: bounds.height / s)
            zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func singleTapped() { onSingleTap?() }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let dy = g.translation(in: self).y
        switch g.state {
        case .changed: onDismissDrag?(dy)
        case .ended: onDismissEnd?(dy, g.velocity(in: self).y)
        case .cancelled, .failed: onDismissEnd?(0, 0)
        default: break
        }
    }

    /// The swipe that puts the gallery away starts only with one finger, on an image that isn't
    /// zoomed, moving mostly up or down; so it never fights a pinch, panning a zoomed image, or
    /// swiping to the next one.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g === dismissPan {
            guard g.numberOfTouches <= 1, zoomScale <= minimumZoomScale + 0.01, !isZooming else { return false }
            let v = dismissPan.velocity(in: self)
            return abs(v.y) > abs(v.x) * 1.3
        }
        return super.gestureRecognizerShouldBegin(g)
    }
}

/// The swipe down runs alongside the scroll views' own panning, but never alongside a pinch.
private final class PageGestures: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        !(other is UIPinchGestureRecognizer)
    }
}
