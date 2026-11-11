import AppKit
import SwiftUI
import StorageCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.settings.backupFolder
        panel.prompt = "Вибрати"
        if panel.runModal() == .OK, let url = panel.url { model.settings.backupFolder = url }
    }

    private func projectName(_ id: String) -> String {
        model.result?.report.rows.first { $0.id == id }?.project.name ?? id
    }

    var body: some View {
        Form {
            Section("Бекап баз перед очищенням") {
                LabeledContent("Папка") {
                    HStack {
                        Text(model.settings.backupFolder.path).lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled).foregroundStyle(.secondary)
                        Button("Вибрати…", action: chooseFolder)
                        Button {
                            try? FileManager.default.createDirectory(at: model.settings.backupFolder, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([model.settings.backupFolder])
                        } label: { Image(systemName: "arrow.right.circle") }
                        .buttonStyle(.borderless)
                        .help("Показати у Finder")
                    }
                }
                Stepper("Тримати останні \(model.settings.keepLibraryBackups)", value: $model.settings.keepLibraryBackups, in: 1...50)
                Text("Перед кожним очищенням копіюється папка «Resolve Projects» кожної бази в «дата · DaVinci Resolve версія». Найстаріші бекапи понад ліміт ідуть у Кошик.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Бекапи проєктів (Resolve Project Backups)") {
                Stepper("Лишати останні \(model.settings.keepProjectBackups) версії", value: $model.settings.keepProjectBackups, in: 1...20)
                Text("Для кожного проєкту окремо: Project.db і кожен таймлайн. Старіші вибирає «Позначити старі бекапи».")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Не чіпати") {
                if model.settings.protectedProjectIDs.isEmpty {
                    Text("Жодного. Познач проєкт у деталях проєкту.").foregroundStyle(.secondary)
                }
                ForEach(model.settings.protectedProjectIDs.sorted(), id: \.self) { id in
                    HStack {
                        Label(projectName(id), systemImage: "lock.fill")
                        Spacer()
                        Button("Прибрати") { model.setProtected(id, false) }.buttonStyle(.link)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
    }
}
