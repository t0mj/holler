---
title: "I paid $4 for a frontier model to defrag my agent's memory"
subtitle: "The dispatch contract: renting a frontier model for structured local work — safely and auditably"
date: 2026-09-07
draft: false
tags: [agents, memory, headless-dispatch, runpod]
summary: "Two headless dispatches to a rented 320B MoE rebuilt my coding agent's drifted markdown memory — −21.5% standing context for about $4 of billed time — and the reusable part isn't the defrag, it's the dispatch contract."
crossposts: []
# fallback title candidate (swap at review, no re-draft needed): "−21.5% standing context for $4: defragging an agent's markdown memory with a rented 320B MoE"
---

## TL;DR

- **The pattern:** commission a rented frontier model for structured local work with a **written contract, not a prompt** — scoped tool allowlist as the sandbox, a human gate between findings and execution, and an audit you run yourself instead of trusting the report.
- **The case study:** my coding agent's markdown memory store, one month of daily use, fully drifted. Rebuilt in two headless dispatches: **−21.5% standing context** (the bytes every session pays forever), **~5.4k tokens** of total structural reduction, **3 live contradictions** fixed.
- **The cost:** ~30 minutes of billed model time on a 1× B300 at $7.89/hr ≈ **$4**. Honest dollars after: ~$0.015/session. The dollar figure is not the story.
- **The acceptance criterion:** a 22-item manifest executed **1:1 to the commit log** — 18 scoped commits + 1 commit in a second repo + 2 staged files + 1 untracked diff + 1 report-only item = 22. If the log and the manifest disagree, the manifest loses.

## The drift

My coding agent (pi) keeps its durable memory as flat, git-versioned markdown: an always-loaded global context file, an always-loaded index, and about 15 on-demand entries. One month of daily use and it had drifted the way every append-biased store drifts. The index's "one line per entry" rule had rotted into 2.5 KB abstract paragraphs. Per-release changelogs were living inside semantic entries that get read on every session. Live-state lines silently contradicted each other — one said a thing was running, another recorded it terminated, and both were loaded as truth. And a load-bearing checklist's canonical copy sat in a read-only directory owned by another tool, where the store that referenced it couldn't maintain it.

None of this is exotic. It's what happens when a store only ever grows: everything is "important," so nothing is load-bearing, and the contradiction you don't notice is the one you pay for later in confidently wrong answers.

## The dispatch, in six beats

The whole rebuild — inventory, a web-grounded ideal-state review, and a 22-item efficiency pass — ran as **two headless dispatches to a rented frontier model**: GLM-5.3-Flash, a 320B-A18B MoE at Q4, on a single B300 at $7.89/hr. Total billed model time was about 30 minutes ≈ $4 (30 min × $7.89/hr ≈ $3.95 — arithmetic on the billed rate; the $4 in the title is rounded). Human involvement: one commissioning message, one mid-run gate, one final review. My interactive session's own context was never touched.

The shape, in six beats: **preflight** every launch; a **contract, not a prompt**; the **tool allowlist as the sandbox**; a **human gate** between findings and execution; **parent-side verification** of the report; and **auditability as the acceptance criterion**.

The CI world already knows the framing: running an agent unattended concentrates three risks — permission, cost, and audit — that an interactive session diffuses across a human's attention (hidekazu-konishi's headless-automation guide is a good public treatment). This post is that same lesson carried into a personal, rented-GPU context. There's no pipeline to hide inside, so the contract has to carry all three itself.

## Beat 1: preflight

Five cheap checks, ~5 minutes, before any billed time:

1. **Readiness** on the rented pod.
2. **Model-identity check.** The commission said "GLM 5.6"; no such model existed. Caught before a single billed minute.
3. **A live tool-calling probe** — one-shot tools request plus one multi-turn tool-result loop against the raw endpoint. This is the thing that makes or breaks an agent dispatch, and it was untested for this build.
4. **A ~30 s headless smoke run** on the exact model and tool allowlist the real task would use.
5. **A search-path check** — the default DuckDuckGo backend was returning empty results from that machine; caught in time, and the task rerouted to a SearXNG instance plus direct fetches.

Each of these is a historical misfire class wearing a check. The preflight is load-bearing: skipping it converts "5 minutes of checks" into "30 minutes of billed silence" — and on this exact day, two of the five checks caught real failures.

## Beat 2: a contract, not a prompt

The task wasn't a prompt; it was a self-contained file: goals, exact scope, hard change rules, a per-repo commit regime, pre-baked decisions, and an exit protocol. The hard rules, verbatim:

*only these files; one scoped commit per item; explicit pathspecs, never `add -A`; lost-update grep before each commit*

