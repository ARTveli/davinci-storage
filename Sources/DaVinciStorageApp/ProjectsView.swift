import SwiftUI
import StorageCore

/// Flat, sortable view of a project row.
struct RowVM: Identifiable {
    let row: ProjectRow
    var id: String { row.id }
    var name: String { row.project.name }
    var library: String { row.project.library }
    var date: Date { row.project.lastModified }
    var cache: Int64 { row.bytes[.cache] ?? 0 }
    var backups: Int64 { row.bytes[.backups] ?? 0 }
    var stills: Int64 { row.bytes[.stills] ?? 0 }
    var mask: Int64 { row.bytes[.magicMask] ?? 0 }
    var proxy: Int64 { row.bytes[.proxy] ?? 0 }
    var total: Int64 { row.total }
}

struct ProjectsView: View {
    @EnvironmentObject var model: AppModel
    let report: Report
    @StateObject private var sortOrder = Box([KeyPathComparator(\RowVM.total, order: .reverse)])
    @StateObject private var focused = Box<String?>(nil)
    @StateObject private var onlyOld = Box(false)

    private var rows: [RowVM] {
        report.rows.map(RowVM.init).filter { !onlyOld.value || model.isOld($0.row.project) }.sorted(using: sortOrder.value)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Stepper("старші за \(model.months) міс.", value: $model.months, in: 1...36)
                Toggle("показувати лише старі", isOn: $onlyOld.value)
                Button("Позначити старі") { model.selectOld() }
                Spacer()
            }
            .padding(10)

            Table(rows, selection: $focused.value, sortOrder: $sortOrder.value) {
                TableColumn("") { (vm: RowVM) in
                    Toggle("", isOn: Binding(get: { model.isSelected(vm.row.items) },
                                             set: { model.setSelected(vm.row.items, $0) }))
                        .labelsHidden()
                        .disabled(vm.row.items.isEmpty)
                }
                .width(24)
                TableColumn("Назва", value: \.name) { (vm: RowVM) in
                    HStack(spacing: 4) {
                        Text(vm.name).fontWeight(model.isOld(vm.row.project) ? .regular : .semibold)
                        if vm.row.items.contains(where: { $0.match == .byName }) {
                            Text("неточно").font(.caption2).padding(.horizontal, 4)
                                .background(Capsule().fill(Color.yellow.opacity(0.35)))
                        }
                    }
                }
                .width(min: 150, ideal: 185)
                TableColumn("Бібліотека", value: \.library).width(min: 70, ideal: 105)
                TableColumn("Остання зміна", value: \.date) { (vm: RowVM) in
                    Text(vm.date, format: .dateTime.day(.twoDigits).month(.twoDigits).year())
                        .foregroundStyle(model.isOld(vm.row.project) ? .secondary : .primary)
                }
                .width(min: 76, ideal: 84)
                TableColumn("Кеш", value: \.cache) { (vm: RowVM) in SizeText(vm.cache) }.width(min: 64, ideal: 78)
                TableColumn("Бекапи", value: \.backups) { (vm: RowVM) in SizeText(vm.backups) }.width(min: 64, ideal: 78)
                TableColumn("Стіли", value: \.stills) { (vm: RowVM) in SizeText(vm.stills) }.width(min: 64, ideal: 78)
                TableColumn("Magic Mask", value: \.mask) { (vm: RowVM) in SizeText(vm.mask) }.width(min: 64, ideal: 78)
                TableColumn("Проксі", value: \.proxy) { (vm: RowVM) in SizeText(vm.proxy) }.width(min: 64, ideal: 78)
                TableColumn("Разом", value: \.total) { (vm: RowVM) in SizeText(vm.total).fontWeight(.semibold) }.width(min: 72, ideal: 84)
            }

            if let id = focused.value, let row = report.rows.first(where: { $0.id == id }) {
                Divider()
                ItemList(title: "\(row.project.name) — що лежить на диску", items: row.items)
                    .frame(height: 190)
            }
        }
    }
}

struct SizeText: View {
    let bytes: Int64
    init(_ bytes: Int64) { self.bytes = bytes }
    var body: some View {
        Text(formatBytes(bytes)).monospacedDigit()
            .foregroundStyle(bytes == 0 ? .tertiary : .primary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Per-item checkboxes with path, size and how the item was linked.
struct ItemList: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let items: [StorageItem]

    var body: some View {
        List {
            Section(title) {
                if items.isEmpty { Text("Нічого не знайдено").foregroundStyle(.secondary) }
                ForEach(items, id: \.url) { it in
                    HStack(alignment: .firstTextBaseline) {
                        Toggle("", isOn: Binding(get: { model.selected.contains(it.url) },
                                                 set: { model.setSelected([it], $0) }))
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(it.category.title) · \(it.match.explanation)")
                                .font(.caption).foregroundStyle(it.match == .byName ? .orange : .secondary)
                            Text(it.url.path).font(.callout).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                            let shared = model.sharedWith(it)
                            if !shared.isEmpty {
                                Text("Спільне для: \(shared.joined(separator: ", "))").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        SizeText(it.bytes).frame(width: 90)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([it.url]) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .help("Показати у Finder")
                    }
                }
            }
        }
    }
}
