---
title: "Flash-Next Q2 on Strata, on an AMD card: how it became my daily driver"
subtitle: "A config flag made a paid seat look like it was degrading at long context. Sorting that out is what made a 176B MoE on one 24 GB AMD card my daily driver."
date: 2026-10-11
draft: false
tags: [strata, amd, rdna3, flash-next, qwen, quantization, context, local-llm]
summary: "A config flag made a paid seat look like it was degrading at long context. Sorting that out is what made a 176B mixture-of-experts model on one 24 GB AMD card my daily driver."
crossposts: []
---

## TL;DR

- **The paid seat I thought was degrading at long context wasn't degrading.** A config flag was feeding the model its own prior reasoning, and it started echoing it back.
- **Sorting that out is what made the local seat usable.** A 24 GB card ran a 176B model by changing where the weights live, not by shrinking the model.
- **Depth is a slope here.** Quality held, reasoning got longer at depth, nothing truncated.
- **The practical number:** 300,000 tokens prefilled in under four minutes. The 27B seat it replaced took the same time for a third of that context.

## The engine that didn't get dumb

I had been running Flash-Next on a paid pod seat for about a month. Somewhere in that stretch — about 13,000 turns — the model started answering with short strings that echoed its own earlier reasoning.

My first assumption was that the context was getting too big for it. That is the story everyone tells about long context, and it was the easiest one to believe.

It was not the model, and it was not the context length. It was a config flag.

I checked truncation first, since that's the obvious villain. There was none — no truncation events, no aborts, no preemptions. Every run finished clean. The model wasn't being cut off mid-thought. It was finishing every thought, completely, and then repeating the tail of one of them back to me.

So I counted the echoes. They appeared 266 times across the seat's history. What made them more likely was the interesting part: the more copies of the echo already sitting in context, the likelier the next turn was to produce one.

| copies already in context | how often the echo appears |
|---|---:|
| none | 1.4% |
| 1–2 | 3.3% |
| 3–5 | 21.4% |
| 6–10 | 20.8% |
| 11–25 | 45.5% |
| 26 or more | 79.1% |

Context depth is a proxy. The real variable is copies in context, and copies accumulate with session length.

The culprit was a config flag. `preserve_thinking: true` renders the model's prior reasoning into the next prompt before the user's new message arrives. Every turn, the model was handed a growing archive of its own thinking, and past a certain density the echo became the most likely thing to say. Removing the echo removed the problem.

This is not a vLLM quirk. A probe of the local engine found it renders prior reasoning into the prompt regardless of the flag — identical results with `preserve_thinking` true, false, and absent. The local seat is not immune. In 1,418 turns on it so far, the echo has never collapsed into a stub, but the mechanism is there and the dose has not accumulated yet.

Getting that straight is what made me willing to run the same model quantized down to Q2_0 on a 24 GB AMD card. That is the seat I use now.

## How a 24 GB card holds 176 billion parameters

Before any of the above means anything, the seat has to work at all. A 66.4 GB model file does not fit in 24 GB of VRAM, and the model did not shrink.

The stock runtime could not do it. Enter Strata — the internet's latest hype, a HIP backend tuned for this card that streams the expert state instead of forcing all of it resident.

The model splits in two. About 125 billion are main parameters. The other 51 billion are n-gram and PLE tables. It is a mixture-of-experts architecture with 24,576 experts, roughly ten used per token, six billion active at any given step.

What sits in VRAM is 23.8 GiB of the 24.2 available. What does not: 31.6 GB of expert weights and the 28.8 GB PLE table, both in system RAM. At a 500,000-token context the KV cache pins another 5.90 GiB in RAM. What that handoff costs in access latency was never measured — it is the part of the arrangement that does not show up in a headline number.

Decode runs 105–160 t/s. Prefill is where the plumbing matters: plain hipBLAS gave 917–923 t/s, tuned hipBLASLt 1,718–1,725 t/s. Roughly double, from a kernel-selection change alone. The weights are identical.

I set the context to 500,000 and measured it holding 506,849 actual tokens. Cold load is 15 s; through the serving door, 25.6 s.

One card. 176 billion parameters. 500,000 tokens of context. Prefill nearly twice as fast. A machine I already owned.

## Depth is a slope here

Sixteen test items, thinking on and off, at 4k, 64k, and 256k of context, on an exclusive seat.

Correctness held between 81% and 84% with thinking off, and 88% to 94% with it on. The gap between the two arms is nine to thirteen points, and the depths did not move it. Reasoning got longer at depth, not shorter. Nothing truncated. Decode fell 18% across the range — slower at depth, not worse.

Two honest caveats. The grader only saw the first 600 characters of each answer, so a couple of arithmetic items that buried the final number late were scored as failures when the setup was plainly right. And this is two reps, tested to 256k, not the configured 500k.

## The confident wrong answer was a source problem

The model did not compute a wrong number. It read a fact that was in its context and forgot where it came from.

In one session on the pod, deep in the context — around 160k tokens — the model told me my Mac mini had 24 GB of memory. I do not own a Mac mini.

Before that line, "mac mini" had appeared four times in the context: a search result about a Mac Mini M4, the model's own tool call asking about a "32GB M1 Max Mac Mini", that call's reasoning, and the model's own earlier plan text. The 24 GB figure came from somewhere else entirely — a real memory reading of about 25.8 GB taken from a different machine earlier in the same session. The model fused a true measurement from one machine with a device name that only existed in tool calls and search snippets, then presented the fusion as fact.

Asked the same question with clean context, the model correctly says no Mac mini was mentioned in the text. It does not invent when the context is clean. It merges sources when the context is contaminated. Two turns later it caught itself and admitted the Mac mini was invented.

