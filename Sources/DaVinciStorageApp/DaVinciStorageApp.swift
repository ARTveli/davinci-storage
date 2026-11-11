import AppKit
import SwiftUI
import StorageCore

@main
struct DaVinciStorageApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Lets `swift run` show a normal window too (inside the .app bundle this is a no-op).
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("DaVinci Storage") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 640)
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case projects = "Проєкти"
    case leftovers = "Видалені проєкти і дублі"
    case service = "Службові кеші"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .projects: "film.stack"
        case .leftovers: "trash.circle"
        case .service: "gearshape.2"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var section = Box<SidebarSection?>(.projects)

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $section.value) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
                if model.resolveRunning {
                    Text("Закрий DaVinci Resolve, щоб очищати")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color.orange.opacity(0.85))
                        .foregroundStyle(.black)
                }
                if let r = model.result {
                    if !r.report.unreadable.isEmpty {
                        Text("Не вдалося прочитати \(r.report.unreadable.count) проєкт(и) — «видалене» може бути неточним")
                            .font(.callout).padding(6).frame(maxWidth: .infinity).background(Color.yellow.opacity(0.3))
                    }
                    switch section.value ?? .projects {
                    case .projects: ProjectsView(report: r.report)
                    case .leftovers: LeftoversView(report: r.report)
                    case .service: ServiceView(report: r.report)
                    }
                } else {
                    ProgressView("Сканую…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                CleanupBar()
            }
            .toolbar {
                ToolbarItem {
                    Button { model.rescan() } label: {
                        Label("Сканувати знову", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isScanning)
                    .help("Сканувати знову")
                }
            }
            .navigationTitle(section.value?.rawValue ?? "DaVinci Storage")
            .navigationSubtitle(model.result.map { "Всього: \(formatBytes($0.report.grandTotal))" } ?? "")
        }
    }
}
