import SwiftUI
import UIKit

// MARK: - Brand

/// The Quire mark from the app icon: three lines of text and a streaming cursor. Used on empty
/// states; the cursor breathes slowly unless Reduce Motion is on.
struct QuireMark: View {
    var width: CGFloat = 64
    var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        let h = width * 0.1
        VStack(alignment: .leading, spacing: h * 1.4) {
            Capsule().fill(Color.qInk).frame(width: width, height: h)
            Capsule().fill(Color.qInk).frame(width: width * 0.8, height: h)
            HStack(spacing: h * 0.67) {
                Capsule().fill(Color.qInk).frame(width: width * 0.5, height: h)
                RoundedRectangle(cornerRadius: h * 0.2, style: .continuous)
                    .fill(Color.qAccent)
                    .frame(width: h * 0.87, height: h * 1.53)
                    .opacity(dim ? 0.2 : 1)
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            guard breathing, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
    }
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
                .font(.system(.title3, design: .serif).weight(.semibold))
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

// MARK: - Toasts

struct ToastOverlay: View {
    let center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let t = center.current {
                HStack(spacing: 10) {
                    if let s = t.symbol {
                        Image(systemName: s).foregroundStyle(Color.qAccent)
                    }
                    Text(t.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.qInk)
                        .lineLimit(2)
                    if let label = t.actionLabel {
                        Button(label) { center.runAction() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.qAccent)
                            .buttonStyle(.plain)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 4)
                .padding(.horizontal, 20)
                .onTapGesture { center.dismiss() }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .id(t.id)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy, value: center.current)
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
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 96)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .card(radius: 8)
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
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 110)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .card(radius: 8)
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
                            .card(radius: 8)
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