One session, so this is documented rather than proven general. But the shift is real: once the context gets this big, the failures stop being engine failures and start being contamination failures. The rule is cheap and it works — when a model is confidently wrong, check whether the wrong answer was already sitting in its context. If it was, you are not looking for a reasoning bug. You are looking at where the sources bled together.

## The cliff was in the engine

There is a failure mode that made long context feel like a trap. An earlier run of the same model family on llama.cpp dropped from 33 t/s in the short-context band to 13.5 t/s above 128k, with three minutes to the first token. That shape is not a model running out of room. It is an engine recomputing work it has already done.

Moving to vLLM removed the drop, and the recorded cause was prefix caching: when a request shares a prefix with work the engine has already run, it reuses that work instead of redoing it. That is the measured part. The shape of the drop — concentrated at the top of the window rather than spread evenly — is consistent with recomputation compounding against length, but nothing here isolates that mechanism.

The narrow claim holds anyway: the slowdown that made deep context impractical was an engine behavior, not a model limit.

## What it changed in practice

Prefill is the part where you sit and watch a counter, and until recently the cost of a big context was measured in minutes.

Flash-Next prefilled 300,000 tokens in under four minutes. That is the same time my 27B seat took for 100,000. Three times the context, the same clock. Push the 27B to its ceiling and prefill runs to nearly seventeen minutes of reading a document before it will say a word to you — and its declared window is 228,300, so 300,000 was never reachable there in any case.

Past a certain size, context stops being something you load and becomes something you wait through.

My workflow changed with it. Point a new session at an old one and pick up where it left off. At 300k that prefill is about four minutes. Before, that was not a thing you did; it was a thing you worked around by compacting, summarizing, or refusing to look at the whole thing. Now it is a delay you accept.

Against the seat it replaced: quality roughly equal, decode roughly double, context more than twice as large, and the cost is nothing instead of $2.49 an hour. Pods stopped being a requirement and became a parallel option. Compaction went from a necessity to a choice.

One caveat, stated plainly: the quality comparison came from different harness versions on different days, and the two models are different checkpoints. The speed and the cost are the claims that hold. The quality delta is a direction, not a result.

## Limits

One card, one box, three days in production. The depth probe stopped at 256k on a seat configured for 500k. Two reps per cell. Text only — no tool calls were measured on this seat. The comparison against the seat it replaced used different instruments on different days.

Worth being precise about which seat each finding belongs to: the echo, the dose-response curve and the Mac Mini claim are all from the paid pod. The depth probe, the residency measurements and the prefill numbers are from the local AMD seat. The local engine does render prior reasoning into the prompt regardless of the flag, but in 1,418 turns on it the echo has never collapsed into a stub.

## Where it goes

The shift from Qwen 3.6 to 3.8 carried much of the load on its own — migrating to pi and dropping Claude Code entirely was the larger move, not the model number. What this seat added on top is a steadier window. Compaction became a decision rather than something that had to be done, and it is now under consideration for compacting pod models running in parallel, though that is a later step, not a guarantee.

What survives the checking is architectural. The dense weights stay resident in VRAM. The expert weights and the PLE table do not. That split is the whole trick, and it is a design that fits one machine, not a fleet.

It is not a result you can project onto every GPU. One card was tested. If the RAM handoff behaves differently on Ada, on Intel, or on the previous RDNA generation, I have no evidence for it. I have a guess that the split is architecture-general and should therefore hold. That is a reasonable guess. It is not a measurement, and I will not print it as one.

What I live by now: a self-hosted seat is proven against one card and one model, and every claim about other hardware stays labeled a projection until that machine pays for itself on its own bill.

This is one seat on one card, and it is early. Large MoEs on consumer hardware are not settled yet — the quant ladder, the effort curve, and what actually breaks at 500k are still ahead of me. More measurements as I take them. The RSS is there if you want it.

## The effort, honestly

Coordinator: 62 prompts, 659 messages, ~17.5M tokens, across a session that ran about 27 hours end to end.

Writers: four models tried — Orion 26B, ornith-1.5-35B, A3B 35B, and Gemma 4. Roughly 18 runs, 14 of them productive. Two failed before the model was ever consulted because a serving door had idle-shut down; one produced a confident review of quotes that were not in the draft.

The section-by-section drafting is what made the difference. Handed the whole evidence packet, the writer seats dropped sections and invented numbers. Handed one claim and one evidence list, they wrote clean sentences.

<p class="harness-meter"><span style="color:var(--accent)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><circle cx="7" cy="4.2" r="2.9" fill="currentColor"/><path d="M1.8 13.2c.5-3.4 2.6-5 5.2-5s4.7 1.6 5.2 5z" fill="currentColor"/></svg></span> 2,091 words · 62 prompts <span class="sep">||</span> <span style="color:var(--gold)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><rect x="2.4" y="4.6" width="9.2" height="7.4" rx="1.8" fill="currentColor"/><line x1="7" y1="4.6" x2="7" y2="2.6" stroke="currentColor" stroke-width="1.1"/><circle cx="7" cy="2" r="1" fill="currentColor"/><circle cx="5.3" cy="8.3" r="1.1" fill="var(--paper)"/><circle cx="8.7" cy="8.3" r="1.1" fill="var(--paper)"/></svg></span> 659 messages · ~17.5M tokens <span class="sep">||</span> <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" style="color:var(--ink);opacity:.7"><circle cx="7" cy="7" r="5.4" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M7 3.9V7l2.3 1.5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg> ~27 hours</p>
