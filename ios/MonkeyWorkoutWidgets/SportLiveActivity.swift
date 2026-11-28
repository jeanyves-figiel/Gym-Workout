import ActivityKit
import SwiftUI
import WidgetKit

private let lime = Color(red: 0.80, green: 1.0, blue: 0.24)

private func color(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

/// A Watch sport session on the lock screen and Dynamic Island (#1130, design B): run number or distance big, lift /
/// riding state, vertical, top speed and heart rate. The clock counts by itself, the rest follows the Watch.
struct SportLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SportActivityAttributes.self) { ctx in
            SportLockScreen(state: ctx.state, attributes: ctx.attributes)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(lime)
        } dynamicIsland: { ctx in
            let s = ctx.state
            let a = ctx.attributes
            let tint = color(a.tint2)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.stateLine(a)).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(tint)
                        Text(s.headline).font(.system(size: 22, weight: .black, design: .rounded)).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(s.verticalText).font(.system(size: 18, weight: .black, design: .rounded)).foregroundStyle(lime)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(s.detailLine).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: a.symbol)
                    Text(s.downhill ? "Run \(s.runs + (s.onLift ? 0 : 1))" : String(format: "%.1f", s.km)).monospacedDigit()
                }
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
            } compactTrailing: {
                Text(s.verticalText).monospacedDigit().foregroundStyle(lime)
            } minimal: {
                Image(systemName: a.symbol).foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

private struct SportLockScreen: View {
    let state: SportActivityAttributes.ContentState
    let attributes: SportActivityAttributes

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: attributes.symbol).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: [color(attributes.tint), color(attributes.tint2)], startPoint: .topLeading,
                                           endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(state.stateLine(attributes))
                    if !state.finished {
                        Text("·")
                        Text(timerInterval: attributes.startedAt...Date.distantFuture, countsDown: false).monospacedDigit()
                    }
                }
                .font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(lime).lineLimit(1)
                Text(state.headline).font(.system(size: 28, weight: .black, design: .rounded)).lineLimit(1)
                Text(state.detailLine).font(.system(size: 13, weight: .bold, design: .rounded)).opacity(0.9).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
    }
}

extension SportActivityAttributes.ContentState {
    /// "SNOWBOARD · ON LIFT", "RUN · PAUSED", "SKI · DONE".
    func stateLine(_ a: SportActivityAttributes) -> String {
        let what = finished ? "DONE" : paused ? "PAUSED" : downhill ? (onLift ? "ON LIFT" : "RIDING") : "LIVE"
        return "\(a.label.uppercased()) · \(what)"
    }

    /// "Run 5" (downhill; "4 runs" once done), else "12.4 km".
    var headline: String {
        if downhill { return finished || onLift ? "\(runs) run\(runs == 1 ? "" : "s")" : "Run \(runs + 1)" }
        return String(format: "%.1f km", km)
    }

    var verticalText: String { "\(vertical) m \(downhill ? "↓" : "↑")" }

    var detailLine: String {
        var parts = [verticalText]
        if downhill, let d = lastRunDrop, !finished { parts.append("last \(d) m") }
        if topKmh > 0 { parts.append("top \(topKmh) km/h") }
        if let hr = heartRate, !finished { parts.append("♥ \(hr)") }
        return parts.joined(separator: " · ")
    }
}
