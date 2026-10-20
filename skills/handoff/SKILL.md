---
name: handoff
description: Write a handoff of the current work so a fresh session (after /clear) can pick it up. Use when the user asks to hand off, wrap up for a new session, or save the session state before /clear.
---

Write a handoff for a fresh Claude session that has no memory of this conversation.

Print it in your reply between a line containing only `<relay-handoff>` and a line containing only `</relay-handoff>`. The relay plugin saves it automatically when your reply ends; do not write any file yourself.

Use this structure, in Markdown without code fences, under 6000 characters:

# <one-line title>
## Goal
## Current state (what is done, and how it was verified)
## Next steps (ordered, concrete)
## Key files (paths and why they matter)
## Decisions and constraints (including approaches tried and rejected, and why)
## Open questions

Use exact paths, commands, names and IDs. Do not narrate the session.

After the block, tell the user in one line, in their language, to type `/clear`. The next session in this terminal will offer to continue from the handoff. Other terminals in the same project see it in a list.

If there is no follow-up work, say so in one line and print no block.
