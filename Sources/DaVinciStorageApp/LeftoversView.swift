import SwiftUI
import StorageCore

struct LeftoversView: View {
    @EnvironmentObject var model: AppModel
    let report: Report

    private func matches(_ g: LeftoverGroup) -> Bool {
        let q = model.search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || g.title.localizedCaseInsensitiveContains(q)
    }

    var body: some View {
        let dups = report.duplicates.filter(matches)
        let deleted = report.deleted.filter(matches)
        List {
            if !dups.isEmpty {
                Section {
                    ForEach(dups) { GroupRow(group: $0) }
                } header: {
                    Text("Дублі")
                } footer: {
                    Text("Копії папок, які вже є в іншому місці. Оригінал, яким користується проєкт, не чіпаємо.")
                }
            }
            if !deleted.isEmpty {
                Section {
                    ForEach(deleted) { GroupRow(group: $0) }
                } header: {
                    Text("Видалені проєкти")
                } footer: {
                    Text("Файли, для яких немає проєкту в жодній базі DaVinci.")
                }
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Пошук")
        .overlay {
            if report.deleted.isEmpty && report.duplicates.isEmpty {
                ContentUnavailableView("Залишків не знайдено", systemImage: "checkmark.seal",
                                       description: Text("Усе на диску належить наявним проєктам."))
            } else if dups.isEmpty && deleted.isEmpty {
                ContentUnavailableView.search(text: model.search)
            }
        }
    }
}

struct GroupRow: View {
    @EnvironmentObject var model: AppModel
    let group: LeftoverGroup

    private var inexact: Bool { group.uncertain || group.items.contains { $0.match == .byName } }

    var body: some View {
        DisclosureGroup {
            ForEach(group.items, id: \.url) { ItemRow(item: $0) }
        } label: {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(get: { model.isSelected(group.items) },
                                         set: { model.setSelected(group.items, $0) }))
                    .labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(group.title).font(.body.weight(.medium))
                        if inexact {
                            Label("неточно", systemImage: "exclamationmark.triangle")
                                .labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text(group.reason).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                SizeText(group.total).frame(width: 90)
            }
        }
        .padding(.vertical, 2)
    }
}
