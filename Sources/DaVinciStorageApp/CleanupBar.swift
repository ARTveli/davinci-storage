import SwiftUI
import StorageCore

struct CleanupBar: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var confirming = Box(false)

    var body: some View {
        HStack {
            if model.isScanning { ProgressView().controlSize(.small) }
            Text("Вибрано: \(model.selected.isEmpty ? "нічого" : formatBytes(model.selectedBytes))")
                .font(.headline).monospacedDigit()
            if !model.selected.isEmpty {
                Button("Зняти вибір") { model.selected = [] }.buttonStyle(.borderless)
            }
            Spacer()
            Button("Перемістити в Кошик…") { confirming.value = true }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selected.isEmpty || model.resolveRunning || model.isScanning)
                .help(model.resolveRunning ? "Спершу закрий DaVinci Resolve" : "Усе піде в Кошик — його можна відновити")
        }
        .padding(10)
        .sheet(isPresented: $confirming.value) { ConfirmSheet(isPresented: $confirming.value) }
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

struct ConfirmSheet: View {
    @EnvironmentObject var model: AppModel
    @Binding var isPresented: Bool

    private var items: [StorageItem] {
        model.selected.compactMap { model.itemsByURL[$0] }.sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Перемістити в Кошик \(items.count) об'єкт(ів) — \(formatBytes(model.selectedBytes))?")
                .font(.title3.weight(.semibold))
            Text("Бази проєктів не змінюються. Усе можна відновити з Кошика, доки ти його не очистиш.")
                .font(.callout).foregroundStyle(.secondary)
            List(items, id: \.url) { it in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(it.category.title) · \(it.label)").font(.callout.weight(.medium))
                        Spacer()
                        SizeText(it.bytes).frame(width: 90)
                    }
                    Text(it.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    let shared = model.sharedWith(it)
                    if !shared.isEmpty {
                        Text("⚠️ Цю папку також використовує: \(shared.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if model.uncertainURLs.contains(it.url) {
                        Text("⚠️ Не доведено, що проєкт видалено — частину даних не вдалося прочитати").font(.caption).foregroundStyle(.orange)
                    }
                    if it.match == .byName {
                        Text("⚠️ Прив'язано лише за назвою папки").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .frame(minHeight: 260)
            HStack {
                Spacer()
                Button("Скасувати") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button("Перемістити в Кошик") {
                    isPresented = false
                    model.trashSelected()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.resolveRunning)
            }
        }
        .padding(20)
        .frame(width: 720, height: 480)
    }
}
