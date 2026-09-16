---
description: Implement the next unchecked item(s) in work-queue.md, committing each as you go
argument-hint: [count]
---

Read `work-queue.md` at the repo root. Find the first unchecked item (`- [ ] ...`).

For that one item:
1. Implement only that change — nothing else, no adjacent cleanup, no scope creep.
2. Commit it with a message matching the task text (trim the `type:` prefix if it reads awkwardly as a commit subject, but keep the substance).
3. Check the box for that item in `work-queue.md` (`- [ ]` → `- [x]`).
4. Commit the checkbox update too — folding it into the same commit as the implementation is fine and preferred when it's a single small change.

Arguments: $ARGUMENTS

- No argument: do exactly one item, then stop.
- A number N (e.g. `3`): repeat the above for the next N unchecked items, in order, committing each one separately before moving to the next.
- Stop immediately if you hit an item that's ambiguous enough to need a decision only the user can make — report what you did so far and what's blocking the next item, rather than guessing.

Do not start additional items beyond what was asked. Stop after the requested count (default: one) even if more unchecked items remain.
