# Project groups, phase 1: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group the board's chats into tag sections and project cards, auto-filed from titles, with a
project page you drill into.

**Architecture:**
- **Decisions in pure `ChatBoardCore` code**, each tested on its own:
  - title parsing;
  - a layout value type;
  - auto-filing;
  - moves;
  - the derived view tree.
- **The app owns one file, `layout.json`.** It writes it and migrates it once from `order.json`, which it then
  leaves untouched.
- **The SwiftUI views only draw** the tree that Core derives.
- **Clicks keep going through `ClickThroughPanel` → `BoardModel.click(at:)`**, now hit-testing cards, section
  headers and the pinned header as well as rows.

**Tech stack:** Swift 5.9, SwiftUI, macOS 14, Swift Testing (run via `window/scripts/test.sh`).

**Spec:** `docs/superpowers/specs/2026-11-13-project-groups-design.md`

## Global constraints

- The repo is public, so it holds made-up names only: in tests, demo data and comments.
- No model calls. The board stays free to run.
- The mod (`hooks/`) is untouched.
- Every new clickable reports its frame for first-click handling, and has no SwiftUI tap gesture or Button.
- Never leave `order.json` stale for the e2e tests in a way that breaks them. Update the e2e test in the same
  task that changes the behavior.

## File map

| File | Responsibility |
|---|---|
| `window/Sources/ChatBoardCore/TitleParse.swift` (new) | title → tag, project, task; normalized keys |
| `window/Sources/ChatBoardCore/Layout.swift` (new) | `Node`, `Container`, `Section`, `Group`, `Layout`, with Codable and lookups |
| `window/Sources/ChatBoardCore/AutoFile.swift` (new) | placing new or renamed chats, forming and dissolving groups |
| `window/Sources/ChatBoardCore/Moves.swift` (new) | move, make group, rename, ungroup, collapse |
| `window/Sources/ChatBoardCore/Tree.swift` (new) | layout + chats → what to draw, rollups, project page buckets |
| `window/Sources/ChatBoardCore/Chat.swift` | add `folder` (last path part of the cwd) |
| `window/Sources/ChatBoard/BoardModel.swift` | load and save `layout.json`, run AutoFile on reload, expose the tree, add `openProject` / `goHome` / moves |
| `window/Sources/ChatBoard/GroupViews.swift` (new) | section header, group card, project page header, Move to menu |
| `window/Sources/ChatBoard/ChatBoard.swift` | `BoardView` renders the tree; the frame tint; snapshot `--project` |
| `window/Tests/ChatBoardCoreTests/{TitleParse,Layout,AutoFile,Moves,Tree}Tests.swift` (new) | unit tests |
| `window/demo/make-demo.py` | more made-up chats sharing projects, plus a `layout.json` |
| `window/scripts/snapshot-check.sh` | also render the project page |
| `window/Sources/E2E/main.swift` | the order test reads `layout.json` |

## Interfaces (shared by every task)

```swift
public struct ParsedTitle: Equatable { public let tag: String?; public let project: String?; public let task: String }
public enum TitleParse {
    public static func parse(_ title: String) -> ParsedTitle
    public static func key(_ text: String) -> String          // lowercased, whitespace collapsed, trimmed
}
public enum Node: Hashable, Codable { case section(String), group(String), chat(String) }
public enum Container: Hashable { case top, section(String), group(String) }
public struct Section: Codable, Equatable { public var id, name: String; public var items: [Node]; public var collapsed: Bool }
public struct Group: Codable, Equatable { public var id, name: String; public var chats: [String]; public var isManual: Bool }
public struct Layout: Codable, Equatable {
    public var top: [Node]; public var sections: [String: Section]; public var groups: [String: Group]
    public var manual: Set<String>          // chats placed by hand
    public var filedAs: [String: String]    // chat id -> title it was auto-filed under
    public func container(of node: Node) -> Container?
}
public enum AutoFile { public static func update(_ layout: Layout, chats: [Chat], priorOrder: [String] = []) -> Layout }
public enum Moves {
    public static func move(_ layout: Layout, _ node: Node, to: Container, before: Node?) -> Layout
    public static func makeGroup(_ layout: Layout, dropping: String, onto: String, name: String) -> Layout
    public static func rename(_ layout: Layout, group: String, to: String) -> Layout
    public static func ungroup(_ layout: Layout, _ group: String) -> Layout
    public static func toggleCollapsed(_ layout: Layout, section: String) -> Layout
}
public enum Tree {
    public enum Entry: Equatable { case chat(Chat, children: [Chat]), group(Card) }
    public enum TopEntry: Equatable { case section(SectionBlock), entry(Entry) }
    public struct Card: Equatable { public let id, name: String; public let chats: [Chat]; public let counts: [Kind: Int]; public let lead: Chat? }
    public struct SectionBlock: Equatable { public let id, name: String; public let collapsed: Bool; public let entries: [Entry]; public let counts: [Kind: Int] }
    public static func build(_ layout: Layout, chats: [Chat]) -> [TopEntry]
    public static func page(_ card: Card) -> [(header: String, chats: [Chat])]   // Needs you / Ready to close / Working
}
```

