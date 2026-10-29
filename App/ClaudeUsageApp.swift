import ServiceManagement
import SwiftUI
import WidgetKit

@main
struct ClaudeUsageApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Text(model.menuTitle)
        }
    }
}

@MainActor
final class UsageModel: ObservableObject {
    @Published var snapshot: UsageSnapshot? = SharedStore.load()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var timer: Timer?

    var menuTitle: String {
        guard let snapshot else { return "✳︎ –" }
        return "✳︎ " + Format.percent(snapshot.session.percent(at: Date()))
    }

    init() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        do {
            snapshot = try await UsageFetcher.fetch()
        } catch {
            // Tengo l'ultimo dato buono e segnalo l'errore nel widget.
            snapshot?.error = error.localizedDescription
        }
        if let snapshot { try? SharedStore.save(snapshot) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct MenuContent: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        if let s = model.snapshot {
            let now = Date()
            Text("Sessione: \(Format.percent(s.session.percent(at: now))) · reset tra \(Format.remaining(until: s.session.resetsAt, from: now))")
            Text("Settimana: \(Format.percent(s.weekly.percent(at: now))) · reset tra \(Format.remaining(until: s.weekly.resetsAt, from: now))")
            Text("Aggiornato alle \(s.fetchedAt.formatted(date: .omitted, time: .shortened))")
            if let error = s.error { Text("⚠︎ \(error)") }
            Divider()
        }
        Button("Aggiorna ora") { Task { await model.refresh() } }
        Toggle("Apri all'avvio", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
        Divider()
        Button("Esci") { NSApplication.shared.terminate(nil) }
    }
}
