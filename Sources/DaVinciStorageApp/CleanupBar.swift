import SwiftUI
import StorageCore

/// Confirmation for the destructive action (HIG): specific title, consequences, every path listed,
/// Cancel is the default button; the destructive button is red and never default.
struct ConfirmSheet: View {
    @EnvironmentObject var model: AppModel

    private var items: [StorageItem] {
        model.selected.compactMap { model.itemsByURL[$0] }.sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 40)).symbolRenderingMode(.hierarchical).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Перемістити \(uaCount(items.count)) у Кошик?").font(.title3.weight(.semibold))
                    Text("Звільнить \(formatBytes(model.selectedBytes)). Спершу програма зробить бекап усіх баз у «\(model.settings.backupFolder.path)» і ще раз перевірить диск. Бази проєктів не змінюються, а все переміщене можна відновити з Кошика, доки ти його не очистиш.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            List(items, id: \.url) { it in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("\(it.category.title) · \(it.label)").font(.callout.weight(.medium))
                        Spacer()
                        SizeText(it.bytes).frame(width: 90)
                    }
                    Text(it.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .help(it.url.path)
                    let shared = model.sharedWith(it)
                    if !shared.isEmpty {
                        Label("Цю папку також використовує: \(shared.joined(separator: ", "))", systemImage: "person.2")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if model.uncertainURLs.contains(it.url) {
                        Label("Не доведено, що проєкт видалено — частину даних не вдалося прочитати",
                              systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                    if it.match == .byName {
                        Label("Прив'язано лише за назвою папки", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 240)
            HStack {
                Spacer()
                Button("Перемістити в Кошик", role: .destructive) {
                    model.confirming = false
                    model.trashSelected()
                }
                .foregroundStyle(.red)
                .disabled(model.resolveRunning)
                Button("Скасувати") { model.confirming = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 720, height: 500)
        .onExitCommand { model.confirming = false }
    }
}
