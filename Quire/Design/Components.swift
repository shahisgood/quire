import SwiftUI
import UIKit

// MARK: - Brand

/// The Quire mark from the app icon: three lines of text and a streaming cursor. Used on empty
/// states; the cursor breathes slowly unless Reduce Motion is on.
///
/// Where it's `playful`, three taps write it out again. The cursor narrows into a text caret, backs
/// over the three lines, then types them back, gliding with the ink, blinking once at the end of each
/// line as it drops to the next, with a soft tick for each. When the last line is down, the caret
/// swells back into the block and the mark gives a little stamp.
struct QuireMark: View {
    var width: CGFloat = 64
    var breathing = false
    var playful = false
    var onWritten: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    @State private var written: CGFloat = 3
    /// 0 is the block cursor of the icon, 1 a thin text caret.
    @State private var caret: CGFloat = 0
    @State private var writing = false
    @State private var stamp = false

    var body: some View {
        let mark = MarkDrawing(width: width, written: written, caret: caret,
                               cursorOpacity: writing ? 1 : (dim ? 0.2 : 1))
            .scaleEffect(stamp ? 1.08 : 1)
            .accessibilityHidden(true)
            .onAppear(perform: breathe)
        if playful {
            mark
                .contentShape(.rect)
                .onTapGesture(count: 3, perform: write)
        } else {
            mark
        }
    }

    private func breathe() {
        guard breathing, !reduceMotion else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { dim = false }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
    }

    private func write() {
        guard !writing else { return }
        writing = true
        Haptics.tap()
        if reduceMotion {
            Haptics.success()
            writing = false
            onWritten()
            breathe()
            return
        }
        let narrow = 0.18, erase = 0.5, pen = 2.4
        withAnimation(.easeOut(duration: narrow)) { caret = 1 }
        withAnimation(.easeInOut(duration: erase).delay(narrow)) { written = 0 } completion: {
            withAnimation(.linear(duration: pen)) { written = 3 } completion: {
                Haptics.success()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                    caret = 0
                    stamp = true
                } completion: {
                    withAnimation(Motion.bouncy) { stamp = false }
                }
                writing = false
                breathe()
                onWritten()
            }
        }
        // A soft tick as each line is finished, like a carriage return.
        for line in 0..<3 {
            let at = narrow + erase + pen * (Double(line) + MarkDrawing.lineShare) / 3
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(at))
                Haptics.soft()
            }
        }
    }
}

/// The mark itself, drawn with as much of its three lines on the page as `written` says (0 to 3).
/// Each line runs out smoothly, easing in and out like a hand finding its pace, then rests a beat
/// before the next begins; the cursor rides just after the ink of the line being written, and
/// blinks once in each rest.
private struct MarkDrawing: View, Animatable {
    let width: CGFloat
    var written: CGFloat
    var caret: CGFloat
    let cursorOpacity: Double

    /// The part of each line's turn spent writing; the rest is the pause before the next.
    static let lineShare: Double = 0.8

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(written, caret) }
        set {
            written = newValue.first
            caret = newValue.second
        }
    }

    var body: some View {
        let h = width * 0.1
        let lengths = [width, width * 0.8, width * 0.5]
        let centers = [h * 0.5, h * 2.9, h * 5.565]
        // The block of the icon, or a slim caret a little taller than the text.
        let caretW = lerp(h * 0.87, h * 0.3, caret)
        let caretH = lerp(h * 1.53, h * 1.75, caret)
        let gap = lerp(h * 0.67, h * 0.4, caret)
        let line = (0..<3).first { inked($0) < 1 } ?? 2
        let ink = inked(line)
        let caretX = lengths[line] * ink + (ink > 0 ? gap : 0)
        ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Color.qInk)
                    .frame(width: lengths[i] * inked(i), height: h)
                    .offset(y: centers[i] - h / 2)
            }
            RoundedRectangle(cornerRadius: min(caretW, h) * 0.3, style: .continuous)
                .fill(Color.qAccent)
                .frame(width: caretW, height: caretH)
                .opacity(cursorOpacity * blink)
                .offset(x: caretX, y: centers[line] - caretH / 2)
        }
        .frame(width: width, height: h * 6.33, alignment: .topLeading)
    }

    /// How much of line `i` is on the page, eased so each line starts and finishes gently.
    private func inked(_ i: Int) -> CGFloat {
        let f = min(1, max(0, (written - CGFloat(i)) / CGFloat(Self.lineShare)))
        return f * f * (3 - 2 * f)
    }

    /// The caret dips once in the rest between lines, and only while it's a caret.
    private var blink: Double {
        let phase = Double(written - written.rounded(.down))
        guard caret > 0.5, written < 3, phase > Self.lineShare else { return 1 }
        let t = (phase - Self.lineShare) / (1 - Self.lineShare)
        return 1 - 0.8 * sin(.pi * t)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}

