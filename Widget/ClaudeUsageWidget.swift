import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: context.isPreview ? .placeholder : SharedStore.load()))
    }

    /// Una voce al minuto per far scendere il conto alla rovescia; l'app ricarica il widget a ogni nuovo dato.
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snapshot = SharedStore.load()
        let start = Calendar.current.dateInterval(of: .minute, for: Date())?.start ?? Date()
        let entries = (0..<60).map { i in
            UsageEntry(date: start.addingTimeInterval(Double(i) * 60), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

private func usageColor(for percent: Double) -> Color {
    switch percent {
    case ..<70: return claudeOrange
    case ..<90: return .yellow
    default: return .red
    }
}

struct Ring: View {
    let percent: Double
    var lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(percent, 100) / 100)
                .stroke(usageColor(for: percent), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(Format.percent(percent))
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
    }
}

struct WindowColumn: View {
    let title: String
    let window: UsageWindow
    let now: Date

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Ring(percent: window.percent(at: now))
            Text("resets in \(Format.remaining(until: window.resetsAt, from: now))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct Footer: View {
    let snapshot: UsageSnapshot

    var body: some View {
        if snapshot.error != nil {
            Label("updated at \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))",
                  systemImage: "exclamationmark.triangle")
                .font(.system(size: 9)).foregroundStyle(.orange)
        }
    }
}

struct SmallView: View {
    let snapshot: UsageSnapshot
    let now: Date

    var body: some View {
        VStack(spacing: 6) {
            Ring(percent: snapshot.session.percent(at: now))
            Text("resets in \(Format.remaining(until: snapshot.session.resetsAt, from: now))")
                .font(.caption2.weight(.medium))
            Text("week \(Format.percent(snapshot.weekly.percent(at: now)))")
                .font(.caption2).foregroundStyle(.secondary)
            Footer(snapshot: snapshot)
        }
    }
}

struct MediumView: View {
    let snapshot: UsageSnapshot
    let now: Date

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 24) {
                WindowColumn(title: "Session (5h)", window: snapshot.session, now: now)
                WindowColumn(title: "Week", window: snapshot.weekly, now: now)
            }
            Footer(snapshot: snapshot)
        }
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                if family == .systemSmall {
                    SmallView(snapshot: snapshot, now: entry.date)
                } else {
                    MediumView(snapshot: snapshot, now: entry.date)
                }
            } else {
                Text("Open the Claude Usage app")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageWidget", provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Usage percentage and time until reset.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
