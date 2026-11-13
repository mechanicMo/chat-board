"""Writes made-up chats for Chat Board screenshots. Nothing here is a real chat, person or business.

    python3 demo/make-demo.py <folder>
    CHAT_BOARD_DEMO=<folder> ChatBoard --snapshot out.png --width 420
"""
import json, os, sys, time

root = sys.argv[1]
now = time.time() * 1000
min_ = 60 * 1000

# (title, kind, line, minutes since it finished, unread, parent index, focused rank)
# Titles follow `[tag] project - task`, so the board groups them into sections and project cards.
chats = [
    ("[client] bakery site - fix the menu page", "question",
     "Should the seasonal menu replace the regular one, or sit above it?", 2, True, None, 0),
    ("[client] bakery site - compress the photos", "ready",
     "Photos shrunk from 48 MB to 6 MB and the page loads in under a second.", 9, True, 0, 0),
    ("[client] dog groomer - add booking reminders", "working", "", 0, False, None, 0),
    ("[biz] blog - draft the launch post", "your_move",
     "Left: you pick which of the two openings to keep.", 14, True, None, 0),
    ("[side] recipe app - add search", "question",
     "Should search match ingredients too, or only titles?", 21, False, None, 0),
    ("[client] yoga studio - class schedule bug", "ready",
     "Fixed the Sunday classes showing on Monday and checked it on a phone.", 33, False, None, 0),
    ("[life] garage - plan the shelving", "your_move",
     "Left: you measure the back wall so I can size the shelves.", 47, False, None, 0),
    ("[biz] website - new pricing page", "working", "", 0, False, None, 0),
    ("[client] dog groomer - test the reminder texts", "ready",
     "All three reminder texts sent to the test phone on time.", 58, False, 2, 0),
    ("[side] recipe app - import from a link", "your_move",
     "Left: you pick which two sites to support first.", 66, False, None, 0),
    ("[side] recipe app - shopping list", "working", "", 0, False, None, 0),
    ("[side] recipe app - meal plan export", "ready",
     "Exports a week of meals to a printable PDF.", 72, False, None, 0),
    # The chat open beside the board, drawn as the highlighted current chat.
    ("[side] chat board - write the readme", "working", "", 0, False, None, 1),
]

records = os.path.join(root, "records", "demo")
rows = os.path.join(root, "share", "rows")
os.makedirs(records, exist_ok=True)
os.makedirs(rows, exist_ok=True)

for i, (title, kind, line, ago, unread, parent, focused) in enumerate(chats):
    local, cli = f"local_demo{i:02d}", f"demo-cli-{i:02d}"
    finished = now - ago * min_
    user_at = finished - 3 * min_
    record = {
        "sessionId": local, "cliSessionId": cli, "title": title, "isArchived": False,
        "cwd": "/Users/demo/projects", "lastActivityAt": finished,
        "lastTurnEdgeAt": finished,
        # Read chats were looked at after they finished; unread ones before.
        "lastFocusedAt": (now - 1000 if focused else min(now - 30_000, user_at if unread else finished + min_)),
    }
    if parent is not None:
        record["spawnedFrom"] = {"sessionId": f"local_demo{parent:02d}"}
    row = {"sessionId": cli, "localId": local, "userAt": user_at,
           "repliedAt": finished if kind != "working" else 0,
           "phase": "working" if kind == "working" else "idle"}
    if kind == "question":
        row["turnEnd"] = {"at": finished, "ask": line, "recap": ""}
    elif kind == "ready":
        row["verdict"] = {"at": finished, "isDone": True, "left": line}
    elif kind == "your_move":
        row["verdict"] = {"at": finished, "isDone": False, "left": line.removeprefix("Left: ")}
    json.dump(record, open(os.path.join(records, local + ".json"), "w"))
    json.dump(row, open(os.path.join(rows, cli + ".json"), "w"))

# The order the person dragged them into.
json.dump([f"demo-cli-{i:02d}" for i in (12, 0, 2, 3, 4, 7, 5, 6)], open(os.path.join(root, "share", "order.json"), "w"))
print("wrote", len(chats), "made-up chats to", root)
