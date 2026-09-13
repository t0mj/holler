---
title: One session, 1.9M tokens, idea to launch
subtitle: A local 27B ran the whole arc on a 262K window — closed research, phase gates, todos, and two compactions it sailed straight through
date: 2026-09-12
draft: false
tags: [local-llm, qwen, agent-harness, long-context, compaction]
summary: "One continuous local-27B session took a coding-agent TUI from a closed research handoff to a launched build — long-horizon work without a frontier model or a million-token context."
crossposts: []
---

## TL;DR

- **The shift:** One continuous session took a coding-agent TUI from a closed research handoff to a full build to launch — no wrap-up, no restart, no frontier model.
- **The machine:** The plan never lived in the model's head. It lived in artifacts — an execution log, a todo list updated thirty-odd times, phases that ended with tests, and two compactions — one at a phase boundary, one at 95% of the window — that the session sailed straight through.
- **The numbers:** fourteen prompts, 313 turns, two compactions, ≈1.9M new tokens, and a peak context of 248K — 95% of the 262K window.
- **The caveat:** n=1, one workflow shape. And the framework did as much of the work as the model did.

## What happened

The build: a pane-based TUI for a coding agent, rendered inside Ghostty — title-bar chrome with git branch, session title, and model cost; a session feed; a todos pane; JSON config; a slash command to open it.

The session didn't start from an idea in a chat box. It started from a closed research phase — five live probes against the terminal's internals, all verified and closed — with a locked design direction and an ordered phase plan. What the session then did is the point of this post: it ran the whole remaining arc, plan to build to install to launch, in one continuous run. And when the launch was done, it didn't stop — the next prompt was a rendering quirk I'd spotted, and that got root-caused and fixed in the same session, too.

## The machine

This is the part worth stealing, because none of it is a model feature.

**The handoff was closed.** Research done, results recorded, direction locked, phases ordered. The agent's first move was to re-verify the repo — working tree, live probe window, the patch inventory — and then it asked exactly one direction question: which phase to enter, with three sub-decisions attached. I answered, and it was the last question it needed.

**State lived on disk, not in the model's head.** Every phase ended with a commit, a test run, and an entry in an execution log that lives in the repo. When the session needed to remember anything, the log was the memory. The model could lose the thread and pick it back up, because the thread was a file.

**The plan lived in the todos.** Thirty-odd todo updates across the session — the plan was an artifact that got updated as work landed, not a recollection that got fuzzy. Even after two compactions, the finished phases were still sitting in the list and the in-flight phase's plan was sitting in the compaction summaries. Nothing was lost, because the plan had never only been in the model's head.

**The compaction.** This is what made the long horizon possible on a 262K window. At a phase boundary, with the context at roughly 146K, the model wrote out the state of play, compacted, and its first sentence afterwards was the exact thread it had just been on — recon for the next phase. Nothing lost. Then it kept going. The context climbed back to 248K — 95% of the window — in the middle of a crash fix, and it compacted again, and the fix landed in the same stretch. The log shows fifteen dropped connections across the session that it just worked through. Two compactions, fifteen dropped connections, zero stops. A million-token context is one way to keep a long session alive. Compaction at phase boundaries, a plan in artifacts, and logs you can re-read is the other. The window is a buffer, not the memory.

**It verified itself against the live terminal.** Ghost text, footer line counts, prompt-window rendering — checked against a real terminal window in a live probe, not imagined. The missing pieces it found, it found itself.

The model isn't smarter; the machine is tighter.

## The shape of the collaboration

Roughly twenty-two turns per prompt. That's the density that matters: I was not in the loop on the work. My prompts, over the session, were go-aheads, a mid-flight feature idea ("fold this into the plan"), observations and questions about what I was looking at in the UI, one idea I reversed and wanted parked, a crash report, and a rendering quirk. Ideas arrived as I thought of them, and the machine folded them or parked them without breaking stride.

Not a correction every few minutes. Fourteen prompts across a session that ran past eight hours.

## The numbers, lightly

Measured from the session log at close (2026-09-12); these numbers are final.

