import SwiftUI
import StorageCore

struct ServiceView: View {
    @EnvironmentObject var model: AppModel
    let report: Report

    private func note(_ it: StorageItem) -> String {
        if it.url.lastPathComponent == ".LUT" {
            return "Скомпільовані копії твоїх LUT і мініатюри для LUT-браузера. DaVinci відтворить цей кеш сам, коли LUT знадобиться. Назавжди зменшити його можна лише прибравши непотрібні LUT-паки з основної папки LUT."
        }
        return "Тимчасові файли DaVinci Resolve. Безпечно видаляти, коли програма закрита."
    }

    private func icon(_ it: StorageItem) -> String {
        it.url.lastPathComponent == ".LUT" ? "camera.filters" : "internaldrive"
    }

    var body: some View {
        List {
            Section {
                ForEach(report.service, id: \.url) { it in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: Binding(get: { model.selected.contains(it.url) },
                                                 set: { model.setSelected([it], $0) }))
                            .labelsHidden()
                        Image(systemName: icon(it)).font(.title2).foregroundStyle(.secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(it.label).font(.headline)
                            Text(note(it)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Text(it.url.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
                        }
                        Spacer()
                        SizeText(it.bytes).frame(width: 90)
                    }
                    .padding(.vertical, 6)
                }
            } header: {
                Text("Кеші, які DaVinci створює сам")
            }
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "icloud.and.arrow.up").font(.title2).foregroundStyle(.secondary).frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Frame.io").font(.headline)
                        Text("Папку ще не знайдено — з'явиться після першого рендеру в Frame.io.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .padding(.leading, 30)
            }
        }
    }
}