// MARK: - Small pieces

/// Small-caps section label: the "folio" voice used for headers throughout.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(Color.qInk2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rounded-square symbol tile for settings rows. Scales with Dynamic Type.
struct IconTile: View {
    let symbol: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.5, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: side, height: side)
            .background(color, in: .rect(cornerRadius: side * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A settings row label: tile, title, optional one-line detail.
struct TileLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Color.qInk)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// A thin capacity bar (context window, memory budget, key credit).
struct MeterBar: View {
    var fraction: Double
    var warn = false
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.qRule)
                Capsule()
                    .fill(warn ? Color.qAccent : Color.qInk2)
                    .frame(width: max(height, min(1, max(0, fraction)) * geo.size.width))
            }
        }
        .frame(height: height)
        .animation(Motion.quick, value: fraction)
        .accessibilityHidden(true)
    }
}

/// A capsule toggle chip for filters and presets.
struct FilterChip: View {
    let title: String
    var symbol: String? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isOn ? Color.qOnAccent : Color.qInk)
            .background(isOn ? Color.qAccent : Color.qRaised, in: .capsule)
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Color.qRule, lineWidth: 1))
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .animation(Motion.quick, value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A label with an (i) that reveals a one-paragraph explanation, plus a dot when the value is
/// set at this level (a per-chat or per-persona override).
struct HelpLabel: View {
    let title: String
    let help: String
    var overridden = false
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(Motion.quick) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if overridden {
                        Circle().fill(Color.qAccent).frame(width: 6, height: 6)
                            .accessibilityLabel("Set here")
                    }
                    Text(title).foregroundStyle(Color.qInk)
                    Image(systemName: open ? "info.circle.fill" : "info.circle")
                        .font(.footnote)
                        .foregroundStyle(open ? Color.qAccent : Color.qInk2)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the explanation" : "Explains this setting")
            if open {
                Text(help)
                    .font(.footnote)
                    .foregroundStyle(Color.qInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }
}

/// Centered empty state with the Quire mark.
struct EmptyState<Actions: View>: View {
    let title: String
    let message: String
    var showMark = true
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            if showMark { QuireMark(width: 56, breathing: true).padding(.bottom, 8) }
            Text(title)
                .displayFont { .system(.title3, design: $0).weight(.semibold) }
                .foregroundStyle(Color.qInk)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.qInk2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions()
                .padding(.top, 6)
        }
        .frame(maxWidth: 340)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Confirmations

/// For irreversible actions: the PWA's typed confirmation ("type wipe to confirm").
struct TypedConfirmSheet: View {
    let title: String
    let message: String
    let word: String
    let actionLabel: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var matches: Bool { text.trimmingCharacters(in: .whitespaces).lowercased() == word }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(message)
                    .foregroundStyle(Color.qInk2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Type “\(word)” to confirm.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.qInk)
                TextField(word, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .padding(12)
                    .card(radius: 12)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if matches { confirm() } }
                Button(role: .destructive, action: confirm) {
                    Text(actionLabel)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.qDanger)
                .disabled(!matches)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.qBase)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func confirm() {
        guard matches else { return }
        Haptics.warning()
        onConfirm()
        dismiss()
    }
}

// MARK: - UIKit bridges

nonisolated struct SharedFile: Identifiable, Sendable {
    let url: URL
    var id: String { url.path }
}

/// The system share sheet, for handing a file to Files, AirDrop, Mail and so on.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Read-only text with real range selection (SwiftUI's text selection on iOS copies the whole string).
struct SelectableTextView: UIViewRepresentable {
    let text: String
    var monospaced = false

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.backgroundColor = .clear
        v.adjustsFontForContentSizeCategory = true
        v.textContainerInset = UIEdgeInsets(top: 16, left: 14, bottom: 32, right: 14)
        v.dataDetectorTypes = [.link]
        v.alwaysBounceVertical = true
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        if v.text != text { v.text = text }
        if monospaced {
            let size = UIFont.preferredFont(forTextStyle: .footnote).pointSize
            v.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: UIFont.monospacedSystemFont(ofSize: size, weight: .regular))
        } else {
            v.font = UIFont.preferredFont(forTextStyle: .body)
        }
        v.textColor = UIColor(Color.qInk)
    }
}