## Tasks

### Task 1: TitleParse

Test cases, each written red first:
- `[work] orchard - pick characters` → work / orchard / pick characters
- `[work] orchard games -- memory match` → project `orchard games`; a double dash counts as the separator
- `[work] orchard - step 1 - then 2` → the task keeps its inner ` - `
- `Orchard: write parent guides` → no tag, project `orchard`
- `[work] just a note` (no separator) → tag work, no project
- `Untitled chat` → nothing
- `key("  Orchard   Games ")` → `orchard games`

Commit: `TitleParse: read tag, project and task from a chat title`.

### Task 2: Layout + Chat.folder

- Test that a `Layout` round-trips through JSON.
- Test `container(of:)` for a chat at the top level, in a section, and in a group.
- Add `folder` to `Chat`, filled in `chat(record:...)` from the last path part of `cwd`.

Commit: `Layout: sections, groups and loose chats as one value`.

### Task 3: AutoFile

Test cases:
1. A brand-new tagged chat goes to the top of its section, creating the section at the top when missing.
2. Two loose chats in a section sharing a project form a group at the upper one's spot, named as the upper
   one spells it.
3. A chat whose project extends a group's name (`orchard games`) joins `orchard`.
4. The colon form with no tag joins a matching group in any section.
5. A folder name matching a group joins it.
6. A chat in `manual` never moves, and never joins a forming group.
7. A rename of a chat not in `manual` re-files it.
8. An auto group with under 2 present chats dissolves into loose chats at its spot. A manual group with 1
   chat stays; with 0 it's removed.
9. Side sessions (a parent that is present) are never placed.
10. `priorOrder` keeps the old flat order when migrating.

Commit: `AutoFile: file chats into sections and project groups from their titles`.

### Task 4: Moves

Test cases:
- Reordering within a container.
- A chat into a group marks both the chat and the group manual.
- A section can only move in `.top`, and a group never goes inside a group.
- `makeGroup` puts a manual group where the target chat was.
- `ungroup` leaves the chats in place, marked manual.
- `rename` marks the group manual.
- `toggleCollapsed`.

Commit: `Moves: drag and menu actions on the layout`.

### Task 5: Tree

Test cases:
- Absent chats and empty sections are skipped.
- Children nest under their parent.
- `counts` per kind.
- `lead` is the first chat by question > your move > ready, and nil when all are working.
- `page` buckets by status and keeps the group's order.

Commit: `Tree: what the board draws, with per-card rollups`.

### Task 6: BoardModel wiring

- Load `layout.json`, and on first run migrate from the `order.json` order.
- Run `AutoFile` in `reload()`, save when the layout changes, and publish `tree`.
- Add `openProject(id)`, `goHome()`, `move(...)`, `menuTargets`.
- Move the drag state off of `chats` order.

Commit: `Board model: keep the layout file and the drill-in state`.

### Task 7: Views

Add `GroupViews.swift` with:
- `SectionHeader`: name, count, chevron and status bar.
- `GroupCard`.
- `ProjectHeader`: the banner with "← All chats", "N of M shown" and a purple dot when another group has a
  question; the breadcrumb; the title and status bar.
- The Move to submenu, Rename group and Ungroup in the context menus.

Then:
- `BoardView` renders the tree, or the project page inside a 2-point accent frame.
- Drag reorders within a container, using `Moves.move`.
- `click(at:)` dispatches on frame keys: `chat:<id>`, `group:<id>`, `section:<id>`, `home`.

Commit: `Board: tag sections, project cards and the project page`.

### Task 8: Demo, snapshot, e2e

- `make-demo.py` gets shared projects and a section order.
- The snapshot gets `--project`, and `snapshot-check.sh` renders both views and checks the colors.
- The e2e order test reads `layout.json`.
- Run `test.sh`, `snapshot-check.sh`, and then e2e on the Mini.

Commit: `Demo and checks for project groups`.

### Task 9: Install and look at it

- `build.sh`, then restart the app.
- Read the real board's `layout.json`, and look at it on screen.
- Report to Mo.
