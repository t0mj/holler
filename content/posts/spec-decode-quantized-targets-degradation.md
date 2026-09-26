---
title: "Turning on a speed feature dropped my hard-reasoning scores from 39/40 to 0/40"
subtitle: "Draft-MTP speculative decoding on quantized targets: a silent quality trap"
date: 2026-09-16
draft: false
tags: [llama.cpp, speculative-decoding, quantization, quality-evaluation]
summary: "An A/B test reveals that enabling draft-MTP speculative decoding on a Q4_K_M 27B model silently collapses long-chain reasoning performance, matching an upstream bug class."
crossposts: []
---

## TL;DR

- **Finding:** Enabling `draft-mtp` speculative decoding on a Q4_K_M quantized 27B model caused a silent, systematic collapse in long-reasoning performance. Short-answer tasks were unaffected.
- **Numbers:** On the two hardest reasoning blocks (40 items each), every one went to **0/40** under spec-ON: fix block 39/40 (gate) and 38/40 (fine-tune) at spec-OFF; implement block 27/40 and 29/40 at spec-OFF. Overall mean score dropped from ~0.88 to ~0.70.
- **Setup:** 27B models (Qwen3.8-27B and a GRPO fine-tune), Q4_K_M quantization, 24GB Radeon RX 7900 XTX (RDNA3), Vulkan backend, llama.cpp build `47c7869`.
- **Caveat:** This is a correlation with a known upstream bug class (#25618). The isolation test (running on a non-quantized target) was infeasible due to memory constraints, so the mechanism is consistent with but not yet proven by an isolation test.

## The Setup

I run a local inference stack on a single 24GB Radeon RX 7900 XTX. The hardware is RDNA3, accessed via the Vulkan backend in llama.cpp. The specific build I used for these tests is `47c7869`.

The models were two 27B-class weights, both quantized to Q4_K_M. The first was `Qwen3.8-27B`, used as a gate. The second was `Smaug-Mini`, a GRPO agentic fine-tune of the same base, released roughly one week before the runs. Both models had an MTP (Multi-Token Prediction) head; one was trained, the other inherited from the base.

The evaluation suite consisted of 364 items, organized into 8 blocks across 4 effort levels. The suite was seeded, and both runs (spec-ON and spec-OFF) completed with zero errors. The harness was md5-identical across machines, and the llama.cpp build was the same for both states. The only variable changed was the speculative decoding path.

The KV cache was quantized to q4_0. Flash-attention was enabled, though public data suggests it offers no speed win on RDNA3; I kept it for the ~7% memory savings. These settings were held constant across both runs.

## The A/B Test

The test was a direct comparison: the same models, the same suite, the same hardware, the same build. The only difference was whether `draft-mtp` speculative decoding was enabled.

**Speculative Decoding OFF:**

| Model | Mean Score | Pass Count | Fix Block (40 items) | Implement Block (40 items) |
|---|---|---|---|---|
| Gate (Qwen3.8-27B) | 0.882 | 308/364 | 39/40 | 27/40 |
| Fine-tune (Smaug-Mini) | 0.885 | 312/364 | 38/40 | 29/40 |

**Speculative Decoding ON (draft-mtp):**

| Model | Mean Score | Pass Count | Fix Block (40 items) | Implement Block (40 items) |
|---|---|---|---|---|
| Gate (Qwen3.8-27B) | 0.704 | 246/364 | 0/40 | 0/40 |
| Fine-tune (Smaug-Mini) | 0.700 | 248/364 | 0/40 | 0/40 |

The drop is not uniform. The "fix" and "implement" blocks are the longest-reasoning-chain items in the suite. Under spec-OFF, both models scored near ceiling on these blocks (38–39/40). Under spec-ON, both models scored 0/40 on both blocks.

The short-answer blocks were unaffected. The "ifw" and "knowledge" blocks scored 10/10 in both states. The "agentic" block scored 14/15 in both states. The degradation was specific to the long-chain reasoning items.

## The Control

To rule out grader drift or harness instability, I included a control block: "review." Both models perform poorly on this block regardless of the spec-decode state.

- **Gate:** 14/40 in both spec-OFF and spec-ON runs.
- **Fine-tune:** 13/40 in both spec-OFF and spec-ON runs.

The control block remained stable. This suggests the grader and harness were not drifting between runs. The only variable that changed was the spec-decode path, and the only blocks that changed score were the long-reasoning ones.

## The Nature of the Failure

The failure was silent. There were no crashes. The output was not empty, not looping, and not truncated. Many responses stopped naturally. The battery marked them as wrong, but I did not read all of them in detail.

The scores collapsed, but the qualitative nature of the errors is not fully characterized. Did the model hallucinate facts? Did it fail to follow instructions? Did it produce plausible-looking but logically broken chains? Without a detailed qualitative review, I can only say that the output was well-formed but systematically wrong on the hard items.

This is the dangerous class of failure: the feature "worked." The tokens generated, the process ran, the throughput numbers looked plausible. The only signal was the quality battery. If you don't run a quality battery, you might never notice.

## Upstream Context

This behavior maps directly to an open issue in `ggml-org/llama.cpp`: **#25618**.

The issue describes a scenario where, under greedy sampling (temperature=0, top_k=1), draft-model speculative decoding can produce different text than a non-speculative run when the target is quantized (e.g. Q4_K_M). The same setups match on a bf16 target. This contradicts the expected property that speculative decoding is lossless for greedy decode.

The issue notes that the mismatch has been reproduced on Vulkan/AMD, and others have reported similar mismatches on CUDA. Ngram speculation reportedly stays lossless on the same quantized targets. Draft-MTP is explicitly in scope.

My case matches on the three variables the issue names:

- Target quantization: Q4_K_M
- Speculative decoding type: draft-mtp
- Backend: Vulkan/AMD

The upstream demonstration was under greedy decoding — the strongest case for the losslessness claim. Mine was stochastic (temperature 1.0), where the guarantee is even looser.

There are related reports in the same bug class, but they are analogous, not confirmatory of the specific RDNA3 mechanism:

- **#25908:** Vulkan/RDNA4 spec-decode acceptance collapse with `p_min 0.0` (my exact flag value).
- **#23752:** Metal: MTP spec-decode up to 28% slower with correct output (the speed side of the same story).

As far as I could find in the issue tracker, my measured impact (~18 mean points; two models; 0/40 → 38–39/40 on the hard blocks) is the largest reported so far in this class.

## Why It Matters

The trap here is that the feature appeared to work. No errors, no crashes, fluent text. The only signal was a quality battery, which most people never run.

The vendor's own card for the fine-tune said "leave MTP spec decode off," citing the mechanism as "inherited MTP head, not retrained." The warning was directionally right, but the mechanism was wrong. The model with the *trained* MTP head was affected identically. Per the upstream issue, the real variable is the combination of **quantized target** and **spec path**.

There is an irony: the spec-decode path is lossless on bf16 targets. But a bf16 27B model (~54GB) cannot fit on a 24GB card. The quantization that allows the model to fit is precisely what breaks the speed trick.

I had "verified" spec-decode in production a week earlier by checking that the config was set and the process was running. A check that reports success while the feature is quietly harmful is the dangerous class.

I audited related settings while in there. The KV cache was q4_0-quantized. Community practice runs q8_0 as the safe middle, but full precision likely cannot fit at my 185k context on 24GB. A targeted probe is pending. Input contamination was audited and ruled out: shared KV slots used exact-match prefix reuse, and `n_keep=0`.

## Mechanism Honesty

The spec-ON state correlates with hard-item collapse on quantized targets. The mechanism is consistent with the upstream issue #25618, but it is not yet demonstrated by an isolation test.

The isolation test would be to run the same setup with a non-quantized (bf16) target. If the degradation disappears at bf16, the quantized-target hypothesis is confirmed. If the degradation persists at bf16, the spec-decode path itself is suspect.

However, a bf16 27B model requires ~54GB of VRAM. My card has 24GB. The isolation test is infeasible on my hardware. This infeasibility is itself part of the story: the very constraint that forces quantization (memory) is the variable that triggers the bug, and the test that would prove the bug is impossible to run on the hardware that exhibits it.

## Independent Corroboration — Same Trap Class, Different Hardware

While writing this up I found a separate community investigation pointing the same direction from a different axis. The author (thc1006) ran a 19-configuration matrix of llama.cpp speculative decoding — ngram-cache, ngram-mod, and draft models at various depths — on Qwen3.6-35B-A3B (a small-active-param MoE) on an RTX 3090. Result: **every configuration was 39–60% slower than plain autoregressive decode**, even when draft acceptance hit 100%. The work is rigorous in the way mine tries to be: jitter re-runs, KV-format controls, replication on a second machine, and cross-hardware checks (2×3090, A100 NVLink, H200), with raw JSON and scripts published ([write-up](https://hackmd.io/ODXuOQNzSiyUITz7g9mtBw)).

Two notes on how far this corroboration goes:

1. Their axis is **speed**, mine is **quality**, and their target is MoE while mine is dense. What they independently confirm is the class claim — *speculative decoding defaults on local, constrained targets are unsafe* — not my specific 0/40 collapse, which remains a single-box result at a specific build. Nobody has yet reproduced the quality collapse off-AMD.
2. Their study contains a counterexample against a blanket "spec decode bad" reading: **vLLM with MTP on the same 2×3090 hardware was +27.5% faster**, provided prefix-caching was disabled to avoid a separate cache-hit-rate bug. My own follow-up (a community fine-tune that keeps both quality and 76.8 t/s under spec-ON) lands the same way: the finding is *this path, on these targets, in these builds*. Speculative decoding as a technique survives the week; my default config did not.

The combined picture, for anyone serving locally: the stock "fast" configuration is the one thing in your stack that changes what your model can do, and the engines disagree with each other about whether the feature is even net-positive. Bench quality with the feature on before you trust the speed you just bought.

## A Grain of Salt

This is an n=1 result on a specific hardware configuration (RDNA3, 24GB, Vulkan) and a specific llama.cpp build (`47c7869`). The models were 27B-class, quantized to Q4_K_M. The suite was 364 items, seeded, with zero errors.

The "silent" nature of the failure is based on the absence of crashes and the fact that the output was not empty or looping. I did not perform a detailed qualitative analysis of every wrong answer. The claim that the output was "plausible-looking" is an inference from the scores and the absence of obvious degenerate patterns, not a proven fact.

The upstream issue #25618 is a strong prior, but a prior is not a proof. The correlation is tight, and the control block rules out grader drift, but the mechanism is not fully isolated.

If you are running draft-mtp speculative decoding on quantized targets on a non-CUDA backend, I would recommend running a quality battery before trusting the output.

<p class="harness-meter">1,773 words · 15 prompts || 89 messages · ~6.9M tokens || ~0.7 hours</p>
