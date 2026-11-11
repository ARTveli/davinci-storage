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
                .frame(minWidth: 1100, minHeight: 620)
        }
        .defaultSize(width: 1440, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Сканувати знову") { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isScanning)
            }
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
        case .leftovers: "archivebox"
        case .service: "gearshape.2"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 250, ideal: 290)
        } detail: {
            Group {
                if let r = model.result {
                    switch model.section ?? .projects {
                    case .projects: ProjectsView(report: r.report)
                    case .leftovers: LeftoversView(report: r.report)
                    case .service: ServiceView(report: r.report)
                    }
                } else {
                    ProgressView("Сканую бази DaVinci…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { Banners() }
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
            .navigationTitle(model.section?.rawValue ?? "DaVinci Storage")
            .toolbar { MainToolbar() }
        }
        .sheet(isPresented: $model.confirming) { ConfirmSheet() }
        .alert("Готово", isPresented: Binding(get: { model.lastClean != nil }, set: { if !$0 { model.lastClean = nil } })) {
            Button("OK") { model.lastClean = nil }
        } message: {
            if let r = model.lastClean {
                Text("У Кошику: \(r.trashed.count). Не вдалося: \(r.failed.count)."
                     + r.failed.prefix(5).map { "\n• \($0.url.lastPathComponent): \($0.reason)" }.joined())
            }
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: $model.section) {
            Section("Диск") {
                ForEach(SidebarSection.allCases) { s in
                    Label(s.rawValue, systemImage: s.icon)
                        .badge(Text(model.result == nil ? "" : formatBytes(model.total(s))).monospacedDigit())
                        .tag(s)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let r = model.result {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Усе, що знайдено").font(.caption).foregroundStyle(.secondary)
                    Text(formatBytes(r.report.grandTotal)).font(.title3.weight(.semibold)).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
    }
}

struct MainToolbar: ToolbarContent {
    @EnvironmentObject var model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.section == .projects || model.section == nil {
                Menu {
                    ForEach([1, 3, 6, 12], id: \.self) { m in
                        Button("Не змінювались понад \(m) міс.") { model.selectOld(months: m) }
                    }
                } label: {
                    Label("Позначити старі", systemImage: "calendar.badge.clock")
                }
                .accessibilityLabel("Позначити старі")
                .disabled(model.isUncertain || model.result == nil)
                .help(model.isUncertain ? "Частину даних не вдалося прочитати — автовибір вимкнено"
                                        : "Позначити все, що належить лише давно не відкритим проєктам")
            }

            Button { model.rescan() } label: {
                Label("Сканувати знову", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning)
            .help("Сканувати знову (⌘R)")

            Button(role: .destructive) { model.confirming = true } label: {
                Label("Перемістити в Кошик", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.selected.isEmpty || model.resolveRunning || model.isScanning)
            .help(model.resolveRunning ? "Спершу закрий DaVinci Resolve" : "Перемістити вибране в Кошик (⌘⌫)")

            if model.section == .projects || model.section == nil {
                Button { model.inspectorShown.toggle() } label: {
                    Label("Деталі", systemImage: "sidebar.trailing")
                }
                .help("Показати або сховати деталі проєкту")
            }
        }
    }
}

/// Non-blocking notices: Resolve running, scan uncertainty.
struct Banners: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.resolveRunning {
                Notice(icon: "lock.fill", tint: .orange,
                       title: "DaVinci Resolve відкритий — очищення вимкнено",
                       lines: ["Закрий DaVinci, щоб безпечно перемістити файли в Кошик."])
            }
            if let r = model.result?.report, r.isUncertain {
                Notice(icon: "exclamationmark.triangle.fill", tint: .orange,
                       title: "«Видалене» може бути неточним",
                       lines: r.warnings + r.unreadable.map { "Не вдалося прочитати проєкт: \($0.path)" })
            }
        }
    }
}

struct Notice: View {
    let icon: String
    let tint: Color
    let title: String
    let lines: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                ForEach(lines, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(tint.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct StatusBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("Сканування…").foregroundStyle(.secondary)
            } else if model.selected.isEmpty {
                Text("Нічого не вибрано").foregroundStyle(.secondary)
            } else {
                Text("Вибрано \(uaCount(model.selectedCount)) · \(formatBytes(model.selectedBytes))").monospacedDigit()
                Button("Зняти вибір") { model.selected = [] }.buttonStyle(.link)
            }
            Spacer()
            Text("Усе йде в Кошик — його можна відновити").font(.caption).foregroundStyle(.tertiary)
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// "1 об'єкт", "3 об'єкти", "5 об'єктів".
func uaCount(_ n: Int) -> String {
    let mod10 = n % 10, mod100 = n % 100
    let word = (mod10 == 1 && mod100 != 11) ? "об'єкт"
        : ((2...4).contains(mod10) && !(12...14).contains(mod100)) ? "об'єкти" : "об'єктів"
    return "\(n) \(word)"
}
