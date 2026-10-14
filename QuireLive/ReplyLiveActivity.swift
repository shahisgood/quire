import ActivityKit
import SwiftUI
import WidgetKit

@main
struct QuireLiveBundle: WidgetBundle {
    var body: some Widget {
        ReplyLiveActivity()
    }
}

/// A reply being written, after you've left Quire: on the Lock Screen and in the Dynamic Island.
/// A tap opens the chat.
struct ReplyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReplyActivityAttributes.self) { context in
            LockScreenReply(context: context)
                .activityBackgroundTint(LivePalette.base.opacity(0.94))
                .activitySystemActionForegroundColor(LivePalette.accent)
                .widgetURL(chatURL(context))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        LiveMark(size: 14)
                        Text(state.phase.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LivePalette.accent)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Elapsed(state: state)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(LivePalette.ink2)
                        .frame(maxWidth: 64, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.title)
                            .font(.system(.subheadline, design: .serif).weight(.semibold))
                            .foregroundStyle(LivePalette.ink)
                            .lineLimit(1)
                        if !state.snippet.isEmpty {
                            Text(state.snippet)
                                .font(.caption)
                                .foregroundStyle(LivePalette.ink2)
                                .lineLimit(2)
                        }
                        Text("\(context.attributes.model) · \(LiveFormat.tokens(state.tokens)) tokens")
                            .font(.caption2)
                            .foregroundStyle(LivePalette.ink2)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                LiveMark(size: 12)
            } compactTrailing: {
                if state.phase.isLive {
                    Elapsed(state: state)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(LivePalette.ink2)
                        .frame(width: 38)
                } else {
                    Image(systemName: state.phase.symbol)
                        .foregroundStyle(LivePalette.accent)
                }
            } minimal: {
                LiveMark(size: 12)
            }
            .widgetURL(chatURL(context))
            .keylineTint(LivePalette.accent)
        }
    }

    private func chatURL(_ context: ActivityViewContext<ReplyActivityAttributes>) -> URL? {
        URL(string: "quire://chat/\(context.attributes.chatId)")
    }
}

// MARK: - Lock Screen

private struct LockScreenReply: View {
    let context: ActivityViewContext<ReplyActivityAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LiveMark(size: 15)
                Text("Quire · \(context.attributes.model)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LivePalette.ink2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Elapsed(state: state)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(LivePalette.ink2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 70, alignment: .trailing)
            }
            Text(state.title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(LivePalette.ink)
                .lineLimit(1)
            if !state.snippet.isEmpty {
                Text(state.snippet)
                    .font(.subheadline)
                    .foregroundStyle(LivePalette.ink.opacity(0.8))
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Image(systemName: state.phase.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LivePalette.accent)
                Text(state.phase == .paused ? "Paused · open Quire to finish" : state.phase.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LivePalette.accent)
                if state.tokens > 0 {
                    Text("· \(LiveFormat.tokens(state.tokens)) tokens")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(LivePalette.ink2)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Pieces

/// Time since the reply started: a live count while it's being written, the final time after.
private struct Elapsed: View {
    let state: ReplyActivityAttributes.ContentState

    var body: some View {
        if let end = state.endedAt {
            Text(Duration.seconds(max(0, end.timeIntervalSince(state.startedAt))).formatted(.time(pattern: .minuteSecond)))
        } else {
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
        }
    }
}

/// The Quire mark from the app icon: three lines of text and the accent cursor.
private struct LiveMark: View {
    var size: CGFloat

    var body: some View {
        let bar = size * 0.14
        VStack(alignment: .leading, spacing: size * 0.16) {
            Capsule().fill(LivePalette.ink).frame(width: size, height: bar)
            Capsule().fill(LivePalette.ink).frame(width: size * 0.78, height: bar)
            HStack(spacing: size * 0.08) {
                Capsule().fill(LivePalette.ink).frame(width: size * 0.48, height: bar)
                RoundedRectangle(cornerRadius: size * 0.04)
                    .fill(LivePalette.accent)
                    .frame(width: size * 0.12, height: size * 0.24)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private enum LivePalette {
    static let accent = Color(red: 0x9A / 255, green: 0xA8 / 255, blue: 0xFF / 255)
    static let base = Color(red: 0x0E / 255, green: 0x10 / 255, blue: 0x13 / 255)
    static let ink = Color(red: 0xE8 / 255, green: 0xE6 / 255, blue: 0xE1 / 255)
    static let ink2 = Color(red: 0xE8 / 255, green: 0xE6 / 255, blue: 0xE1 / 255).opacity(0.6)
}

private enum LiveFormat {
    static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000 { return "\(Int((Double(n) / 1000).rounded()))k" }
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return String(n)
    }
}

extension ReplyPhase {
    var symbol: String {
        switch self {
        case .waiting: "ellipsis"
        case .thinking: "brain"
        case .writing: "pencil.line"
        case .done: "checkmark.circle.fill"
        case .stopped: "stop.circle"
        case .paused: "pause.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}
