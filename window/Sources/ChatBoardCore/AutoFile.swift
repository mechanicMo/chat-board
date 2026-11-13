import Foundation

// Files chats into sections and project groups from their titles, so related tasks sit together without anyone
// sorting them. Runs on every refresh and is idempotent: a layout already up to date comes back unchanged.
//
// - A new chat (or one renamed since it was filed) goes to the top of the group its project matches, else the top of
//   its tag's section, else the top of the board.
// - Loose chats in one place that share a project form a group, once there are two of them.
// - A group made this way dissolves back into loose chats when fewer than two of its chats are open. A group the
//   person made or changed stays until none of its chats are open.
// - Chats the person moved by hand are never moved again.
public enum AutoFile {
    public static func update(_ start: BoardLayout, chats: [Chat], priorOrder: [String] = []) -> BoardLayout {
        var layout = start
        let localIds = Set(chats.map(\.localId))
        // Side sessions are drawn under their parent, so only chats without an open parent are filed.
        let roots = chats.filter { chat in
            guard let parent = chat.parentLocalId else { return true }
            return parent == chat.localId || !localIds.contains(parent)
        }
        let present = Set(roots.map(\.id))

        // A renamed chat that was auto-filed is filed again, but only when its tag or project changed. Titles change
        // with every new task, and a new task in the same project must not make the chat jump.
        for chat in roots where !layout.manual.contains(chat.id) {
            guard let filed = layout.filedAs[chat.id], filed != chat.title else { continue }
            if place(TitleParse.parse(filed)) != place(TitleParse.parse(chat.title)) {
                layout.remove(.chat(chat.id))
            } else {
                layout.filedAs[chat.id] = chat.title
            }
        }

        // New chats go on top, so they are placed last-first to keep their order.
        let placed = layout.placedChats
        let rank = Dictionary(priorOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let unplaced = roots.filter { !placed.contains($0.id) }.sorted { a, b in
            switch (rank[a.id], rank[b.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.activeAt > b.activeAt
            }
        }
        for chat in unplaced.reversed() {
            layout.insert(.chat(chat.id), into: home(for: chat, in: &layout), at: 0)
            layout.filedAs[chat.id] = chat.title
        }
        for chat in roots where layout.filedAs[chat.id] == nil && !layout.manual.contains(chat.id) {
            layout.filedAs[chat.id] = chat.title
        }

        let titles = Dictionary(roots.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        formGroups(&layout, titles: titles)
        dissolveGroups(&layout, present: present)
        return layout
    }

    // The part of a title that decides where a chat is filed.
    static func place(_ parsed: ParsedTitle) -> [String?] {
        [parsed.tag.map(TitleParse.key), parsed.project.map(TitleParse.key)]
    }

    // Where a newly filed chat goes: a matching group, else its tag's section (made if missing), else the top.
    static func home(for chat: Chat, in layout: inout BoardLayout) -> Container {
        let parsed = TitleParse.parse(chat.title)
        let sectionId = parsed.tag.map(TitleParse.key)
        if let group = matchGroup(parsed.project, folder: chat.folder, preferring: sectionId, in: layout) {
            return .group(group)
        }
        guard let tag = parsed.tag, let sectionId else { return .top }
        if layout.sections[sectionId] == nil {
            layout.sections[sectionId] = TagSection(id: sectionId, name: tag)
        }
        if !layout.top.contains(.section(sectionId)) { layout.top.insert(.section(sectionId), at: 0) }
        return .section(sectionId)
    }

    // True when `short` is `long` or its first word or words: "orchard" covers "orchard games".
    static func covers(_ short: String, _ long: String) -> Bool {
        long == short || long.hasPrefix(short + " ")
    }

    // A group that is on the board and whose name matches the project, then one the project extends, then one named
    // like the chat's folder. Groups in the chat's own section win a tie.
    static func matchGroup(_ project: String?, folder: String, preferring section: String?, in layout: BoardLayout) -> String? {
        let shown = layout.groups.values.filter { layout.container(of: .group($0.id)) != nil }
        let ordered = shown.sorted { a, b in
            let inA = section.map { layout.container(of: .group(a.id)) == .section($0) } ?? false
            let inB = section.map { layout.container(of: .group(b.id)) == .section($0) } ?? false
            return inA && !inB || (inA == inB && a.id < b.id)
        }
        let key = project.map(TitleParse.key)
        if let key {
            if let exact = ordered.first(where: { TitleParse.key($0.name) == key }) { return exact.id }
            if let extended = ordered.first(where: { covers(TitleParse.key($0.name), key) }) { return extended.id }
        }
        let folderKey = TitleParse.key(folder)
        if !folderKey.isEmpty, let byFolder = ordered.first(where: { TitleParse.key($0.name) == folderKey }) {
            return byFolder.id
        }
        return nil
    }

    // In the top level and in each section, loose chats filed automatically that share a project become a group,
    // placed where the highest of them was and named the way that chat spells the project.
    static func formGroups(_ layout: inout BoardLayout, titles: [String: String]) {
        let containers: [Container] = [.top] + layout.sections.keys.sorted().map { .section($0) }
        for container in containers {
            var clusters: [(key: String, name: String, chats: [String])] = []
            for node in layout.items(in: container) {
                guard case .chat(let id) = node, !layout.manual.contains(id), let title = titles[id],
                      let project = TitleParse.parse(title).project else { continue }
                let key = TitleParse.key(project)
                if let index = clusters.firstIndex(where: { covers($0.key, key) || covers(key, $0.key) }) {
                    clusters[index].chats.append(id)
                    if key.count < clusters[index].key.count { clusters[index].key = key; clusters[index].name = project }
                } else {
                    clusters.append((key, project, [id]))
                }
            }
            for cluster in clusters where cluster.chats.count >= 2 {
                let id = "g-" + UUID().uuidString.lowercased()
                layout.insert(.group(id), into: container, before: .chat(cluster.chats[0]))
                // Removing a chat also takes it out of every group, so the group is filled only after.
                for chat in cluster.chats { layout.remove(.chat(chat)) }
                layout.groups[id] = ProjectGroup(id: id, name: cluster.name, chats: cluster.chats)
            }
        }
    }

    // Auto groups with fewer than two open chats break up in place; groups made by hand go once none are open.
    static func dissolveGroups(_ layout: inout BoardLayout, present: Set<String>) {
        for group in layout.groups.values {
            let open = group.chats.filter(present.contains).count
            if group.isManual ? open > 0 : open >= 2 { continue }
            let where_ = layout.container(of: .group(group.id))
            if let where_, !group.isManual {
                for chat in group.chats { layout.insert(.chat(chat), into: where_, before: .group(group.id)) }
            }
            layout.remove(.group(group.id))
            layout.groups[group.id] = nil
        }
    }
}