And the operating assumption, verbatim:

*there is no interactive user — choose the conservative option and list open questions in the report*

The per-repo commit-regime table is the part people skip. One repo in scope auto-commits. One is stages-only — a human reviews before anything lands. Two files are untracked, so the contract pre-authorizes a diff written to a scratch directory instead of any commit at all. Three different trust levels, decided by a human in advance, not by the model at run time.

That's the distinction that matters. A prompt delegates judgment to the model during execution. A contract removes the judgment in advance — what's left is execution. Phase 1's job was to turn the drift into a 22-item draft manifest (`file · action · one-line why`) and to change nothing else.

## Beat 3: the allowlist is the sandbox

The child ran headless with a named session and this tool allowlist: `read, grep, find, ls, bash, edit, write, todo`. No web tools, no ssh, no browser, no subagents, no question tool. Phase 2 needed zero network, so Phase 2's allowlist had zero network tools.

This is the quiet core of the pattern. The sandbox isn't a policy that says "please don't" — it's a tool list that makes the out-of-scope **structurally impossible**. Deletions and cross-boundary edits were not in the allowlist, so they could not happen no matter what the model decided. The named session means the full transcript — every model call and every tool call — sits on disk as the audit trail.

The CI world's version of the same rule: anything outside a pre-approved allowlist should fail closed rather than block on an approval that will never come (the Developers Digest headless-CI comparison covers this across four agents). Same principle, personal scale.

## Beat 4: the gate between findings and execution

Phase 1 stopped with findings and a 22-item draft manifest, having touched nothing but its own report files. Then the human gate: 8 open questions, each arriving with a conservative default already chosen — so the gate was about 5 minutes of deciding, not an essay assignment. Eight decisions came out, and Phase 2's contract carried them as D1–D8, which means nothing in the execution phase needed judgment the human hadn't already made.

This is the beat that looks like overhead and isn't. Eight wrong assumptions got fixed at ~5 minutes of human time instead of 30 minutes of billed execution. And a mid-run gate is only possible because the dispatch is two phases **by construction** — a single-phase dispatch has nowhere to put it.

## Beat 5: don't trust the report

When the child exited, I didn't read the report and nod. The verification ran on my side:

- Recomputed the hash derivation the child asserted.
- Re-ran the "stale fact" checks myself.
- Re-measured the file sizes with my own tools.
- Audited the 22-item manifest against the commit log **1:1**: 18 scoped commits + 1 commit in a second repo + 2 staged files + 1 untracked diff + 1 report-only item = 22.
- Confirmed a concurrent session's dirty files in a shared repo were untouched.

One detail worth keeping: the child had self-reported a mid-run editor glitch that it caught and repaired inside its own commit window. That's the contract's post-edit grep discipline paying off — every edit verified itself immediately, so the glitch was a recoverable blip rather than silent corruption discovered next week.

## Beat 6: auditability is the acceptance criterion

One logical change per commit means `git log` **is** the execution record. The final diff corresponds 1:1 to the manifest — no unlisted changes, because unlisted changes were structurally impossible (beat 3). You don't read the child's report to trust it; you read it to know where to look. If the commit log and the manifest disagree, the manifest loses.

## What it bought

All numbers measured 2026-09-07 on the actual store, before and after the run. Standing context — paid by every session, forever:

| file | before | after | delta |
|---|---|---|---|
| global context file (always loaded) | 20,245 B | 18,454 B | −1,791 B |
| index (always loaded) | 7,743 B | 3,509 B | −4,234 B (−54.7%) |
| **Tier-0 total** | **27,988 B** | **21,963 B** | **−6,025 B (−21.5%) ≈ ~1.5k tokens** |

The four heaviest on-demand entries — paid on every read — came in at 26,464→16,714 B, 12,142→9,805 B, 5,848→3,132 B, and 4,029→3,078 B. That's −15,754 B ≈ ~3.9k tokens per full read of that set (token figures at ~4 bytes/token, the writeup's own convention). Total structural reduction: **~21.8 KB ≈ ~5.4k tokens**.

And the part that doesn't show up in a token count — **correctness**: 3 live contradictions fixed (a "LIVE" pod line vs its termination record; "no `gh` on this machine" vs `gh` installed and authed; a retired-OS fact in a stale entry), plus 1 factually wrong store description (a per-project store described as one tool's output that is actually another tool's runtime records — and the described store had *never been created*). Every state line now carries a `last-verified:` date.

## Dollars, honestly

