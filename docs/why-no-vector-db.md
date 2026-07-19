# Why there is no vector database

I looked at a lot of personal second brains before building this one, and bounced off most of
them for the same two reasons: I could never tell what the system was actually doing, and
getting started meant installing a stack. Vector store, embedding pipeline, sync daemon,
plugin stack, an MCP server or two.

So the goal was not better retrieval. It was a system I could always see inside of, that asks
you to install as little as possible. Dropping the vector database falls out of that, and this
document is the argument for why it is not a sacrifice.

Retrieval here is three reads:

1. `wiki/hot.md` — a working-memory cache, capped at 500 words, injected at session start
2. `wiki/index.md` — the master catalog, one line per page
3. the three to five pages that line points to, following wikilinks at most one hop

With a grep fallback when the index wording does not match the question. Every step is a file
you can open. ([The full pipeline, in both directions](what-happens-when-you-ingest.md).)

## Every step is legible

This is the whole point, so it goes first.

When a lookup misses here, it is a bad line in `index.md`. You open the file, see that the
catalog entry was vague or that the page was never indexed, and fix the line. The failure has
a location.

When embedding retrieval misses, you have a number. The chunk boundary fell mid-argument, or
the query embedded closer to a neighbour, or the index is stale from three commits ago. Each
is plausible, none is visible, and the debugging surface is a similarity score.

The same asymmetry applies to correctness, and this is where it stops being philosophical.
Because the entire retrieval substrate is text, a script can verify it: `vault_lint.py`
deterministically checks dead wikilinks, orphan pages, duplicate filenames, alias collisions,
frontmatter gaps, index drift and cache size, and tells you exactly what is broken. No tokens,
no model judgment.

There is no equivalent lint for a vector index. You find out it was wrong when an answer is
wrong.

## Nothing to install, nothing to keep running

The system is markdown, YAML frontmatter, one stdlib Python linter and a shell hook. No
embedding model to pin a version of. No vector store to run, migrate, back up or keep in sync.
No reindexing pipeline to fail silently while you keep asking questions and getting
confidently incomplete answers. No MCP server between you and your own files. Nothing to pay
for beyond the model calls you were making anyway.

The notes are plain files in a git repository you own. Obsidian reads them with no plugins —
graph view, backlinks and Properties work out of the box. If this project is abandoned
tomorrow, the vault still opens, still searches, still renders, and every tool that reads
markdown still works on it.

That is worth more than better recall, at least to me.

## The index is written by the thing that reads it

The transparency argument would be hollow if the simpler approach did not actually work. It
does, for a reason that is easy to miss.

A vector store exists because software cannot read. It converts text into coordinates so that
a machine with no comprehension can approximate relevance by measuring distance.

That constraint no longer holds. The reader here is a language model, and the catalog it reads
was written by a language model, in prose, on purpose. `index.md` is one line per page
describing what that page is about. Picking the relevant three from a few hundred such lines
is not a search problem — it is reading comprehension, which is exactly what the reader is
good at.

Embedding a corpus so that a model can find things in it is translating a document into a
format optimized for a reader that isn't there anymore.

## The graph is curated, not inferred

Cosine similarity infers that two notes are related. Here it is not inferred: when a page
mentions an entity or a concept, it links to it with `[[wikilinks]]`, written deliberately at
ingest time with the full source still in context.

A hand-placed link carries intent that a similarity score cannot reconstruct. "These two pages
are 0.83 similar" and "this decision was made because of that constraint" are not the same
claim. The first is a measurement; the second is knowledge. Following one hop of real links
beats expanding a similarity radius, because the links encode why.

## Contradictions need structure, not similarity

New information that conflicts with an existing page gets a callout on both sides, and nothing
is silently overwritten:

```markdown
> [!warning] Contradiction with [[Other Page]]
> This page claims X; [[Other Page]] claims Y. Needs resolution.
```

Detecting that requires knowing which existing page makes the competing claim, and then editing
that page. Similarity search surfaces neighbours; it has no notion of a claim being in tension
with another, and no place to record that it is. A store that only retrieves cannot flag — it
can only return two conflicting chunks and let them fight in the context window.

## Where this breaks down

This is a real tradeoff, not a free lunch.

**Scale.** The read path assumes a catalog a model can hold in context — hundreds to low
thousands of pages, which is what a personal vault is. Point this at a corporate wiki with
fifty thousand documents and the index stops fitting, at which point you want a real retrieval
layer.

**Wording you did not anticipate.** If the index line and your question share no vocabulary and
no concepts, the read path can miss where semantic search would hit. That is what the grep
fallback is for, and grep is a weaker net than embeddings.

**A model in the loop.** Retrieval is reading, so it costs a model call. Vector search answers
without one. For a second brain you talk to, you were paying for the call anyway.

**Consolidation is not free.** Ingest is sequential and deliberate, one source at a time.
Compared to dropping files into a folder and letting a pipeline absorb them, this is slower by
design — the structure that makes retrieval cheap is created at write time, not at read time.

If your corpus is large, machine-generated, or queried by something that isn't a language
model, use a vector database. If it is your own notes, read by a model, and you want to be able
to see what is happening to them, the index costs nothing to inspect and everything it knows is
written in words you can read.
