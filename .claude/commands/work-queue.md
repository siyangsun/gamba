---
description: Implement the next unchecked item(s) in work-queue.md, committing each as you go
argument-hint: [count]
---

Read `work-queue.md` at the repo root. Find the first unchecked item (`- [ ] ...`).

For that one item:
1. Implement only that change — nothing else, no adjacent cleanup, no scope creep.
2. Commit it with a message that keeps the task's prefix (`chore:`, `feat:`, `fix:`, etc.) but is written from the task list, not copied from it verbatim. Some entries are phrased as investigations ("check if...") or as a bug/problem description rather than the fix — resolve that phrasing before it becomes a commit message:
   - An entry phrased as a question or investigation ("check if we need to delete X") means: go investigate, decide, and act — then write the commit message as what you actually did or found (e.g. `chore: remove unused godot import metadata`, or `chore: confirm godot import metadata is all in use` if nothing needed removing), not as the original open question.
   - An entry phrased as a problem/bug report ("light gray text doesn't read well") means: write the commit message as the fix that was applied (e.g. `fix: darken light gray text for readability`), not as the complaint.
   - An entry already phrased as a directive (a clear feat/fix/chore instruction) can keep its wording close to as-is.
   The commit message should read as a description of a completed change, never as an open question or a restated problem.
3. Check the box for that item in `work-queue.md` (`- [ ]` → `- [x]`).
4. Commit the checkbox update too — folding it into the same commit as the implementation is fine and preferred when it's a single small change.

Arguments: $ARGUMENTS

- No argument: do exactly one item, then stop.
- A number N (e.g. `3`): repeat the above for the next N unchecked items, in order, committing each one separately before moving to the next.
- Stop immediately if you hit an item that's ambiguous enough to need a decision only the user can make — report what you did so far and what's blocking the next item, rather than guessing.

Do not start additional items beyond what was asked. Stop after the requested count (default: one) even if more unchecked items remain.
