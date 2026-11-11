import SwiftUI
import StorageCore

/// Flat, sortable view of a project row.
struct RowVM: Identifiable {
    let row: ProjectRow
    var id: String { row.id + "|" + row.project.library }
    var name: String { row.project.name }
    var library: String { row.project.library }
    var date: Date { row.project.lastModified }
    var cache: Int64 { row.bytes[.cache] ?? 0 }
    var backups: Int64 { row.bytes[.backups] ?? 0 }
    var stills: Int64 { row.bytes[.stills] ?? 0 }
    var mask: Int64 { row.bytes[.magicMask] ?? 0 }
    var proxy: Int64 { row.bytes[.proxy] ?? 0 }
    var total: Int64 { row.total }
    var inexact: Bool { row.items.contains { $0.match == .byName } }
}

struct ProjectsView: View {
    @EnvironmentObject var model: AppModel
    let report: Report
    @StateObject private var sortOrder = Box([KeyPathComparator(\RowVM.total, order: .reverse)])

    private var rows: [RowVM] {
        let q = model.search.trimmingCharacters(in: .whitespaces)
        return report.rows.map(RowVM.init)
            .filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
            .sorted(using: sortOrder.value)
    }

    var body: some View {
        Table(rows, selection: $model.focusedProject, sortOrder: $sortOrder.value) {
            TableColumn("") { (vm: RowVM) in
                Toggle("", isOn: Binding(get: { model.isSelected(vm.row.items) },
                                         set: { model.setSelected(vm.row.items, $0) }))
                    .labelsHidden()
                    .disabled(vm.row.items.isEmpty)
                    .help("Позначити все цього проєкту")
            }
            .width(22)
            TableColumn("Назва", value: \.name) { (vm: RowVM) in
                HStack(spacing: 5) {
                    Text(vm.name)
                        .foregroundStyle(model.isOld(vm.row.project) ? .secondary : .primary)
                    if vm.inexact {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help("Частину файлів прив'язано лише за назвою папки — неточно")
                            .accessibilityLabel("неточно")
                    }
                }
            }
            .width(min: 150, ideal: 200)
            TableColumn("Бібліотека", value: \.library) { (vm: RowVM) in
                Text(vm.library).foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 110)
            TableColumn("Змінено", value: \.date) { (vm: RowVM) in
                Text(vm.date, format: .dateTime.day(.twoDigits).month(.twoDigits).year())
                    .monospacedDigit()
                    .foregroundStyle(model.isOld(vm.row.project) ? .secondary : .primary)
            }
            .width(min: 76, ideal: 84)
            TableColumn("Кеш", value: \.cache) { (vm: RowVM) in SizeText(vm.cache) }.width(min: 64, ideal: 78)
            TableColumn("Бекапи", value: \.backups) { (vm: RowVM) in SizeText(vm.backups) }.width(min: 64, ideal: 78)
            TableColumn("Стіли", value: \.stills) { (vm: RowVM) in SizeText(vm.stills) }.width(min: 64, ideal: 78)
            TableColumn("Magic Mask", value: \.mask) { (vm: RowVM) in SizeText(vm.mask) }.width(min: 70, ideal: 84)
            TableColumn("Проксі", value: \.proxy) { (vm: RowVM) in SizeText(vm.proxy) }.width(min: 64, ideal: 78)
            TableColumn("Разом", value: \.total) { (vm: RowVM) in SizeText(vm.total).fontWeight(.semibold) }.width(min: 72, ideal: 84)
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Пошук проєкту")
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView.search(text: model.search)
            }
        }
        .inspector(isPresented: $model.inspectorShown) {
            ProjectInspector(row: report.rows.first { RowVM(row: $0).id == model.focusedProject })
                .inspectorColumnWidth(min: 300, ideal: 360, max: 520)
        }
    }
}

struct ProjectInspector: View {
    @EnvironmentObject var model: AppModel
    let row: ProjectRow?

    var body: some View {
        if let row {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.project.name).font(.title3.weight(.semibold)).textSelection(.enabled)
                        LabeledContent("Бібліотека", value: row.project.library)
                        LabeledContent("Остання зміна") {
                            Text(row.project.lastModified, format: .dateTime.day().month(.wide).year())
                        }
                        LabeledContent("Разом на диску") { Text(formatBytes(row.total)).monospacedDigit() }
                    }
                    .padding(.vertical, 4)
                }
                ForEach(Category.allCases.filter { c in row.items.contains { $0.category == c } }, id: \.self) { c in
                    Section(c.title) {
                        ForEach(row.items.filter { $0.category == c }, id: \.url) { ItemRow(item: $0) }
                    }
                }
                if row.items.isEmpty {
                    Text("На диску нічого не знайдено").foregroundStyle(.secondary)
                }
            }
        } else {
            ContentUnavailableView("Вибери проєкт", systemImage: "sidebar.trailing",
                                   description: Text("Тут з'являться його файли на диску."))
        }
    }
}

/// One file or folder: checkbox, how it was linked, path, size, Reveal in Finder.
struct ItemRow: View {
    @EnvironmentObject var model: AppModel
    let item: StorageItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle("", isOn: Binding(get: { model.selected.contains(item.url) },
                                     set: { model.setSelected([item], $0) }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(item.url.deletingLastPathComponent().path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    .help(item.url.path)
                Label(item.match.explanation, systemImage: item.match == .byName ? "exclamationmark.triangle" : "link")
                    .font(.caption2)
                    .foregroundStyle(item.match == .byName ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                let shared = model.sharedWith(item)
                if !shared.isEmpty {
                    Label("Також використовує: \(shared.joined(separator: ", "))", systemImage: "person.2")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 4)
            SizeText(item.bytes).frame(width: 74)
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .help("Показати у Finder")
        }
        .padding(.vertical, 2)
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
