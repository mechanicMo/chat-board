# Project groups on the board - design

Date: 2026-11-13. Status: draft for review.

## Goal

Today the board is one flat list. With 15 to 20 chats open, the chats for one project (say five chats
about the same app) are scattered across it. This change groups chats by **tag** and **project**, read
straight from the chat titles, so related tasks sit together. Status stays visible at every level.

Names below are made up. Titles follow the rename rule `[tag] project - task`, for example
`[work] orchard - pick base characters`.

## The three levels

| Level | Comes from | Looks like |
|---|---|---|
| **Section** | the title's tag (`work`, `home`, `client`) | a header you can collapse and drag |
| **Group** | the title's project (`orchard`) | a card with a status bar |
| **Chat** | one task | today's row |

Chats with no tag sit **loose** at the top level, outside every section. A chat can also sit loose inside a
section when no group fits it.

## Home view

- Sections in your order. Each header shows its name, its chat count and a collapse chevron. A collapsed
  section still shows one status bar for everything inside it.
- Inside a section: group cards and loose chat rows, mixed, in your order.
- **A group card** shows:
  - the project name and its task count;
  - a status bar split purple / orange / green / gray, in proportion;
  - its most urgent chat's title and status line (a question beats your move beats ready; a card with
    only working chats shows no line).
- **Rollups on a card:** the card is bold when any chat in it is unread, and gets today's "current chat"
  highlight when the chat in front of you is inside it.
- Side sessions stay nested under their parent wherever the parent is, as today.

## Project page (drill-in)

Clicking a card replaces the list with that project.

- **Pinned header** (it never scrolls):
  - **Banner:** "← All chats" on the left and "N of M shown" on the right, on the accent tint. A purple dot
    next to "All chats" when a chat in any other group or section is asking you a question.
  - **Breadcrumb:** `All chats › work › orchard`. Every part except the last is clickable, and each goes home.
  - The project name in large type, with its status bar.
- **The whole board gets a 2-point accent frame** while a project page is open.
- **Tasks sit under status headers:** Needs you (question and your move), Ready to close, Working. Within
  each header the order is yours. When a chat's status changes, it moves to the new header and keeps its
  relative place there.
- **Clicking a chat opens it, and the board stays on the project page.** The board view never changes
  because of what you clicked.

## Auto-filing

The app reads every chat's title on each refresh (every 3 seconds, as today). Nothing calls a model.

**1. Parse the title.**

| Title | Tag | Project |
|---|---|---|
| `[work] orchard - pick characters` | work | orchard |
| `[work] orchard games - memory match` | work | orchard games |
| `Orchard: write parent guides` | none | orchard |
| `Untitled chat` | none | none |

- The project is matched in lowercase with spaces trimmed.
- Only the first ` - ` splits project from task, so a dash inside the task is safe.
- A chat in a private folder is never parsed and never written to the layout file.

**2. Match the project to a group.**

1. An exact name match wins.
2. Otherwise, an existing group whose name is the first word or words of the project. So `orchard games`
   joins `orchard`.
3. Otherwise, a group whose name equals the chat folder's last path part.

**3. Form groups.** When 2 or more chats outside groups share a project (side sessions don't count), a group
is created, named the way the first chat spelled it.

**4. Placement.** An auto-filed chat goes to the top of its group or section. A brand-new chat with no
title yet goes to the top of the board, as today.

**A drag always wins.** Once you move a chat by hand, auto-filing never moves it again: not after a rename,
an archive or an unarchive. This is stored per chat.

## Groups you make or change by hand

- **Make one:** drop a chat onto a loose chat. The group takes the target chat's project name, or "New group".
- **Rename a group:** right-click the card, then Rename group.
- **Ungroup:** right-click the card, then Ungroup. Its chats go loose in the same spot, and they count as
  placed by hand.
- **When groups disappear:**
  - an auto-made group dissolves when it drops below 2 chats;
  - a group you made, renamed or dragged anything into stays until it has 0 chats.

## Dragging

Every drag shows a drop line. Dropping onto a card shows the card highlighted.

| From | To | Result |
|---|---|---|
| a section header | between sections | reorders sections |
| a card or loose chat | another spot in its section | reorders |
| a card or loose chat | inside another section | moves it there; the title doesn't change |
| a loose chat | onto a card | joins that group |
| a loose chat | onto a loose chat | makes a new group |
| anything | above or below every section | sits loose at the top level |
| a chat on a project page | within its status header | reorders |
| a chat on a project page | held on the banner or breadcrumb for 0.5 s | the board flips home with the drag still live; drop anywhere above |

**Right-click → Move to ▸** lists every group, every section, and "Out of all groups". It is the reliable
backup for all of the above.

## Search

Cmd+F still searches every chat. It looks inside collapsed sections and groups too, and shows a flat result
list where each row reads "orchard · pick characters". Opening a result leaves the board view as it was.

## Architecture

- **The app does all of this. The mod doesn't change.** That way there's one writer, no races between open
  chats, and no `/reload-plugins` needed.
- **New pure functions in `ChatBoardCore`, each tested on its own:**
  - `TitleParse`: title → tag, project, task;
  - `Layout`: sections, groups, items and placed-by-hand flags, as values;
  - `AutoFile`: layout + chats → new layout;
  - `Moves`: one function per drag or menu action.
- **One new file, `~/.claude/chat-hud/layout.json`, written only by the app.** It replaces `order.json`. On
  first launch the app builds it from `order.json` and leaves `order.json` alone. Ids of closed chats stay in
  the file, so a chat that comes back keeps its place.
- **The panel is never the key window**, so every new clickable has to report its frame through
  `rowsInWindow` / `ControlFrames`, or it drops the first click. That covers cards, the banner, breadcrumb
  parts, section headers and chevrons.
- **Escape is not used to go back.** The board would have to take Escape from Claude.

## Testing

- **Unit tests per function**, using the real title shapes: the colon form, a project that extends a group
  name, a dash inside the task, case differences, side sessions, private folders.
- **Each test is proved red before its code is written.**
- **Demo data:**
  - `make-demo.py` gets tagged, made-up titles;
  - `snapshot-check.sh` renders the home view and a project page;
  - it checks that all four status colors are still drawn.
- **End-to-end:** update the `order` and `search` groups, and add:
  - first click on a card, the banner and a breadcrumb part;
  - drag a chat into a group;
  - hold on the banner to flip home with the drag still live;
  - Move to.

## Build order

1. **Phase 1:**
   - the title parser and the layout model;
   - auto-filing;
   - section headers, with collapse and drag;
   - cards and the project page, with the pinned header and frame;
   - Move to;
   - reordering within one level.
2. **Phase 2, the cross-level drags:**
   - dropping onto cards and loose chats;
   - holding on the header to flip home;
   - dragging out to the top level.

Phase 1 is usable on its own: everything can be moved through the menu.

## Out of scope

- Claude's own sidebar sections. The board doesn't read or write them.
- Any model call for grouping.
- Changing chat titles from the board.
