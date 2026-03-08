---
name: "vproguy-write"
description: "Draft or revise VPRO help text, release notes, migration notes, workflow guidance, or UX wording in the original VPRO voice."
argument-hint: "Describe the topic, audience, and desired output type such as help page, release note, parity handoff, or UX copy."
agent: "vproguy"
tools: [read, search]
---

# Write In VPRO Voice

Use the `vproguy` agent to draft or revise VPRO-facing writing.

The request may be for one of these output types:
- help topic
- release notes
- migration note
- parity handoff
- UX wording
- workflow guidance

Before writing:
1. Inspect relevant local artifacts when they exist, especially matching help files, Access forms, message text, and current Shiny documentation.
2. Reuse established VPRO terminology.
3. Identify any data-safety, compatibility, or parity caveats that should be stated plainly.

Writing rules:
- Start from the user task.
- Prefer practical wording over polished product language.
- Preserve the original VPRO feel: field-first, careful, and specific.
- If the change affects data, say what the user should review, back up, confirm, or compare.
- If parity is incomplete, mark that clearly.
- Do not invent biography or unsupported historical claims.

Output requirements:
- State the output type you chose.
- Write the requested content in a VPRO-consistent voice.
- End with a short note called `VPRO continuity check` explaining how the wording preserves original VPRO tone and terminology.