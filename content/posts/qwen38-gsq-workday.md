---
title: "The GSQ 3-bit that carried four hundred thousand tokens"
subtitle: "Context capacity isn't a speed upgrade — it's a patience tax."
date: 2026-09-10
draft: false
tags: [llama.cpp, qwen, quantization, gsq, llama-swap, amd, coding-agent]
summary: "One working day running the GSQ-RCO 3-bit quant of Qwen3.8-27B as the daily coding agent across eight sessions: decode held, prefill paid, five sessions overflowed the box's cram budget, and the honest verdict — not a step down, a little looser, and I'm reverting to the 4-bit tomorrow."
crossposts: []
---

## TL;DR

- **Carried ~453k tokens at once** — five sessions resident at one point; no crash, but the combined context overflowed the box's budget and everything slowed drastically.
- **Prefill is the cost** — a fresh ~240k prefill after a TTL eviction takes ~16.6 min; the first production day logged four client cancels (HTTP 499) — three of them clustered right after one cold start.
- **Decode: no penalty** — 47.3 vs 44.9 t/s p50, p90 tied, spec-decode acceptance 60% vs 62% against the 4-bit.
- **Reverting to the 4-bit tomorrow** — not because the 3-bit failed, but because the waiting is the real cost.

> *What GSQ is: non-uniform quantizations from the Deep Algorithms and Systems Lab at IST Austria. GSQ (Gumbel-Softmax quantization) learns the grid and scales for each tensor; RCO then assigns a different quantization type to each tensor under an exact size budget. The IQ3_S file I run is their "task-lossless" operating point — 3.50 bits per weight, matching the base model exactly on AIME25 and LiveCodeBench v6 at about a fifth of the BF16 size. ([model card](https://huggingface.co/ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF))*

I ran Qwen3.8-27B in the GSQ-RCO IQ3_S quant (3-bit) as my daily coding agent for one working day. Same box as the 4-bit: 24 GB RX 7900 XTX, Arch Linux, llama-swap v253, llama.cpp `b9999` Vulkan build (`47c7869`), q4_0 KV cache, flash attention, draft-mtp speculative decode (`--spec-draft-n-max 3`). The file is 11.29 GiB, and its full 262,144-token context pool sits entirely in VRAM — 17.97 GiB peak measured under day-one production traffic, about 4 GiB back of the 4-bit's 22.04 GiB peak under the same traffic (15.64 GiB file, pinned at 185,000 context after its OOM boundary probe at ~191k).

I didn't switch for speed. I switched for headroom. The 4-bit's 185k cap kept compacting my sessions more often than I liked, and the 3-bit's 262k pool was already in the box. I wanted to see what happens when the daily driver gets more room.

## The verdict

I went in half-skeptical. The 4-bit is the model I trust with important systems; the 3-bit was the long-context runner. One day of real work was supposed to tell me where the 3-bit actually sits.

I didn't feel like I was using a worse model. I felt like I was using a looser one — like my doppelgänger but something different, and you can't quite put your finger on it. The outward expression is looser; the work results aren't. And I respect that.

It seemed to use the todo list better — updating it and inserting new items as it went. Unsure why. It just stood out. (And the session writing this post ran on the 3-bit itself — and it never opened a single todo list. The tool was there the whole time; a proof I ran that indicates this was likely just vibes.)

Handled everything thrown at it, across very different types of coding — one JS web app and local infrastructure.

Most likely it's my own personal bias of working with a 3-bit I quant, making me doubt more than anything. Who knew I had a quant preference?

I've upped the keep-alive to an hour to keep the model resident, and with higher-context windows that's working against me now, too.

Early on: weary. Mid-day: impressed, genuinely wondering what I'm worried about. End of day — Sick. Of. Waiting. On. Prefill…

I don't normally find myself with extra time to type blog feelings. So I've either become extra efficient, or I'm waiting on water to boil, watching prefill spin.

I didn't need the 3-bit to be faster. I needed it to hold more. It did. But the cost isn't in VRAM.

It's in minutes.

## The day

Eight sessions. Three projects. One model file that had never been my daily driver before.

One JavaScript project — a two-pane fullscreen terminal front for my coding agent. Local-infra work: reviewing and fixing a bug a smaller session had found on a laptop inference box, a model-installer refactor, a llama-swap token-log review, a pass over recent package updates. And blog drafts: a style review of a draft post, and drafting for a trading app.

Day totals, 3-bit only: **267 assistant turns, 8.37M input tokens, 248k output tokens, 293 tool calls, 29 tool failures (~10%).**

The biggest single session ran 117 turns over ~13 hours, peaking at ~171k tokens of context — and it never compacted once. The peak single context of the day was **247,116 tokens**: a long-running infra session, revived by a background monitor.

At one point, five live sessions were holding context at the same time — the three biggest at 124,665 + 120,947 + 111,148 (~357k), plus two blog sessions at 58,649 and 37,331. About **453k tokens across five windows.** The combined context overflowed the box's `-cram` budget — I'd raised it from 24 GB to 40, maybe 42 now — and everything slowed drastically until the contexts drained; sometimes it needed a restart. A session-gating extension had been keeping the concurrency down all week; the revival storm is what broke through it.

The tool failures were the usual flotsam of exploration: a handful of edit-tool rejections (stale anchors, malformed replace ops), a run of self-inflicted syntax errors iterating on macOS automation scripts, two browser/PATH misses. The todo tool, meanwhile: 60 uses across the week, zero failures.

## What the day cost

Three things, and they share a root: the context is bigger, so everything that touches it is slower.

**Cold prefill.** After a TTL eviction, a fresh ~240k-token prefill takes about **16.6 minutes** — the bench from [the first post](/holler/posts/qwen38-xtx-quant-comparison/) puts time-to-first-token at 1,008 s on the 3-bit. Nobody's client waits that long: the first production day logged four client cancels (HTTP 499) — three of them clustered right after one cold start.

**Compactions.** Raising the cap did not remove compaction — it made each one heavier. Nine compactions across the 3-bit's sessions over the week, one that day; the 117-turn session compacted zero times. A summarized 250k context takes longer to summarize than a 185k one. Both things are true at once: the smaller cap compacts more often, and each big one costs more.

**The ~453k moment.** This is the one you can't plan around. Background monitors revive old sessions, the gate lets another through, and suddenly half a million tokens are resident across five windows, past the `-cram` budget. The 3-bit's whole advantage — it fits more context — is exactly what makes this worse, because the compaction of that context takes longer too.

## The numbers that held

Measured against the 4-bit, same box, same week:

| | 4-bit (Q4_K_M) | 3-bit (IQ3_S) |
| --- | ---: | ---: |
| decode p50 / p90 (t/s) | 44.9 / 72.5 | 47.3 / 73.1 |
| prefill p50, cache-heavy mix (t/s) | 174.1 | 128.4 |
| prefill, fresh 241,776 tokens (t/s) | 242.3 | 239.8 |
| spec-decode acceptance | 62% | 60% |

Decode is a wash. Prefill carries the 3-bit's dequant tax on a warm-cache mix — 26% on the day's mix — and vanishes at a clean fresh prefill. Week-long usage from the session logs (Sept 7–10):

| | 4-bit (local) | 3-bit (local) | 8-bit (rented H100) |
| --- | ---: | ---: | ---: |
| assistant turns | 2,775 | 665 | 6,242 |
| input tokens | 106.6M | 12.0M | 800M |
| tool-failure rate | 6.2% | 7.5% | 7.8% |
| average peak context | 81.3k | 129.8k | 129.3k |

The 3-bit sessions ran hotter — 129.8k average peak against the 4-bit's 81.3k — because the cap lets them. The 8-bit is the same model at FP8 on a rented H100 NVL (94 GB), vLLM, $3.19/hr: single-stream decode p50 51.6 t/s, 4-way concurrent 105.7 (the previous A100 fell to 66.1), prefill p90 933 t/s, about $17.4 per million output tokens. That's a 2.5-hour slice — a first impression, not a baseline — and it's the one I reach for when three sessions need the model at once.

## The plan

Tomorrow I go back to the 4-bit at 185k, lower the context, and see how the revert feels — for everything else, the 4-bit is the safer default. The 3-bit keeps the singular long-context jobs, 200k-class, where it's pretty great. The 8-bit stays on demand for concurrent bursts.

## A grain of salt

n=1: one box, one working day, one quant, agent-mode only, speculative decoding on. The 16.6-minute cold start is a bench number from the first post, not this day's log. The ~453k concurrent moment depends on which sessions the monitors happen to revive — the least reproducible part. The H100 comparison is a 2.5-hour slice. And the subjective read is mine, with a self-acknowledged quant bias.

If you've run a 3-bit 27B as a daily coding agent — or measured cold-start and concurrent-context behavior on a fixed-VRAM box — I'd genuinely like to know what a healthy number looks like.

Related: [the first production day](/holler/posts/qwen38-gsq-production-day/) · [the quant A/B this post follows](/holler/posts/qwen38-xtx-quant-comparison/) · [the CPU-fallback incident](/holler/posts/xtx-cpu-fallback-incident/) · [the thinking-levels grid](/holler/posts/qwen38-thinking-levels/)

## The effort, honestly

This post was written by the model it reviews. The forensics, the brief, the merge, and the number-verification all ran on the 3-bit itself — the thing under review — while three models on a 64 GB inference laptop each drafted from the same brief. Measured from the session records at time of writing:

- **The coordinator** — the 3-bit (the GSQ-RCO IQ3_S itself): 61 turns, 62 tool calls, ~2.7M tokens, about an hour of active time (the session sat idle between work).
- **The writers** — three local models on one laptop, one identical brief each: an 80B (Qwen3-Next-80B-A3B), a 9B (ornith-9b), and a 26B MoE (Gemma 4, QAT at Q4_K_XL): 3 calls, 15,263 tokens, ~13 minutes summed, first loads included.

The cross-check is the point. The 80B had the best voice and invented a few details — a made-up GPU utilization figure, a false "measured three times" — that the merge had to cut. The other two drafts got every number right. No draft goes to the log unchecked.

<p class="harness-meter"><span style="color:var(--accent)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><circle cx="7" cy="4.2" r="2.9" fill="currentColor"/><path d="M1.8 13.2c.5-3.4 2.6-5 5.2-5s4.7 1.6 5.2 5z" fill="currentColor"/></svg></span> 1,676 words · 5 prompts <span class="sep">||</span> <span style="color:var(--gold)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><rect x="2.4" y="4.6" width="9.2" height="7.4" rx="1.8" fill="currentColor"/><line x1="7" y1="4.6" x2="7" y2="2.6" stroke="currentColor" stroke-width="1.1"/><circle cx="7" cy="2" r="1" fill="currentColor"/><circle cx="5.3" cy="8.3" r="1.1" fill="var(--paper)"/><circle cx="8.7" cy="8.3" r="1.1" fill="var(--paper)"/></svg></span> 66 messages · ~2.7M tokens <span class="sep">||</span> <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" style="color:var(--ink);opacity:.7"><circle cx="7" cy="7" r="5.4" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M7 3.9V7l2.3 1.5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg> ~1 hour</p>
