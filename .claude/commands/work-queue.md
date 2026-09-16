---
description: Implement the next unchecked item(s) in roadmap.md, committing each as you go
argument-hint: [count]
---

Read `roadmap.md`. Take the first unchecked item (`- [ ]`).

1. Implement only that item — nothing else, no adjacent cleanup, no scope creep.
2. Verify before committing, based on the item's exact type word:
   - `*feat*` (asterisks): a headless boot (`godot --headless --path . --quit-after N`) to catch script errors, plus — if the change is visual — a real screenshot, since headless renders no actual pixels. For the screenshot, launch Godot normally (windowed, not headless) with a temporary debug hook that waits ~60 frames then calls `get_viewport().get_texture().get_image().save_png(...)`, then look at the PNG; remove the hook after.
   - plain `feat` or `fix` (no asterisks): a headless boot only — no screenshot.
   - anything else (`chore`, `refactor`, `ui`, etc.): skip verification entirely.
3. If the item required a code change, commit it: type prefix (drop any asterisks), one short line describing what was actually done — not the task's raw wording if it was a question ("check if...") or a bug report, and no added rationale beyond the prefix + line. E.g. "light gray text doesn't read well" → `fix: darken light gray text`. Check the box in `roadmap.md` and fold that into the same commit.
4. If the item was pure investigation with no code change (e.g. "confirmed nothing needed removing"), just check the box — don't create a commit for it. Leave it staged/uncommitted; it'll ride along with the next real commit, or stay as a harmless pending change if this was the last item.

$ARGUMENTS: none = one item, then stop. A number N = the next N items, each committed separately. Stop early and report back if an item needs a decision only the user can make — don't guess.
