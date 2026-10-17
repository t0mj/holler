---
title: "My image model grew a watermelon instead of a pb&j"
subtitle: "A quantization A/B that flipped what an image is about, a blinded re-score that withdrew the verdict, and a reasoning pass that turned out to be a gate"
date: 2026-09-20
draft: false
tags: [image-generation, qwen-image, quantization, stable-diffusion.cpp, amd]
summary: "Qwen-Image-2.1's Q4_0 build grew a watermelon out of a sandwich prompt. Blinding showed the seed was the real lever, and a 9B refine pass scored 8/8 where a neutral one scored 4/8."
crossposts: []
---

## TL;DR

- **Meaning changed, then didn't.** At a fixed seed, the Q4_0 build of Qwen-Image-2.1 grew a slice of watermelon out of a tentacle where the sandwich belongs, and the Q6_K build kept the bread and jam. A blinded 3-seed × 2-quant grid showed the composition tracks the *seed*, not the quant — so the watermelon is real and the quant verdict is not.
- **The seed is the lever.** On an 8-point rubric, seed choice moved fidelity 2–3 points for free. A 1.4×-heavier DiT (4.2 → 6.0 GB) bought about a point at best and cost +9–11% wall time (78.1 → 87.0 s at 1024², 229.7 → 251.0 s at 1536²), +1.7 GiB peak VRAM (11.86 → 13.53 GiB), and 6 GB of weights.
- **A gate, not a multiplier.** The same prompt, refined four ways by ornith-9b and scored blind: explicit instruction 8/8/8, soft guidance 6/6/6, raw 5/5/7, neutral 4/4/4 — worse than doing nothing.
- **The method is the finding.** Four confident readings from the first pass did not survive their own checks: a banding metric that found blank sky, a typography pair with an unreadable sign, a "steps are nearly free" reading that was the server ignoring steps, and a single-pair fidelity impression that blinding dissolved.

## Setup

One box: a 24 GB RX 7900 XTX, Vulkan (RADV), running stable-diffusion.cpp at commit `c678dfe` with flash attention and VAE tiling on. Weights: Qwen-Image-2.1's Q4_0 diffusion transformer (4.2 GB) and, for the quality arm, Q6_K (6.0 GB), plus a Qwen3-VL-8B text encoder and a bf16 VAE. The refine arms ran on ornith-9b, a dense 9B model, on a second box. Protocol for the matched A/B cells: prompt verbatim unless stated otherwise, 20 steps, cfg 6.0, euler, card exclusive, per-cell VRAM sampling. The size-cap probe ran 8 steps unless a row says otherwise. Every image in this post was generated with Qwen-Image-2.1 (Qwen Research License, non-commercial).

The prompt, exactly as typed: "a cartoon octopus in the real world tattooing a pb&j on one of its arms while at the beach."

![Figure 1. Left: the raw prompt at Q4_0, 1536², seed 42 — a slice of watermelon grows out of the tentacle where the sandwich belongs. Right: same weights, same prompt meaning, with a 9B model rewriting the sentence first — scored 8/8 blind at 1024², seed 7. Same quant; the ceiling moved upstream.](/img/watermelon-quant/figure-1.png)

## The watermelon

The matched-seed pair at 1536² (seed 42, both quants, everything else identical) is where it got weird. The two files are not a texture difference: mean pixel difference 45.5 on a 0–255 scale, with 69% of pixels differing by more than 10. That is a composition change. And in this pair, the Q4_0 file grew a watermelon.

The scene and the action are right: an octopus at a beach, machine in hand, tattooing. But where the sandwich should be, a slice of watermelon grows out of the tentacle. The composition changed, not the grain — that is not banding or blur. Whether the weight change did it is the next section's question, answered by taking the quant away.

One pair, one seed. That is worth an observation, not a verdict.

## The honest turn: it was the seed

Three seeds (7, 42, 123) times two quants at 1024², six renders pasted into a sheet under shuffled IDs, the mapping unread until after scoring. The rubric is 8 points: sandwich identifiable, octopus operates the machine, the mark lands on its own arm, beach setting.

| DiT quant | seed 7 | seed 42 | seed 123 | mean |
|---|---|---|---|---|
| Q4_0 | 5 (tattoo-class) | 5 (tattoo-class) | 7 (agent-class) | 5.7/8 |
| Q6_K | 5 (tattoo-class) | 7 (agent-class) | 8 (agent-class) | 6.7/8 |

Two interpretation classes showed up. Agent-class: a real octopus at a beach doing the tattooing. Tattoo-class: the whole scene rendered as a tattoo artwork on a human limb, which fails "octopus … at the beach" as a scene.

The class tracks the seed: seed 7 produced the tattoo misread under both quants, seed 123 produced the agent under both, and seed 42 was the only cell where the class itself flipped — tattoo under Q4_0, agent under Q6_K. The other seed-123 cell is a one-point difference inside the same class; two cells favour the heavier quant, one of them by a class flip, and that is not a signal.