~1.5k standing tokens × $10/M ≈ **$0.015/session** — a couple of dollars a month at heavy use. The dollar figure is not the story. The story is: 21.5% of the standing slot back for working material, one canonical home per rule (there used to be 2–3, which is how the contradictions happened), and a recorded maintenance ritual — a quarterly staleness sweep plus a written re-defrag trigger — instead of the previous monotonic drift.

## Further reading

Thread (a) — headless/scoped dispatch (the CI world as allies, not prior art being one-upped):

- [Claude Code in CI/CD and Headless Automation](https://hidekazu-konishi.com/entry/claude_code_cicd_and_headless_automation.html) — permission, cost, and audit as the three risks of unattended runs
- [Headless AI Coding Agents in CI: Claude Code, Codex CLI, Gemini CLI, and opencode Compared](https://www.developersdigest.tech/blog/headless-ai-coding-agents-ci-comparison-2026) — allowlists that fail closed, across four tools

Thread (b) — agent-memory design (what grounded the ideal-state review):

- [AI Agent Memory Design Guide](https://hidekazu-konishi.com/entry/ai_agent_memory_design_guide.html) — CoALA taxonomy, context budgeting
- [Awesome-AI-Memory](https://github.com/IAAR-Shanghai/Awesome-AI-Memory) — survey taxonomy, memory lifecycle
- [Agent Memory Engineering](https://nicolasbustamante.com/blog/agent-memory-engineering) — the production verdict: the simple thing won
- [Markdown Is Not Agent Memory](https://blog.getzep.com/markdown-is-not-agent-memory) — the counterpoint, whose own concession (one agent, one user, locally re-derivable truth) is exactly the regime this store lives in

## A grain of salt

- **n=1.** The −21.5% and ~5.4k tokens are this store's defrag, not a universal promise. The *shape* (append-biased markdown memory + always-loaded index) is the common case; the percentage isn't. If you defrag yours, post the before/after — I'd genuinely like to know what a healthy number looks like across stores.
- **The model is the point of the experiment, not a recommendation.** A 320B-A18B MoE at ~$8/hr did well on a *structured, contract-shaped* task with heavy local file work and bounded research — this run was ~90% local reads and edits, ~10% web. Open-ended synthesis is a different workload, and I have no data on it here.
- **The preflight is load-bearing.** The tool-call probe and the search-path check each caught a real failure mode on the day. Skipping them converts 5 minutes of checks into 30 minutes of billed silence.
- **The gate is not overhead.** It's where 8 wrong assumptions got fixed at ~5 minutes of cost instead of 30 minutes of billed execution.

That's the whole pattern: rent the model, write the contract, scope the tools, gate the run, verify the report, and let the commit log be the record. Six beats, each load-bearing.

## The effort, honestly

This post was made the way it describes: a written charter, a handshake before any real work, milestone-gated turns, and a human at every gate — three of them between the commission message and this paragraph (sign-off, the outline review, the final read). The meter, measured from the session records on 2026-09-07:

- **The writer** — the rented 320B, three turns (handshake, outline, draft): 20 model messages, 17 tool calls, ~693k tokens, about 10 minutes of model time.
- **The coordinator** — the local 27B that kept the gates, verified the citations, and ran the identifier sweep: 69 model messages, 59 tool calls, ~13.9M tokens across the run's 166 minutes.

The asymmetry is the point: the expensive model spent ten minutes doing the thing it's good at, and the cheap model spent the hours doing the thing contracts are for — checking.

<p class="harness-meter"><span style="color:var(--accent)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><circle cx="7" cy="4.2" r="2.9" fill="currentColor"/><path d="M1.8 13.2c.5-3.4 2.6-5 5.2-5s4.7 1.6 5.2 5z" fill="currentColor"/></svg></span> 355 words · 9 prompts <span class="sep">||</span> <span style="color:var(--gold)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><rect x="2.4" y="4.6" width="9.2" height="7.4" rx="1.8" fill="currentColor"/><line x1="7" y1="4.6" x2="7" y2="2.6" stroke="currentColor" stroke-width="1.1"/><circle cx="7" cy="2" r="1" fill="currentColor"/><circle cx="5.3" cy="8.3" r="1.1" fill="var(--paper)"/><circle cx="8.7" cy="8.3" r="1.1" fill="var(--paper)"/></svg></span> 89 messages · ~14.6M tokens <span class="sep">||</span> <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" style="color:var(--ink);opacity:.7"><circle cx="7" cy="7" r="5.4" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M7 3.9V7l2.3 1.5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg> ~3 hours</p>

## Corrections

- 2026-09-12: the "four heaviest" line named the four memory entries; names dropped — the before/after bytes carry the point, not the map of the store.
