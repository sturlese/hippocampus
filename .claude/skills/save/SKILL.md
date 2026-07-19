---
name: save
description: >
  File the current conversation's valuable content (analysis, decision, session summary)
  as a structured wiki note so it isn't lost in chat history. Triggers on: "save this",
  "guarda esto", "guárdalo en el wiki", "/save", "file this", "apunta esto",
  "guarda esta conversación", "save this session".
allowed-tools: Read, Write, Edit, Glob, Grep
---

# save: file this conversation into the wiki

Extract the durable knowledge from the current conversation and write it as a wiki page. The conversation is the input, not the content — save the conclusions, not the transcript.

## Workflow

1. **Identify what's worth keeping**: the synthesis, the decision and its rationale, the findings. Skip mechanical Q&A, setup steps, and anything already in the wiki (update the existing page instead — check `wiki/index.md`).
2. **Pick the type and destination**:
   | Content | Type / template | Destination |
   |---|---|---|
   | Analysis, answer to a question, research findings | `note` (`note_type: synthesis`) | `wiki/notes/` |
   | A decision that was made, with rationale | `note` (`note_type: decision`) | `wiki/notes/` |
   | Whole-session summary worth keeping | `note` (`note_type: session`) | `wiki/notes/` |
   | The conversation defined a new concept | `concept` | `wiki/concepts/` |
   | The conversation was about an ongoing project | update the `project` page | `wiki/projects/` |
3. **Name it** — short, descriptive, Title Case, unique. If the user gave a name, use it; otherwise propose one and ask only if the content is ambiguous.
4. **Write the page** from the matching `_templates/` skeleton: declarative present tense, in English, self-contained (readable cold in 6 months), every mentioned entity/concept wikilinked, claims cited as `(Source: [[Page]])`. If it answers a specific question, put the question verbatim in the `question:` field.
5. **Update `wiki/index.md`**, **prepend to `wiki/log.md`** (`## [YYYY-MM-DD] save | <Title>`), **refresh `wiki/hot.md`**.
6. **Confirm**: "Saved as [[Title]] in wiki/<folder>/."

If a page with the same name exists, ask before overwriting — usually the right move is updating it.