The initial impression — bigger quant, more faithful — is withdrawn.

What survives is a transferable rule: on this model, iterate seeds before weights or prompt rewrites. A seed moves the rubric 2–3 points and flips the entire composition for free. A 1.4×-heavier DiT buys about a point, costs 9–11% wall and 1.7 GiB of VRAM, and breaks same-seed comparisons — the same seed under a different quant is a different composition. Pin the quant as well as the seed.

## The reasoning layer

The prompt carries a real ambiguity: "tattooing a pb&j on one of its arms" — is the sandwich the artwork being inked, or the object receiving the needle? The test: hand the verbatim prompt to the ornith-9b refiner, ask it to refine, render the result unmodified at the same three seeds, and score blind. Four arms.

| arm | instruction to the refiner | refined length | seeds 7/42/123 | mean |
|---|---|---|---|---|
| raw | none | 77 chars | 5, 5, 7 | 5.67/8 |
| soft-guided | block the human-limb misread, keep the object identifiable | 528 chars | 6, 6, 6 | 6.00/8 |
| explicit | needle on its own tentacle; the sandwich is the design being inked | 581 chars | 8, 8, 8 | 8.00/8 |
| neutral | "you decide what the original means; add or remove nothing" | 207 chars | 4, 4, 4 | 4.00/8 |

![Figure 2. The ablation as a strip, six renders under blind IDs: the three that scored 8/8 came from the explicit refine, the three that scored 4/8 from the neutral one. Same model, same seeds, same settings; only the instruction to the refiner differs.](/img/watermelon-quant/figure-2.png)

Two findings, and they point opposite ways.

A good refine beat everything in the series. 8/8 on all three seeds, including the two that had produced the tattoo-on-a-human-thigh misread with the raw prompt. The ceiling is not fixed by the image model or the quant — it moved a full rubric point above the best raw render, and the whole move was a sentence. The explicit refine said, among other things: "the sandwich existing only as the tattoo artwork and never as a prop or object being tattooed." That one clause is the difference between 6 and 8.

A lazy refine scores below doing nothing. Under "add or remove nothing," ornith-9b deleted the tattoo machine and deleted "real world" while keeping "cartoon," and added a sunny sky. The image model then faithfully rendered a flat cartoon of an octopus holding a sandwich, with no tattooing at all — 4/8, three seeds, unanimous. That is a reasoning failure on the remove axis, and the neutral arm is exactly the instrument that measures it. Refinement is a gate, not a monotone improvement: the image model renders whatever the refiner throws away.

Terse refines are the risky ones: the neutral arm used 45 completion tokens, the explicit arm 129. A short refine reads as efficiency; on this workload it is a warning sign.

A refine replaces the seed as the lever. The raw prompt was bimodal — it flipped between a real beach scene and a tattoo-on-a-limb depending on the seed — but each refined arm produced one class across all three seeds. Refinement collapses the variance that made seed iteration useful.

I ran the neutral arm with two bigger local refiners to see whether scale bought the reasoning: Qwen3-Next-80B-A3B at Q4_K_XL and bonsai-27b at Q1_0. Text scores on a 14-point axis: 8 and 3. Renders at seed 7: 5/8 and 4/8. Both lost to ornith-9b given one explicit sentence. The 80B refine invented a towel, a beach ball, and a popsicle — and the image model rendered every one of them, faithfully. The renderer cannot distinguish an authored prop from a hallucinated one, which is what makes invention count a useful text-side metric. Scale did not buy adherence; the failure was instruction following, not capacity.

## The wall: a pixel budget, not a max side

The first ladder in this project concluded "cap at 1536 on the long side," and that was the wrong variable. The binding constraint is a single 4 GiB compute buffer — the driver reports a 4,294,967,295-byte maximum — and the diffusion transformer's compute buffer scales with latent token count, which tracks total pixels, not the long edge.

| Size | MP | Result | Wall |
|---|---|---|---|
| 1024×1024 | 1.05 | OK | 76 s (20 steps) |
| 2048×1024 | 2.10 | OK | 195 s (20 steps) |
| 1024×2048 | 2.10 | OK | 81 s (8 steps) |
| 1792×1792 | 3.21 | OK | 150 s (8 steps) |
| 1920×1920 | 3.69 | OK | 440 s (20 steps) |
| 2048×2048 | 4.19 | FAIL (HTTP 500) | < 20 s |

It sits between 3.69 MP, which passes at 440 s with a 12.52 GiB peak, and 4.19 MP, which fails in under 20 s. The budget is aspect-independent: 2048×1024 at 2.10 MP renders in 195 s at 20 steps, faster than 1536² at 230 s, on the same visual class of ask. The serving gate is now total pixels ≤ 3,800,000.

