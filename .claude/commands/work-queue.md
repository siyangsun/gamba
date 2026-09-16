---
description: Implement the next unchecked item(s) in roadmap.md, committing each as you go
argument-hint: [count]
---

Read `roadmap.md`. Take the first unchecked item (`- [ ]`).

1. Implement only that item — nothing else, no adjacent cleanup, no scope creep.
2. If its type is written `*feat*` (asterisks), verify before committing: headless boot (`godot --headless --path . --quit-after N`) for script errors, plus a screenshot from a temporary debug hook (remove it after) if the change is visual. Skip this for plain `feat`/`fix`/`chore`/`refactor`.
3. Commit with the type prefix (drop any asterisks) and a message describing what was actually done — not the task's raw wording if it was a question ("check if...") or a bug report. E.g. "light gray text doesn't read well" → `fix: darken light gray text for readability`.
4. Check the box in `roadmap.md` and commit that too (folding it into #3's commit is fine).

$ARGUMENTS: none = one item, then stop. A number N = the next N items, each committed separately. Stop early and report back if an item needs a decision only the user can make — don't guess.
