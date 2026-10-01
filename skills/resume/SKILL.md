---
name: resume
description: Continue from the most recent relay handoff in this project (.claude/relay/handoff.md or .claude/relay/last.md). Use when the user asks to resume, pick up the handoff, or continue where the last session left off.
---

Read the handoff from the project root: `.claude/relay/handoff.md` if it exists, otherwise `.claude/relay/last.md`.

- If neither exists, tell the user there is no handoff in this project.
- Otherwise, confirm in one line what you are picking up (the title and the first next step), then continue with the next steps unless the user's message says otherwise.

Treat the handoff as a starting point, not as ground truth: if a file or fact it mentions looks different now, trust what you see.