Once flash attention was baked into the server entry, the failure mode changed. Without it, a render whose buffer crossed the 4 GiB limit silently fell back to the CPU and crawled at 426 s/it against 4.12 (the no-attention 1536² cell, 2186 MB with attention, over the limit without it) — no error, no nonzero exit, a 103× slowdown that presents as a slow box. With attention on, the over-budget case fails fast with a 500. The buffer story is still why the flag is mandatory, even though the scary-silent version is gone for server traffic.

## The fields that never arrived

The server exposes an OpenAI-compatible route whose body carries steps, seed, and negative_prompt fields. This server does not read them. The defect announced itself when three step counts were requested: 20, 40, and 12 steps came back byte-identical (1,212,566 bytes) at a constant 76 s wall. A real 40-step run cannot cost the same as a 12-step run, and a random seed cannot produce three identical files.

Reading the source at this commit settles it: the OpenAI route parses the prompt, count, size, and output format, then applies the server's launch-time defaults, and the server's own documentation lists exactly those fields. The control fields are dropped by design, not by bug. The supported override is a JSON block embedded in the prompt, and once the wrapper builds that block the steps take effect — 8 steps in 32 s, 20 in 76 s, 40 in 150 s, with distinct outputs each time — and seed 42 renders byte-identically across calls.

The failure mode is the lesson: no error, no warning, no nonzero exit — plausible results at a plausible speed. Every step-count number in the first half of this project was measured on a step count the server had silently ignored, and the reading that seemed to follow from it — that steps were nearly free — was the artifact wearing a conclusion.

## What the checks caught

Every confident claim in the first version of these findings was wrong, and a check caught each one.

The banding metric took the lowest-variance block of the render — which is just blank sky, where banding cannot exist. A transect through an actual gradient is the valid measure.

The typography pair had the sign too small to read in either quant, so it proved nothing about the quants.

"Steps are nearly free" — the ignored-fields artifact from the section above, withdrawn with the fix.

The single-pair fidelity impression dissolved under blinding.

And one identifier of the dangerous kind: a plausible-looking build SHA written into a spec as a placeholder, caught by re-reading before it reached the record. The pattern across all five is the same — recalled content stated as verified content. The check is the only difference between those.

## A grain of salt

n=3 per arm, one scorer, blind IDs on a 400 px downsampled sheet, renders on one 24 GB RDNA3 box, refine arms on one local 9B model, one stable-diffusion.cpp build. The "own arm" axis of the rubric is judgment, and it wobbled even for a single scorer — two same-class cells scored 1 and 2 on that axis. The refiner rubric is not blind to prompt length, so a longer refine is guessable even with shuffled IDs. The bonsai-27b Q1_0 arm is confounded by quant damage and says nothing about 27B-class refiners. And the watermelon itself is n=1: it is real, it reproduces at that seed, and I do not know how often the Q4_0 build does this.

## Further reading

- [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) — the engine, at commit c678dfe
- [Qwen-Image-2.1](https://huggingface.co/Qwen/Qwen-Image-2.1) — the weights, the Q4_0/Q6_K GGUFs, and the license
- [llama-swap](https://github.com/mostlygeek/llama-swap) — the swap layer that arbitrates the card

## The effort, honestly

- Coordinator: this session — turns, tool calls, tokens, active time measured from the session log at publish time, after the last edit round
- Writer: none — merged from two independent single-author drafts (this session + a local 27B at 3-bit quant), numbers verified against the run record line by line
- Reviewer: a local 80B MoE (Qwen3-Next-80B-A3B) — one judgment pass, 27.6k prompt / 4.2k completion tokens; a second review pass on the merge by the standing 27B

<!-- CLOSER: author final -->

<p class="harness-meter"><span style="color:var(--accent)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><circle cx="7" cy="4.2" r="2.9" fill="currentColor"/><path d="M1.8 13.2c.5-3.4 2.6-5 5.2-5s4.7 1.6 5.2 5z" fill="currentColor"/></svg></span>2,497 words · 157 prompts <span class="sep">||</span> <span style="color:var(--gold)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><rect x="2.4" y="4.6" width="9.2" height="7.4" rx="1.8" fill="currentColor"/><line x1="7" y1="4.6" x2="7" y2="2.6" stroke="currentColor" stroke-width="1.1"/><circle cx="7" cy="2" r="1" fill="currentColor"/><circle cx="5.3" cy="8.3" r="1.1" fill="var(--paper)"/><circle cx="8.7" cy="8.3" r="1.1" fill="var(--paper)"/></svg></span>1,554 messages · ~39.6M tokens <span class="sep">||</span> <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" style="color:var(--ink);opacity:.7"><circle cx="7" cy="7" r="5.4" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M7 3.9V7l2.3 1.5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg> ~289 hours active</p>
