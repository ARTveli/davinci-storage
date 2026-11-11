import SwiftUI
import StorageCore

struct ServiceView: View {
    @EnvironmentObject var model: AppModel
    let report: Report

    private func note(_ it: StorageItem) -> String {
        if it.url.lastPathComponent == ".LUT" {
            return "Скомпільовані копії твоїх LUT і мініатюри для LUT-браузера. DaVinci відтворить цей кеш сам при наступному використанні LUT. Зменшити його назавжди можна лише прибравши непотрібні LUT-паки з основної папки LUT."
        }
        return "Тимчасові файли DaVinci Resolve. Безпечно видаляти, коли програма закрита."
    }

    var body: some View {
        List {
            ForEach(report.service, id: \.url) { it in
                HStack(alignment: .top) {
                    Toggle("", isOn: Binding(get: { model.selected.contains(it.url) },
                                             set: { model.setSelected([it], $0) }))
                        .labelsHidden()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(it.label).font(.headline)
                        Text(note(it)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(it.url.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
                    }
                    Spacer()
                    SizeText(it.bytes).frame(width: 100)
                }
                .padding(.vertical, 4)
            }
            HStack(alignment: .top) {
                Image(systemName: "icloud.and.arrow.up").frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frame.io").font(.headline)
                    Text("Папку ще не знайдено (з'явиться після першого рендеру в Frame.io).")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
