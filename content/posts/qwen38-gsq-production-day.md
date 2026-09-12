---
title: "The 3-bit model ran all day. It didn't break. But it kept trying to edit the same broken line."
subtitle: "One full day of production traffic on a 24 GB 7900 XTX, with two quantized Qwen3.8-27B models side by side."
date: 2026-09-07
draft: false
tags: [llama.cpp, qwen, quantization, llama-swap, amd]
summary: "After a week of benching, the 3-bit quant finally carried real traffic — and its quirks were weirder than the numbers suggested."
crossposts: []
---

## TL;DR

- Follow-up to [the quant comparison post](/holler/posts/qwen38-xtx-quant-comparison/): the 3-bit GSQ-RCO IQ3_S (+MTP head) ran **a full day of real agent traffic** on my 24 GB 7900 XTX, side by side with its 4-bit Q4_K_M sibling — 294 requests / 228,371 output tokens against the 4-bit's 504 / 559,963, for 795,364 output tokens across the box.
- **Decode held.** Per-request decode p50 47.3 vs 44.9 t/s, p90 tied (73.1 vs 72.5), spec-decode acceptance 60% vs 62%. The 3-bit is not slower where the wall-clock goes.
- **Prefill paid — and it's the only real delta.** On the day's cache-heavy mix, prefill p50 128 vs 174 t/s; at a clean 241,776-token fresh prefill the two are tied (239.8 vs 242.3).
- The number that won't go away isn't in any log: when an edit failed, the 3-bit **kept retrying the same broken edit** — several times, more than any other model I run. Unmeasured, quantization-adjacent, and the reason I still don't trust it with my important systems.

## The setup

The box didn't blink once today. No restarts, no OOMs — just the two models, Q4_K_M and the 3-bit IQ3_S, humming in their lanes on 24 GB of VRAM, swapped back and forth by llama-swap v253: Arch Linux, llama.cpp Vulkan build b9999 (commit `47c7869`), q4_0 KV cache, flash attention, 16 threads, draft-mtp spec-decode on both entries. The 4-bit — "the gate" — handled my daily coding-agent sessions at a 185k pinned context. The 3-bit — "the long-context runner" — took the 200k-class jobs, with the full 262k pool resident (17.97 GiB peak vs 22.04 for the 4-bit, 6 GiB of headroom at a 241k prefill). Both entries, same flags, same box: [the quant comparison post](/holler/posts/qwen38-xtx-quant-comparison/) is where they came from.

It was the first full day the 3-bit ever did.

I didn't expect it to work. Not because the numbers said no — they said the opposite. The 3-bit file fits. The KV pool is 262k tokens, fully resident. Six gigabytes of headroom. I knew that from the bench. But knowing a thing and letting it run on your actual work is different.

## The cold-start cancels

The 3-bit's first requests of the day came right after a cold load. The session's context had to be re-prefilled from scratch — and on this box, a full ~240k-token fresh prefill takes about **16.6 minutes** (bench number from the first post: 997.7 s TTFT on the 4-bit, 1,008.2 s on the 3-bit). Nobody's client waits that long. The proxy log shows four client cancels (HTTP 499) in the following hours, after 3 s, 300 s, 300 s, and 72 s of waiting — three of them clustered right after that cold start. The clients were my own agent sessions, not a load test.

I didn't fix it. The next requests came through fine, because by then the KV cache was warm and "prefill" meant a few thousand fresh tokens instead of 240k. That's the whole economics of a 262k-capable box: warm sessions are nearly free, and a cold start after a TTL eviction re-pays the entire session's context. (What happens when a cold spawn lands wrong has [its own post](/holler/posts/xtx-cpu-fallback-incident/).)

## The numbers that held

The 3-bit did 294 requests that day. 228,371 output tokens. 26,067,542 of its prompt tokens came from the KV cache — 95.8%, the same shape as the 4-bit's 95.5%. Decode: 47.3 t/s p50, 73.1 p90, spec-decode accepting 60% of drafted tokens. The 4-bit: 44.9 p50, 72.5 p90, 62% acceptance. The numbers are too close to matter.

Prefill is where the day's one real delta lives: 128.4 t/s p50 for the 3-bit, 174.1 for the 4-bit — a 26% tax. And the bench curve says where it lives:

| prompt tokens (fresh) | 4-bit pp / tg | 3-bit pp / tg |
| --- | --- | --- |
| 99,475 | 420.0 / 46.0 | 409.4 / 45.6 |
| 224,109 | 256.0 / 28.5 | 253.5 / 29.3 |
| 241,776 | 242.3 / 25.9 | 239.8 / 22.9 |

(pp = prefill t/s, tg = generation t/s; 2026-09-05 bench, thinking off, fresh server per run.) At a clean 241k fresh prefill the two are tied — so the gap is not the long game. It's the day's traffic shape: with 95–96% of prompt tokens served from cache, most of a request's prefill is a small fresh tail over a huge warm KV, and a 3-bit group-scaled format costs something on exactly that path. That's my read of the mix, not an isolated measurement — the point stands either way: if your jobs are cold-prefill-heavy, the 4-bit buys ~35% prefill speed. If your jobs are warm-session-heavy, the tax is small and the 4 GiB the 3-bit frees is worth more than it.

