import Foundation

public func formatBytes(_ bytes: Int64) -> String {
    bytes == 0 ? "—" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

public extension Category {
    var title: String {
        switch self {
        case .cache: "Кеш"
        case .backups: "Бекапи"
        case .stills: "Стіли"
        case .magicMask: "Magic Mask"
        case .proxy: "Проксі"
        case .service: "Службове"
        }
    }
}

/// Plain-text report for the terminal.
public func renderReport(_ r: Report) -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    let cats: [Category] = [.cache, .backups, .stills, .magicMask, .proxy]
    func pad(_ s: String, _ n: Int) -> String { s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count) }
    func lpad(_ s: String, _ n: Int) -> String { s.count >= n ? s : String(repeating: " ", count: n - s.count) + s }

    var out = "DaVinci Storage — всього: \(formatBytes(r.grandTotal))\n"
    if !r.unreadable.isEmpty {
        out += "\n⚠️  Не вдалося прочитати проєкти (видалене може бути неточним):\n"
        for u in r.unreadable { out += "   \(u.path)\n" }
    }

    out += "\n== Проєкти ==\n"
    out += pad("Назва", 30) + pad("База", 22) + pad("Змінено", 12) + cats.map { lpad($0.title, 11) }.joined() + lpad("Разом", 11) + "\n"
    for row in r.rows {
        out += pad(row.project.name, 30) + pad(row.project.library, 22) + pad(df.string(from: row.project.lastModified), 12)
        out += cats.map { lpad(row.bytes[$0].map(formatBytes) ?? "—", 11) }.joined()
        out += lpad(formatBytes(row.total), 11) + "\n"
    }

    out += "\n== Видалені проєкти і дублі ==\n"
    for g in r.duplicates + r.deleted {
        out += "\(g.title) — \(formatBytes(g.total))\(g.uncertain ? " (неточно)" : "")\n   \(g.reason)\n"
        for it in g.items { out += "   · \(it.category.title): \(it.url.path) (\(formatBytes(it.bytes)))\n" }
    }

    out += "\n== Службові кеші ==\n"
    for it in r.service { out += "\(it.label) — \(formatBytes(it.bytes))  \(it.url.path)\n" }
    return out
}
