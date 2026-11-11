import SwiftUI
import StorageCore

/// Byte-identical LUTs. Nothing is pre-selected; copies used by a project or a DCTL are locked.
struct LutView: View {
    @EnvironmentObject var model: AppModel
    let groups: [LutGroup]

    private var filtered: [LutGroup] {
        let q = model.search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? groups : groups.filter { $0.copies.contains { $0.relativePath.localizedCaseInsensitiveContains(q) } }
    }

    var body: some View {
        List {
            if !filtered.isEmpty {
                Section {
                    ForEach(filtered) { LutGroupRow(group: $0) }
                } footer: {
                    Text("Однакові за вмістом LUT. Проєкти й DCTL звертаються до LUT за шляхом, тому копії, які десь використовуються, заблоковані 🔒. Лиши хоча б одну копію в кожній групі.")
                }
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Пошук LUT")
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Дублів LUT не знайдено", systemImage: "checkmark.seal",
                                       description: Text("Кожен LUT у бібліотеці унікальний."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: model.search)
            }
        }
    }
}

struct LutGroupRow: View {
    @EnvironmentObject var model: AppModel
    let group: LutGroup

    /// Never allow selecting every copy of a group.
    private func canSelect(_ c: LutCopy) -> Bool {
        guard c.isSelectable else { return false }
        if model.selected.contains(c.url) { return true }
        let remaining = group.copies.filter { !model.selected.contains($0.url) }
        return remaining.count > 1
    }

    var body: some View {
        DisclosureGroup {
            ForEach(group.copies, id: \.url) { c in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Toggle("", isOn: Binding(get: { model.selected.contains(c.url) },
                                             set: { model.setSelected([c.storageItem], $0) }))
                        .labelsHidden()
                        .disabled(!canSelect(c))
                    VStack(alignment: .leading, spacing: 2) {
                        Text((c.relativePath as NSString).lastPathComponent).lineLimit(1)
                        Text((c.relativePath as NSString).deletingLastPathComponent)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        if !c.usedBy.isEmpty {
                            Label("використовується: \(c.usedBy.joined(separator: ", "))", systemImage: "lock.fill")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer()
                    SizeText(c.bytes).frame(width: 74)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([c.url]) } label: {
                        Image(systemName: "arrow.right.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Показати у Finder")
                }
                .padding(.vertical, 2)
            }
        } label: {
            HStack {
                Text((group.copies.first?.relativePath as NSString?)?.lastPathComponent ?? "LUT").font(.body.weight(.medium))
                Text("\(group.copies.count) копії").foregroundStyle(.secondary)
                if group.copies.allSatisfy({ !$0.isSelectable }) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).help("Усі копії використовуються")
                }
                Spacer()
                Text("зайве \(formatBytes(group.wasted))").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

/// "1 файл", "3 файли", "5 файлів".
func uaFiles(_ n: Int) -> String {
    let mod10 = n % 10, mod100 = n % 100
    let word = (mod10 == 1 && mod100 != 11) ? "файл"
        : ((2...4).contains(mod10) && !(12...14).contains(mod100)) ? "файли" : "файлів"
    return "\(n) \(word)"
}
