// Shared by the mod tests (hooks/) and Chat Board tests (window/). The part after `export default` is plain JSON,
// so the Swift tests read it too. Both describe() functions must give these answers.
export default {
  "note": "Shared by the mod's tests (hooks/) and the window's tests (window/). Both describe() functions must give these answers, so the band and the board never disagree. Times are in ms.",
  "now": 1000000000,
  "cases": [
    {"name": "a running turn is working", "row": {"phase": "working", "userAt": 999990000}, "kind": "working", "line": "Working on your message"},
    {"name": "a question in the end-of-turn box", "row": {"phase": "idle", "userAt": 999000000, "turnEnd": {"ask": "Which fix first?", "recap": "Two fixes ready.", "at": 999500000}}, "kind": "question", "line": "Which fix first?"},
    {"name": "the box question beats a done verdict", "row": {"phase": "idle", "userAt": 999000000, "turnEnd": {"ask": "Ship it?", "recap": null, "at": 999500000}, "verdict": {"isDone": true, "left": "All done.", "purpose": "p", "at": 999500000}}, "kind": "question", "line": "Ship it?"},
    {"name": "a question written at the end of the reply", "row": {"phase": "idle", "userAt": 999000000, "textQuestion": {"text": "Want me to keep going?", "at": 999500000}}, "kind": "question", "line": "Want me to keep going?"},
    {"name": "done verdict", "row": {"phase": "idle", "userAt": 999000000, "verdict": {"isDone": true, "left": "The fix is merged.", "purpose": "p", "at": 999500000}}, "kind": "ready", "line": "The fix is merged."},
    {"name": "not-done verdict", "row": {"phase": "idle", "userAt": 999000000, "verdict": {"isDone": false, "left": "You review the draft.", "purpose": "p", "at": 999500000}}, "kind": "your_move", "line": "Left: You review the draft."},
    {"name": "a verdict older than your last message is ignored", "row": {"phase": "idle", "userAt": 999600000, "verdict": {"isDone": true, "left": "Old.", "purpose": "p", "at": 999500000}, "turnEnd": {"ask": null, "recap": "New recap.", "at": 999700000}}, "kind": "your_move", "line": "New recap."},
    {"name": "recap only", "row": {"phase": "idle", "userAt": 999000000, "turnEnd": {"ask": null, "recap": "Tests pass.", "at": 999500000}}, "kind": "your_move", "line": "Tests pass."},
    {"name": "a rename card waiting over 3 seconds", "row": {"phase": "working", "userAt": 999000000, "pending": {"tool": "mcp__ccd_session_mgmt__set_session_title", "at": 999995000, "asked": false}}, "kind": "question", "line": "Waiting for your OK: rename this chat"},
    {"name": "a rename card under 3 seconds is still working", "row": {"phase": "working", "userAt": 999000000, "pending": {"tool": "mcp__ccd_session_mgmt__set_session_title", "at": 999999000, "asked": false}}, "kind": "working", "line": "Working on your message"},
    {"name": "a long shell command is just working", "row": {"phase": "working", "userAt": 999000000, "pending": {"tool": "Bash", "at": 999900000, "asked": false}}, "kind": "working", "line": "Working on your message"},
    {"name": "a shell command the permission check put to you", "row": {"phase": "working", "userAt": 999000000, "pending": {"tool": "Bash", "at": 999999500, "asked": true}}, "kind": "question", "line": "Waiting for your OK: Bash"},
    {"name": "a quick tool stuck over 20 seconds", "row": {"phase": "working", "userAt": 999000000, "pending": {"tool": "mcp__notes__save_note", "at": 999970000, "asked": false}}, "kind": "question", "line": "Waiting for your OK: save note"},
    {"name": "a quick tool under 20 seconds", "row": {"phase": "working", "userAt": 999000000, "pending": {"tool": "mcp__notes__save_note", "at": 999990000, "asked": false}}, "kind": "working", "line": "Working on your message"}
  ]
}
