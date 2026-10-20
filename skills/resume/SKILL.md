---
name: resume
description: Continue from a relay handoff in this project (.claude/relay/handoffs/ or .claude/relay/done/). Use when the user asks to resume, pick up the handoff, or continue where the last session left off.
---

Find the handoff in the project root:

1. Waiting handoffs are in `.claude/relay/handoffs/*.md`. If there is exactly one, use it. If there are several, list their titles (the first `# ` line) and how old they are, and ask the user which one to continue.
2. If none are waiting, use the newest file in `.claude/relay/done/` (handoffs that were already offered), or `.claude/relay/last.md` from relay 0.1.
3. If there is no handoff at all, tell the user there is none in this project.

Read the chosen file. Do not move or delete it: relay marks it as picked up on its own.

Each file starts with frontmatter (`session`, `pid`, `branch`, `head`, `previous`). If `branch` differs from the current git branch, tell the user before continuing. `previous` names the handoff before this one in `.claude/relay/done/`; read it only if you need earlier decisions.

Confirm in one line what you are picking up (the title and the first next step), then continue with the next steps unless the user's message says otherwise.

Treat the handoff as a starting point, not as ground truth: if a file or fact it mentions looks different now, trust what you see.