## The broken line

My agent uses an edit plugin — pi's "hashline" — that finds lines in files by hash anchor, not by line number. Sometimes it fails. The model misreads the context, writes the wrong thing, the edit lands broken. I've seen it occasionally on every model I run.

But on the 3-bit it happened *differently*. It didn't just fail once. It failed, tried again, failed again — the same broken edit, the same retry, three, sometimes four times in a row. The 4-bit fails once and moves on. The 3-bit is stubborn. It doesn't learn from the failure.

I don't know why. There's no metric for it — no token count, no latency spike, no acceptance rate. It's a vibe, and it's the one part of the day that didn't come from a log. I eventually removed the plugin from my workflow, because other sessions failed once in a while too — but the 3-bit stuck out loud enough that I remember which one it was.

And that's why I'm still not running the 3-bit on my own memory system. I run my agent at medium thinking on this model ([the thinking-levels grid](/holler/posts/qwen38-thinking-levels/) is why), and even at medium thinking the model has to remember what it did five turns ago, track what file it's editing, know which function it's modifying. That's important work, and I'm not sure I trust the 3-bit with it. Not yet. I've never compared the two quants side by side on a fixed set of prompts under the same sampling profile. There's a small quality battery in design — fixed task set, the model's production sampling profile as the default arm — but the build is on hold. I keep telling myself I'll run it tomorrow.

I'm not sure why. The numbers say it's fine. The VRAM is better. The speed is the same. And I keep defaulting to the 4-bit. I'm afraid it'll be wrong in a way I can't measure. I'm not sure if that's rational. I'm not sure it isn't bias.

## The log that died four times

Yesterday, the box did blink — four times, all OOM-killed: the 230k-token boundary probe dying mid-prefill at ~191k tokens, and a 12-model verification burst that pushed the kernel's commit budget to its limit. Each restart wiped the usage log, because it lives in memory. I lost ~150 requests' worth of numbers — I have the counts, not the tokens. What survived after the last restart: 112 requests on the 4-bit, decode p50 78.5, a lighter mix than today.

Today, the box didn't die. 504 requests on the 4-bit, 294 on the 3-bit, and 26 on a 27B fine-tune — 795,364 output tokens across the three. But I still feel like I'm testing the 3-bit on a live wire.

I'll do more real work on it soon — including on the systems I'd normally trust the 4-bit with. If it breaks, I'll write another post. If it doesn't, I'll still be a little nervous.

## A grain of salt

One box, one engine build, one model family, two quants — and for the 3-bit, one full production day plus the bench data from the first post. The per-request p50/p90 figures are over mixed request shapes (the two models took different traffic mixes by design — the 4-bit the working sessions, the 3-bit the long jobs), so it's a fair same-day comparison, not a controlled A/B. The prefill-gap mechanism is my read of the cache mix, not an isolated measurement. The hashline retry behavior is a lived impression with no measurement behind it — possibly quantization, possibly the MTP head, possibly the traffic. And no quality battery has run on either file yet; if the 3-bit deviates, this post gets a corrections note.

If you're running 3-bit quants in real traffic, I'd genuinely like to know what your experience is — especially with edit-heavy agent work. Is the retry-loop behavior normal at 3 bits, or am I seeing a real quality gap?

## The effort, honestly

Single-author, single-model: the coordinator that gathered the day of metrics, ran the identifier sweep, and wrote the draft is the same local 27B — no external writers on this one. Measured from the session records at time of writing (the session spans a couple of days and sat idle between work, so wall time is not active time):

- **The coordinator** — the local 27B: 73 messages, 87 tool calls, ~7.9M tokens (cumulative, heavy re-reads of the serve logs), ~3 hours of active model time.

<p class="harness-meter"><span style="color:var(--accent)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><circle cx="7" cy="4.2" r="2.9" fill="currentColor"/><path d="M1.8 13.2c.5-3.4 2.6-5 5.2-5s4.7 1.6 5.2 5z" fill="currentColor"/></svg></span> ~1,555 words · 4 prompts <span class="sep">||</span> <span style="color:var(--gold)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><rect x="2.4" y="4.6" width="9.2" height="7.4" rx="1.8" fill="currentColor"/><line x1="7" y1="4.6" x2="7" y2="2.6" stroke="currentColor" stroke-width="1.1"/><circle cx="7" cy="2" r="1" fill="currentColor"/><circle cx="5.3" cy="8.3" r="1.1" fill="var(--paper)"/><circle cx="8.7" cy="8.3" r="1.1" fill="var(--paper)"/></svg></span> 73 messages · ~7.9M tokens <span class="sep">||</span> <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" style="color:var(--ink);opacity:.7"><circle cx="7" cy="7" r="5.4" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M7 3.9V7l2.3 1.5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg> ~3 hours active</p>