- **Wall time:** 8h 38m closed; **active model time** a little under half of that (~3.4 hours).
- **Prompts:** 14. **Assistant turns:** 313. **Tool calls:** 328 (152 bash, 70 edit, 46 read, 33 todo, 17 write, 1 direction question, 4 diagnostics, 3 live-terminal observations, 1 subagent, 1 compaction).
- **Compactions:** two — one the model called at a phase boundary (~146K), one at the wall (~248K, 95% of the window). Zero stops.
- **New tokens:** 1,649,891 in + 273,100 out ≈ 1.9M. **Cache-read:** 37.8M — the standing prompt re-served every turn; the cache did the heavy lifting.
- **Peak context:** 247,810 — 95% of the 262K window — hit on the crash-fix climb that triggered the second compaction.
- **Thinking:** medium, ~157K reasoning tokens across the session.
- **Hardware & cost:** Qwen 3.8 27B in FP8, vLLM, one rented **A100 SXM** at ~$1.59/hr (standing pod, up for the session's window) — the whole idea-to-launch arc came in just under fifteen dollars of GPU (estimate: 8h 38m at the hourly rate).

## A piece of mind

We're getting long sessions out of the local fleet that hold up against my best frontier-model sessions — and I've actually stopped reaching for the cloud for this kind of work.

The $20 a month for Claude Code is worth it — for non-proprietary stuff, or things I don't mind being harvested. This isn't that. It's a journal, in the sense that no one needs to see how poorly I write my prompts, or be watching the progression of ideas as they develop. Knowing everything is local takes a weight off my shoulders about what's loaded or in flight.

That's the whole point of the fleet, honestly. The speed numbers are the headline; the piece of mind is the subtext.

## A grain of salt

n=1. One session, one model, one workflow shape, and the workflow was the good kind: research already closed, direction already locked, phases already ordered. Put a 27B on a blank page with none of that and this post does not get written. The machine is the mechanism; the model is the engine.

This was UI work — visible, verifiable, and forgiving of small errors in a way a numerical or security-sensitive workload isn't. And it had one crash: a shape issue introduced by a hot reload. Caught, root-caused, and fixed in the same session. Small against what the session did.

I still don't know what a healthy prompt cadence looks like for a session like this. If you've clocked yours, I want the number.

Related:

- [Defragging an agent's memory with a frontier-model dispatch](/posts/memory-defrag-dispatch/) — the dispatch contract that keeps the fleet honest.
- [Qwen 3.8 thinking levels, measured](/posts/qwen38-thinking-levels/) — where the medium setting in this session comes from.

## The effort, honestly

Every number above is measured from the build session's own log after it closed, then re-checked against the raw file. The post was drafted and verified in a separate coordinator pass; the closer is the author's own.

- **The build session** — qwen3.8-27b-fp8 on one rented A100 SXM: 14 prompts, 313 assistant turns, 328 tool calls, ≈1.9M new tokens with cache reads excluded, ~3.4 hours active inside 8h 38m of wall.

<p class="harness-meter"><span style="color:var(--accent)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><circle cx="7" cy="4.2" r="2.9" fill="currentColor"/><path d="M1.8 13.2c.5-3.4 2.6-5 5.2-5s4.7 1.6 5.2 5z" fill="currentColor"/></svg></span> 1308 words · 14 prompts <span class="sep">||</span> <span style="color:var(--gold)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><rect x="2.4" y="4.6" width="9.2" height="7.4" rx="1.8" fill="currentColor"/><line x1="7" y1="4.6" x2="7" y2="2.6" stroke="currentColor" stroke-width="1.1"/><circle cx="7" cy="2" r="1" fill="currentColor"/><circle cx="5.3" cy="8.3" r="1.1" fill="var(--paper)"/><circle cx="8.7" cy="8.3" r="1.1" fill="var(--paper)"/></svg></span> 327 messages · ~1.9M tokens <span class="sep">||</span> <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" style="color:var(--ink);opacity:.7"><circle cx="7" cy="7" r="5.4" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M7 3.9V7l2.3 1.5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg> ~3.4 hours</p>
