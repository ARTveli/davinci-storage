import SwiftUI
import StorageCore

struct LeftoversView: View {
    @EnvironmentObject var model: AppModel
    let report: Report

    var body: some View {
        List {
            if report.deleted.isEmpty && report.duplicates.isEmpty {
                Text("Залишків видалених проєктів і дублів не знайдено 🎉").foregroundStyle(.secondary)
            }
            if !report.duplicates.isEmpty {
                Section("Дублі") { ForEach(report.duplicates) { GroupRow(group: $0) } }
            }
            if !report.deleted.isEmpty {
                Section("Видалені проєкти") { ForEach(report.deleted) { GroupRow(group: $0) } }
            }
        }
    }
}

struct GroupRow: View {
    @EnvironmentObject var model: AppModel
    let group: LeftoverGroup
    @StateObject private var expanded = Box(false)

    private var inexact: Bool { group.uncertain || group.items.contains { $0.match == .byName } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: Binding(get: { model.isSelected(group.items) },
                                         set: { model.setSelected(group.items, $0) }))
                    .labelsHidden()
                Text(group.title).font(.headline)
                if inexact {
                    Text("неточно").font(.caption2).padding(.horizontal, 4)
                        .background(Capsule().fill(Color.yellow.opacity(0.35)))
                }
                Spacer()
                SizeText(group.total).frame(width: 100)
                Button(expanded.value ? "Сховати" : "Деталі") { expanded.value.toggle() }.buttonStyle(.borderless)
            }
            Text(group.reason).font(.caption).foregroundStyle(.secondary).padding(.leading, 26)
            if expanded.value {
                ForEach(group.items, id: \.url) { it in
                    HStack {
                        Text("\(it.category.title): \(it.url.path)").font(.caption).textSelection(.enabled)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        SizeText(it.bytes).frame(width: 90).font(.caption)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([it.url]) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.leading, 26)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
