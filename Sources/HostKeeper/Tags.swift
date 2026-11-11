import SSHConfigKit
import SwiftUI

enum Tags {
    private static let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .brown, .mint, .red]

    /// The same tag always gets the same color.
    static func color(_ tag: String) -> Color {
        let sum = tag.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }

    /// Every tag used on any host or key, sorted.
    @MainActor static var all: [String] {
        let keyTags = KeyStore.shared.keyTags.values.flatMap { $0 }
        return HostBlock.normalize(ConfigStore.shared.hosts.flatMap(\.tags) + keyTags)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// The sidebar filter. `#tag` words must all match a tag; other words must all appear somewhere.
struct SearchQuery {
    var tags: [String] = []
    var words: [String] = []

    init(_ text: String) {
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            if word.hasPrefix("#"), word.count > 1 { tags.append(String(word.dropFirst())) } else { words.append(word) }
        }
    }

    var isEmpty: Bool { tags.isEmpty && words.isEmpty }

    func matches(fields: [String], tags itemTags: [String]) -> Bool {
        let tagsOK = tags.allSatisfy { wanted in itemTags.contains { $0.caseInsensitiveCompare(wanted) == .orderedSame } }
        let haystack = (fields + itemTags).joined(separator: " ")
        return tagsOK && words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
    }
}

struct TagChip: View {
    let tag: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 3) {
            Text(tag).lineLimit(1)
            if let onRemove {
                Button("Remove \(tag)", systemImage: "xmark", action: onRemove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .imageScale(.small)
            }
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(Tags.color(tag))
        .background(Tags.color(tag).opacity(0.15), in: .capsule)
    }
}

/// A row of tag chips for sidebar rows.
struct TagLine: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 3) {
                ForEach(tags.prefix(4), id: \.self) { TagChip(tag: $0) }
                if tags.count > 4 { Text("+\(tags.count - 4)").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Chips with remove buttons, a field to type new tags, and a menu of tags already in use.
struct TagEditor: View {
    @Binding var tags: [String]
    @State private var draft = ""

    private var suggestions: [String] {
        Tags.all.filter { tag in !tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
    }

    var body: some View {
        LabeledContent("Tags") {
            VStack(alignment: .trailing, spacing: 6) {
                if !tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(tag: tag) { tags.removeAll { $0 == tag } }
                        }
                    }
                }
                HStack {
                    TextField("Add tag", text: $draft, prompt: Text("Type a tag and press Return"))
                        .onSubmit(add)
                    Menu("Existing") {
                        if suggestions.isEmpty { Text("No other tags yet") }
                        ForEach(suggestions, id: \.self) { tag in
                            Button(tag) { tags.append(tag) }
                        }
                    }
                    .fixedSize()
                }
            }
        }
    }

    /// Commas let you add several at once: "prod, web".
    private func add() {
        tags = HostBlock.normalize(tags + draft.split(separator: ",").map(String.init))
        draft = ""
    }
}

/// Lays children out left to right, wrapping onto new lines, aligned to the trailing edge.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.maxX - row.width
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