/// The camera, for "Take photo" in the composer.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, dismiss: { dismiss() }) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: () -> Void
        init(onImage: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onImage(img) }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { dismiss() }
    }
}

// MARK: - Inputs

/// An optional number: empty means "unset, let the provider decide".
struct OptionalNumberField: View {
    let placeholder: String
    @Binding var value: Double?
    var range: ClosedRange<Double>? = nil

    var body: some View {
        TextField(placeholder, value: Binding(
            get: { value },
            set: { (v: Double?) in
                guard let v else { value = nil; return }
                if let r = range { value = min(max(v, r.lowerBound), r.upperBound) } else { value = v }
            }), format: .number)
            .keyboardType(.numbersAndPunctuation)
            .modifier(ValuePill(width: 64))
    }
}

struct OptionalIntField: View {
    let placeholder: String
    @Binding var value: Int?
    var range: ClosedRange<Int>? = nil

    var body: some View {
        TextField(placeholder, value: Binding(
            get: { value },
            set: { (v: Int?) in
                guard let v else { value = nil; return }
                if let r = range { value = min(max(v, r.lowerBound), r.upperBound) } else { value = v }
            }), format: .number)
            .keyboardType(.numbersAndPunctuation)
            .modifier(ValuePill(width: 92))
    }
}

/// A number you can type, in a sunken pill: figures centred and tabular, the placeholder showing
/// what applies when it's left empty.
private struct ValuePill: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.medium).monospacedDigit())
            .foregroundStyle(Color.qInk)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(Color.qSunken, in: .capsule)
    }
}

/// Tags with remove buttons and a field to add more (stop sequences, ignored providers).
struct TagField: View {
    @Binding var tags: [String]
    var limit: Int? = nil
    var placeholder: String
    var monospaced = true
    @State private var text = ""

    private var canAdd: Bool { limit.map { tags.count < $0 } ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(tags.enumerated()), id: \.offset) { i, tag in
                            HStack(spacing: 4) {
                                Text(visible(tag))
                                    .font(monospaced ? .footnote.monospaced() : .footnote)
                                    .foregroundStyle(Color.qInk)
                                Button {
                                    withAnimation(Motion.quick) { _ = tags.remove(at: i) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Color.qInk2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(tag)")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.qSunken, in: .capsule)
                        }
                    }
                }
            }
            if canAdd {
                TextField(placeholder, text: $text)
                    .font(monospaced ? .body.monospaced() : .body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(add)
            }
        }
    }

    /// Show control characters the way the PWA does (\n rather than a line break).
    private func visible(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
    }

    private func add() {
        let raw = text.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
        guard !raw.isEmpty, canAdd else { return }
        withAnimation(Motion.quick) { tags.append(raw) }
        text = ""
    }
}
