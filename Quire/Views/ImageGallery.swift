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

    init(images: [Attachment], startId: String) {
        self.images = images
        _currentId = State(initialValue: images.contains { $0.id == startId } ? startId : (images.first?.id ?? startId))
    }

    private var index: Int { images.firstIndex { $0.id == currentId } ?? 0 }
    /// The backdrop thins as you drag the image away, showing the chat underneath.
    private var backdrop: Double { 1 - min(0.9, Double(abs(dragY)) / 420) }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdrop)
                .ignoresSafeArea()

            TabView(selection: $currentId) {
                ForEach(images) { a in
                    ZoomableImage(attachment: a,
                                  isCurrent: a.id == currentId,
                                  onSingleTap: {
                                      withAnimation(reduceMotion ? nil : Motion.quick) { chrome.toggle() }
                                  },
                                  onDismissDrag: { dragY = $0 },
                                  onDismissEnd: { dy, vy in
                                      if abs(dy) > 110 || abs(vy) > 900 {
                                          Haptics.tap()
                                          dismiss()
                                      } else {
                                          withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Motion.bouncy) { dragY = 0 }
                                      }
                                  })
                        .tag(a.id)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
        .sensoryFeedback(.selection, trigger: currentId)
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
                            Haptics.selection()
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

/// One image in the gallery, in a UIKit scroll view, which zooms and pans exactly like Photos and
/// hands sideways swipes to the pager whenever it isn't zoomed in.
private struct ZoomableImage: UIViewRepresentable {
    let attachment: Attachment
    let isCurrent: Bool
    var onSingleTap: () -> Void
    var onDismissDrag: (CGFloat) -> Void
    var onDismissEnd: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> ZoomImageScrollView {
        let v = ZoomImageScrollView(frame: .zero)
        v.imageView.accessibilityLabel = attachment.name
        if let sharp = ThumbnailCache.cachedScreenImage(for: attachment) {
            v.setImage(sharp)
        } else {
            // The thumbnail first, if it's there, then the sharp one as soon as it's decoded.
            v.setImage(ThumbnailCache.cachedThumbnail(for: attachment))
            let a = attachment
            Task { [weak v] in
                let sharp = await ThumbnailCache.screenImage(for: a)
                v?.setImage(sharp)
            }
        }
        return v
    }

    func updateUIView(_ v: ZoomImageScrollView, context: Context) {
        v.onSingleTap = onSingleTap
        v.onDismissDrag = onDismissDrag
        v.onDismissEnd = onDismissEnd
        // An image you've swiped away from goes back to fitting the screen, as in Photos.
        if !isCurrent, v.zoomScale > v.minimumZoomScale + 0.01 {
            v.setZoomScale(v.minimumZoomScale, animated: false)
        }
    }
}

final class ZoomImageScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var onSingleTap: (() -> Void)?
    var onDismissDrag: ((CGFloat) -> Void)?
    var onDismissEnd: ((CGFloat, CGFloat) -> Void)?

    private let dismissPan = UIPanGestureRecognizer()
    private let simultaneous = SimultaneousGestures()
    private var fittedTo: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        imageView.accessibilityIgnoresInvertColors = true
        addSubview(imageView)

        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        single.require(toFail: double)
        addGestureRecognizer(single)

        dismissPan.addTarget(self, action: #selector(panned(_:)))
        dismissPan.delegate = simultaneous
        addGestureRecognizer(dismissPan)
    }

    required init?(coder: NSCoder) { return nil }

    func setImage(_ image: UIImage?) {
        guard let image else { return }
        imageView.image = image
        fittedTo = .zero
        setNeedsLayout()
    }

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

    /// Keeps the image in the middle while it's smaller than the screen on either axis.
    private func centre() {
        let w = max(0, (bounds.width - contentSize.width) / 2)
        let h = max(0, (bounds.height - contentSize.height) / 2)
        let inset = UIEdgeInsets(top: h, left: w, bottom: h, right: w)
        if contentInset != inset { contentInset = inset }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centre() }

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
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
        case .ended, .cancelled, .failed: onDismissEnd?(dy, g.velocity(in: self).y)
        default: break
        }
    }

    /// The swipe that puts the gallery away starts only when the image isn't zoomed and the drag is
    /// mostly vertical, so it never fights panning around a zoomed image or swiping to the next one.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g === dismissPan {
            guard zoomScale <= minimumZoomScale + 0.01 else { return false }
            let v = dismissPan.velocity(in: self)
            return abs(v.y) > abs(v.x) * 1.3
        }
        return super.gestureRecognizerShouldBegin(g)
    }
}

/// Lets the swipe-down run alongside the scroll view's own gestures.
private final class SimultaneousGestures: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
