---
name: relay
description: Hand off to a fresh agent session at the end of a task instead of compacting mid-work. Use when the user asks to hand off, wrap up for a new session, save the session state before clearing the context, or when they ask to resume, pick up the handoff, or continue where the last session left off.
---

# relay

Long sessions get compacted in the middle of work and lose detail. relay moves the work to a fresh session at a clean point instead: the current session writes a handoff file, the user clears the context (or opens a new chat), and the new session continues from that file.

Each handoff is its own file, so several sessions in the same project never overwrite each other:

- Waiting handoffs: `.claude/relay/handoffs/<YYYYmmdd-HHMMSS>-<title-slug>.md`
- Picked-up handoffs: `.claude/relay/done/` (kept so you can look back)

Decide which mode the user wants:

- **Hand off**: they want to stop here and continue in a fresh session.
- **Resume**: they want to continue from an earlier handoff.

## Hand off

1. Check whether there is concrete follow-up work. If there is none, say in one line that everything is done and nothing needs to be carried over, and stop.
2. Write the handoff for a fresh agent that has no memory of this conversation. Use Markdown without code fences, keep it under 6000 characters, and start the file with this frontmatter:

   ```
   ---
   branch: <current git branch, or empty>
   head: <short commit hash, or empty>
   previous: <file name of the handoff this session started from, or empty>
   ---
   # <one-line title>
   ## Goal
   ## Current state (what is done, and how it was verified)
   ## Next steps (ordered, concrete)
   ## Key files (paths and why they matter)
   ## Decisions and constraints (including approaches tried and rejected, and why)
   ## Open questions
   ```

   Use exact paths, commands, names and IDs. Do not narrate the session.
3. Save it in `.claude/relay/handoffs/`, named with the current date and time plus a short slug of the title (for example `20261020-141200-auth-refactor.md`). If this session already wrote a handoff that is still waiting there, replace it. Never touch handoffs written by other sessions. If `.claude/relay/.gitignore` does not exist, create it with the single line `*` so handoffs never end up in git.
4. Tell the user in one line, in their language, to clear the context or start a new session and ask it to resume (for example "resume the handoff").

## Resume

1. List `.claude/relay/handoffs/*.md`. If there is exactly one, use it. If there are several, show their titles (the first `# ` line) and how old they are, and ask the user which one to continue.
2. If none are waiting, offer the newest file in `.claude/relay/done/`. If there is nothing there either, tell the user there is no handoff in this project and stop.
3. Read the chosen file, then move it from `handoffs/` to `done/` so no other session picks it up. Remember its file name: it is this session's `previous` if you hand off again later.
4. If its `branch` differs from the current git branch, tell the user before continuing.
5. Confirm in one line what you are picking up: the title and the first next step. Then continue with the next steps, unless the user's message asks for something else.

Treat the handoff as a starting point, not as ground truth. If a file or fact it mentions looks different now, trust what you see.

## Automatic handoffs in Claude Code

This skill is the portable version, and you trigger it yourself. For Claude Code there is also the free relay plugin (github.com/4mierS/relay). It measures the real context size, asks for a handoff on its own at the end of a task, and offers it after `/clear` without you typing anything.
