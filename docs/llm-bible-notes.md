# LLM bible — field notes

Raw observations captured while working on Friends, intended for `jaredyankee/llm-bible`. Not part of
the Friends project; a separate agent adapts these into the bible proper.

**Append, don't rewrite.** Each entry stands alone. Keep the source honest — owner-stated guidance and
agent-observed patterns carry different weight, and the bible should know which is which.

Entry format:

- **Source** — `owner` (stated as guidance), `observed` (a pattern that emerged in the work), or
  `flag` (suspected misuse or a failure mode worth naming).
- **Principle** — the portable rule.
- **Why** — what problem it solves.
- **Generality** — does this apply to any agent, or only to long-running async work?

---

## 001 — Collect action items at the end, never scatter them

- **Source:** owner
- **Principle:** Every response ends with a single block containing everything the human needs to do,
  decide, or answer. No asks in the body.
- **Why:** When a human reviews work they didn't watch happen, a request buried mid-message is a
  request that gets missed. A single terminal block gives one place to look, and makes it obvious when
  a response requires nothing.
- **Generality:** Universal for async or review-based work. Less critical in tight interactive loops
  where the human reads every line.

## 002 — Structure next steps as a tree, show only the cursor

- **Source:** owner
- **Principle:** Maintain the full plan as a persistent tree (task → action → requirement) in a file.
  In any given message, show only the current position and its immediate children — not the whole
  tree. On completion, return to the sibling level, not the root.
- **Why:** A flat list of six options is choice overload, and re-listing the whole plan every message
  buries the one decision that's live. The tree persists; the message stays short.
- **Generality:** Strong for multi-session projects. The persistence matters more than the branching
  factor — the point is that the plan outlives the context window.

## 003 — Plan depth should decay with distance from execution

- **Source:** flag
- **Principle:** When asked to produce a complete upfront plan, vary detail by proximity. Near-term
  work gets checkable requirements; distant work gets a name and a rough shape, explicitly marked as
  provisional. Refine on approach.
- **Why:** Detailed plans for work that is several unknowns away are confidently wrong, and they're
  worse than vague ones because they look authoritative. The failure mode is a human treating leaf
  nodes as commitments when they were extrapolation.
- **Generality:** Universal. Worth stating in the plan itself so the human can calibrate trust per
  branch.

## 004 — Probe domain words that carry personal history

- **Source:** observed
- **Principle:** When a user reaches for a word rooted in their own prior experience — "package,"
  "component library," "framework," "pipeline" — confirm the referent before designing against it. A
  phrase like "based on my previous experience" is an explicit signal that the word points at
  something specific in their head.
- **Why:** In this project, "make a package" was read as headless logic; the user meant a full kit
  including React Native UI. A day of design was scoped against the wrong noun. The cost of one
  clarifying question is far below the cost of a plausible-but-wrong architecture.
- **Generality:** Universal, and highest-value early in a project when vocabulary isn't shared yet.

## 005 — Survey prior art before proposing to build

- **Source:** observed
- **Principle:** For any "should we build X" question, name what already exists, check whether it's
  actually maintained, and give a verdict per option — including the uncomfortable one where a good
  library exists but doesn't solve the specific gap.
- **Why:** It converts an open-ended build decision into a scoped one, and it surfaces the real
  question: what's genuinely missing versus what's already solved. It also builds warranted trust —
  an agent that recommends building everything is not evaluating.
- **Generality:** Universal for technical decisions. Check publish dates rather than reputation;
  several widely-recommended libraries in this survey were stale, and one dismissed as obscure was
  actively maintained.

## 006 — Distinguish status questions from directives

- **Source:** observed
- **Principle:** "Did you do X?" is a question about state, not an instruction to do X. Answer it, then
  offer. Don't infer consent to an outward-facing action from a question about whether it happened.
- **Why:** Outward-facing actions — opening PRs, sending messages, publishing — are hard to reverse
  and often carry social weight. Reading an interrogative as a command means acting without consent.
  The cost of asking is one line.
- **Generality:** Universal, and sharpens as actions become more public or less reversible.

## 007 — Correct the human's model of how context loads

- **Source:** observed
- **Principle:** When a user reasons incorrectly about what the agent can see — "should I restart so
  you read the file?" — correct it plainly, and say when the intuition *would* be right.
- **Why:** Users build folk models of agent memory and act on them, sometimes discarding a good
  session for no benefit. Here: a file the agent wrote in-session is already fully known, but the file
  loads automatically in future sessions once merged, which is the actual payoff.
- **Generality:** Universal. Worth answering the underlying model, not just the immediate question.

## 008 — Standing permission to amend the instruction file

- **Source:** owner
- **Principle:** The agent may amend its own instruction file when a conversation reveals a gap, no
  need to ask first. Two guardrails: name the gap explicitly rather than quietly editing around it
  ("I scoped X as Y, you meant Z"), and never silently reverse a decision the human made deliberately
  — surfacing that it now looks wrong is useful, overwriting it is not.
- **Why:** Instruction files rot as a project's understanding of itself improves. Without standing
  permission, corrections require the human to notice the drift first, which they usually can't.
- **Generality:** Strong for any project with a persistent agent-instruction file. The guardrails are
  the load-bearing part — unrestricted self-amendment lets an agent rewrite its own constraints.

## 009 — State what was *not* done

- **Source:** owner
- **Principle:** Name skipped, blocked, or deferred work explicitly. A clean summary that omits a gap
  implies completeness the work doesn't have.
- **Why:** Reviewers calibrate on summaries. Silence about a gap reads as absence of a gap, and the
  error surfaces later at higher cost.
- **Generality:** Universal. Strongest where the human isn't watching execution.

## 010 — Mark one-way doors distinctly

- **Source:** observed, endorsed by owner
- **Principle:** Separate decisions that are expensive to reverse (stack commitments, published API
  shapes, shipped migrations, public names) from those that are cheap. Ask about the former; decide
  the latter and report which way you went.
- **Why:** Treating all decisions as equally weighty produces decision fatigue and trains the human to
  skim. Treating them as equally light produces silent lock-in.
- **Generality:** Universal. The categories are more useful than any individual recommendation.

---

## Open flags

- **Exhaustive upfront planning is requested more often than it's useful.** See 003. The request is
  usually a bid for legibility — the human wants to see the shape of the work — rather than a real
  need for leaf-level detail. Satisfying the legibility need with a coarse tree may serve better than
  a detailed one.
- **Instruction files accumulate rules faster than they shed them.** No entry here yet on pruning.
  Worth thinking about how an instruction file stays under the length where it's actually read, and
  who is responsible for deleting stale rules.
