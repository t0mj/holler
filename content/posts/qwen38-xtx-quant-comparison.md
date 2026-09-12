---
title: "Qwen3.8-27B on a 24 GB 7900 XTX: the 3-bit quant won my long-context jobs"
date: 2026-09-06
draft: false
tags: [llama.cpp, qwen, quantization, amd, rdna3, llama-swap]
summary: "Two quants of the same 27B dense model on a 24 GB RX 7900 XTX — Q4_K_M vs a 3-bit GSQ-RCO IQ3_S with a real MTP head. Speed is a wash past 99k tokens; the 4 GiB the smaller file frees is what decides where your context ceiling actually is."
crossposts: []
---

## TL;DR

- I ran two quants of Qwen3.8-27B (dense, 64 layers) on a 24 GB RX 7900 XTX under llama.cpp (Vulkan, build b9999) with llama-swap: **Q4_K_M (15.64 GiB)** and a **3-bit GSQ-RCO IQ3_S with a real MTP head (11.29 GiB)**.
- Past ~99k prompt tokens the two are **speed-identical** (±3%). The difference is the context ceiling: the 4-bit quant's 262k KV pool **OOM'd at ~191k** in a boundary probe; the 3-bit quant runs the full 262k tier with **6 GiB of headroom** left.
- The MTP head in the 3-bit file is real (verified by file diff — and two other "MTP-named" files I tested were not), and `--spec-type draft-mtp --spec-draft-n-max 3` roughly **doubled decode** on it: 47.7 → 96.2 t/s, byte-identical output at temp 0.
- The 4-bit quant stays the gate model (quality pick, pinned to 185k ctx after the OOM probe); the 3-bit quant takes the long jobs — its day-to-day quality verdict is still open.

## The setup

Arch box, AMD RX 7900 XTX 24 GB, pinned via `GGML_VK_VISIBLE_DEVICES=0` (`vulkaninfo --summary`: `Vulkan0 AMD Radeon RX 7900 XTX (RADV NAVI31) 24560 MiB`). llama.cpp **b9999** Vulkan build (`47c7869`), fronted by llama-swap v253. Flags on both entries: 99 GPU layers, flash attention on, **q4_0 KV cache**, `--jinja`, 16 threads.

Every number below came from one harness against the front door, streaming, temp 0, with the payload SHA-256 recorded and identical on both sides, and 1 Hz VRAM sampling. The workloads:

- **standard**: a fixed coding-review prompt, 1,133 prompt tokens, 256 max tokens
- **long-ctx**: a long-context payload shaped like a large codebase review — a prompt template plus a big source corpus, **88,170 prompt tokens**, 512 max tokens
- **curve**: the same job scaled to 99,475 / 224,109 / 241,776 prompt tokens

Both models are thinking models; the standard-workload numbers were run model-default (thinking on), the curve with thinking off. Noted where it matters.

## The two quants

The two files (Hugging Face):

- **Q4_K_M** — [lmstudio-community/Qwen3.8-27B-GGUF](https://huggingface.co/lmstudio-community/Qwen3.8-27B-GGUF)
- **3-bit GSQ-RCO IQ3_S + MTP** — [ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF](https://huggingface.co/ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF) (`Qwen3.8-27B-GSQ-RCO-IQ3_S-mtp.gguf`)

| | Q4_K_M | GSQ-RCO IQ3_S + MTP |
|---|---|---|
| file size | 15.64 GiB | 11.29 GiB |
| provenance | lmstudio-community GGUF | ISTA-DASLab GSQ-RCO (group-scaled quant, RCO) |
| MTP head | no | **yes — verified** |

The MTP verification matters more than it should. Two other "MTP-named" 27B files in my test queue contained **no MTP tensors** — the name was aspirational. For the GSQ-RCO file I checked by diff: 4,034 `nextn`/`mtp` string matches, and the file is exactly **348,470,176 bytes larger** than the repo's non-MTP IQ3_S sibling. That's a head in the file.

(Anomaly worth a line: b9999's `llama-gguf -l` **core-dumps on this file** — the tensor-list tool crashes on GSQ-RCO per-tensor quants, while `llama-server` loads and serves it fine. I did the tensor survey with `strings` instead.)

## Speed

**Standard (1,133 pt, thinking on):**

| engine / quant | pp t/s | tg t/s |
|---|---|---|
| Q4_K_M, llama.cpp + draft-mtp | 696.8 | 91.6 |
| Q4_K_M, LM Studio (its internal engine, q8 KV, spec on) | 712.7 | 70.8 |
| GSQ IQ3_S, **no spec** | 725.5 | 47.7 |
| GSQ IQ3_S, **draft-mtp n-max 3** | (187.3* — cold-start-contaminated) | **96.2 (+102 %)** |

\* The spec run's prefill was contaminated by the cold start (TTFT 6.0 s); the prefill path is unaffected by spec, which the long-ctx numbers confirm.

**Long-ctx (88,170 pt, 512 max, thinking on):**

| engine / quant | pp t/s | tg t/s |
|---|---|---|
| Q4_K_M, llama.cpp + spec | 458.8 | 58.6 |
| Q4_K_M, LM Studio | 451.9 | 51.5 |
| GSQ IQ3_S, no spec (99,515 pt) | 435.4 | 32.3 |

Two things stand out. First, the smaller quant is not slower — it's usually a point or two *faster* on prefill (less weight to stream), and with the MTP head + spec flags it decodes faster than the 4-bit gate. Second: **the no-spec vs with-spec gap is the loudest number in this post** — 47.7 vs 96.2 t/s on the same file. If your serving engine runs speculative decoding and your bench or spawn doesn't mirror those flags, you're benchmarking a different machine than the one you run.

## The real question: where does the context ceiling actually sit

This is where quants stop being a quality choice and become a budget choice. Same box, same q4 KV, 24 GiB:

| | Q4_K_M | GSQ IQ3_S |
|---|---|---|
| file | 15.64 GiB | 11.29 GiB |
| 241,776-pt prefill (pp / tg) | 242.3 / 25.9 | 239.8 / 22.9 |
| VRAM headroom at 241k | **1.94 GiB** | **6.02 GiB** |
| boundary behavior | **262k KV pool OOM'd at ~191k tokens** | full 262,144 tier comfortable |

The speed curve is a flat tie:

| prompt tokens | Q4_K_M (pp / tg) | GSQ IQ3_S (pp / tg) |
|---|---|---|
| 99,475 | 420.0 / 46.0 | 409.4 / 45.6 |
| 224,109 | 256.0 / 28.5 | 253.5 / 29.3 |
| 241,776 | 242.3 / 25.9 | 239.8 / 22.9 |

<svg viewBox="0 0 720 400" width="100%" role="img" aria-labelledby="cc-title" xmlns="http://www.w3.org/2000/svg" font-family="inherit">
<title id="cc-title">Prefill speed versus prompt length for Q4_K_M and GSQ IQ3_S, with the 4-bit OOM boundary</title>
<line x1="56" y1="354.0" x2="704" y2="354.0" stroke="currentColor" stroke-opacity="0.14"/>
<text x="48" y="358.0" text-anchor="end" font-size="12" fill="currentColor" opacity="0.65">200</text>
<line x1="56" y1="288.8" x2="704" y2="288.8" stroke="currentColor" stroke-opacity="0.14"/>
<text x="48" y="292.8" text-anchor="end" font-size="12" fill="currentColor" opacity="0.65">250</text>
<line x1="56" y1="223.6" x2="704" y2="223.6" stroke="currentColor" stroke-opacity="0.14"/>
<text x="48" y="227.6" text-anchor="end" font-size="12" fill="currentColor" opacity="0.65">300</text>
<line x1="56" y1="158.4" x2="704" y2="158.4" stroke="currentColor" stroke-opacity="0.14"/>
<text x="48" y="162.4" text-anchor="end" font-size="12" fill="currentColor" opacity="0.65">350</text>
<line x1="56" y1="93.2" x2="704" y2="93.2" stroke="currentColor" stroke-opacity="0.14"/>
<text x="48" y="97.2" text-anchor="end" font-size="12" fill="currentColor" opacity="0.65">400</text>
<line x1="56" y1="28.0" x2="704" y2="28.0" stroke="currentColor" stroke-opacity="0.14"/>
<text x="48" y="32.0" text-anchor="end" font-size="12" fill="currentColor" opacity="0.65">450</text>
<line x1="56.0" y1="28" x2="56.0" y2="354" stroke="currentColor" stroke-opacity="0.10"/>
<text x="56.0" y="372" text-anchor="middle" font-size="12" fill="currentColor" opacity="0.65">0k</text>
<line x1="179.6" y1="28" x2="179.6" y2="354" stroke="currentColor" stroke-opacity="0.10"/>
<text x="179.6" y="372" text-anchor="middle" font-size="12" fill="currentColor" opacity="0.65">50k</text>
<line x1="303.2" y1="28" x2="303.2" y2="354" stroke="currentColor" stroke-opacity="0.10"/>
<text x="303.2" y="372" text-anchor="middle" font-size="12" fill="currentColor" opacity="0.65">100k</text>
<line x1="426.8" y1="28" x2="426.8" y2="354" stroke="currentColor" stroke-opacity="0.10"/>
<text x="426.8" y="372" text-anchor="middle" font-size="12" fill="currentColor" opacity="0.65">150k</text>
<line x1="550.4" y1="28" x2="550.4" y2="354" stroke="currentColor" stroke-opacity="0.10"/>
<text x="550.4" y="372" text-anchor="middle" font-size="12" fill="currentColor" opacity="0.65">200k</text>
<line x1="674.0" y1="28" x2="674.0" y2="354" stroke="currentColor" stroke-opacity="0.10"/>
<text x="674.0" y="372" text-anchor="middle" font-size="12" fill="currentColor" opacity="0.65">250k</text>
<text x="704.0" y="372" text-anchor="middle" font-size="12" fill="currentColor" opacity="0.65">262k</text>
<text x="56" y="18" font-size="12" fill="currentColor" opacity="0.65">prefill (t/s)</text>
<line x1="528.1" y1="28" x2="528.1" y2="354" stroke="#dc2626" stroke-width="1.5" stroke-dasharray="6 5"/>
<text x="522.1" y="44" text-anchor="end" font-size="12.5" fill="#dc2626">Q4 OOM-kill ~191k (bad-RAM day)</text>
<line x1="513.3" y1="28" x2="513.3" y2="354" stroke="#c2410c" stroke-width="1.5"/>
<text x="507.3" y="346" text-anchor="end" font-size="12.5" fill="#c2410c">Q4 pool pinned 185k</text>
<line x1="704.0" y1="28" x2="704.0" y2="354" stroke="currentColor" stroke-opacity="0.35"/>
<polyline points="301.9,67.1 610.0,281.0 653.7,298.8" fill="none" stroke="#c2410c" stroke-width="2.5"/>
<circle cx="301.9" cy="67.1" r="4" fill="#c2410c"/>
<circle cx="610.0" cy="281.0" r="4" fill="#c2410c"/>
<circle cx="653.7" cy="298.8" r="4" fill="#c2410c"/>
<polyline points="301.9,80.9 610.0,284.2 653.7,302.1" fill="none" stroke="#0f766e" stroke-width="2.5"/>
<circle cx="301.9" cy="80.9" r="4" fill="#0f766e"/>
<circle cx="610.0" cy="284.2" r="4" fill="#0f766e"/>
<circle cx="653.7" cy="302.1" r="4" fill="#0f766e"/>
<line x1="66" y1="46" x2="92" y2="46" stroke="#c2410c" stroke-width="2.5"/><text x="98" y="50" font-size="12.5" fill="currentColor">Q4_K_M (15.64 GiB)</text>
<line x1="66" y1="66" x2="92" y2="66" stroke="#0f766e" stroke-width="2.5"/><text x="98" y="70" font-size="12.5" fill="currentColor">GSQ IQ3_S (11.29 GiB)</text>
</svg>

*Both quants benched to 241,776 tokens on a good-RAM day (09-05). The 4-bit’s ~191k death is the next day’s boundary probe on a bad-RAM day: past that point the KV overflowed into system RAM and the kernel killed the server mid-prefill. Same box, same 262k pool — the boundary moved with RAM state, which is why the margin past the 185k pin is fatal rather than slow.*
Prefill degrades smoothly with depth on both (attention scaling), and the 4.3 GiB of weights the 3-bit quant doesn't carry never shows up as a speed difference — at these depths the GPU is too busy with KV to care. What it *does* buy is the boundary: the 4-bit quant's 262k pool died mid-prefill around 191k in the probe (I pinned it to 185,000 ctx + `-cram 24576` afterward, and verified a fresh 172k prefill at 312 t/s), while the 3-bit quant sat at 241k with 6 GiB to spare.

So on this box the honest read is: **if your jobs fit under ~180k, take the 4-bit for quality. If your jobs are 200k-class, the 3-bit is the one that actually fits**, and you're not paying a speed penalty for it.

## What I run now

The decision, concretely:

- **Day-to-day** — my coding agent's working sessions — runs on the **Q4_K_M gate pinned at 185k ctx**. The agent compacts its own session context as it goes, so day-to-day usage stays within ~5% of that cap: the cut from 262k costs nothing in practice, and it removes the OOM boundary from under the daily driver.
- **Long-context jobs** (200k-class reviews) go to the **GSQ IQ3_S entry at 262k** — the one with the room.

That gate model's thinking knob — what `off` / `low` / `medium` / `xhigh` actually do to it, and why "xhigh" is a duplicate of the default — has its own post: [the thinking-levels grid](/holler/posts/qwen38-thinking-levels/).

Honest caveat: **the 3-bit's quality is not day-to-day tested yet.** My GSQ runs so far are the long-context jobs, and the outputs on those have looked right — but that's one job shape and a small sample. I haven't lived with it as a daily driver; once I have, I'll have a much better idea of where the 3-bit actually sits, and this section gets a corrections note if I'm wrong.

## How the gate model got here (the flip A/B)

The Q4_K_M entry exists because I A/B'd the model through my llama-swap front door two ways — LM Studio's internal Vulkan engine (q8 KV + `--kv-offload` + mlock, spec on) versus local llama.cpp b9999 (q4 KV, FA on, spec flags mirrored) — on the identical SHA-verified payloads:

| workload | metric | LM Studio | llama.cpp + spec | delta |
|---|---|---|---|---|
| standard | pp / tg | 712.7 / 70.8 | 696.8 / 91.6 | −2.2 % / **+29.4 %** |
| 88k long-ctx | pp / tg | 451.9 / 51.5 | 458.8 / 58.6 | +1.5 % / **+13.8 %** |

Statistical tie on prefill, faster decode, ~2 GiB less VRAM at steady state (22.0 vs 24.0). Flip kept.

One trap from that day, recorded in full in [the CPU-fallback incident post](/holler/posts/xtx-cpu-fallback-incident/): the first flip landed while LM Studio's copy was still loaded in-TTL, the new server spawned into ~1.7 GiB of remainder, and "worked" at **pp 4.3 t/s** until the TTL cycled it. Offload is decided once, at load, and VRAM residue at spawn time is how you find out.

## Anomalies worth keeping

- **`--fit on` is not a budget gate on Vulkan** — lazy KV allocation means no up-front reserve, so the flag happily starts a 262k server that will OOM at 191k. Empirical probes are the record.
- **Hot-reloading the llama-swap config stops ALL running model servers**, not just the changed one. A config edit is a fleet-wide eviction event.
- **A flag grid (threads 8/16 × FA × KV f16/q8/q4) moved prefill by ≤3% and decode by ±1.5%** — decode on this box is memory-bandwidth-bound and mostly flag-insensitive. The flags that matter are the KV quant (the memory lever) and the spec flags (the decode lever).

## A grain of salt

One box, one engine build, one model family, two quants — and the 3-bit quality picture is early evidence from one job shape, not a verdict. The transferable parts: verify MTP heads by file diff, not filename; probe your real context boundary instead of trusting `--fit`; and remember that on a fixed-VRAM box the quant choice is a context-budget decision first and a quality decision second.

If you're running 27B-class dense models on 24 GB and know where your ceiling sits — with numbers — post it. Piles of other people's ceilings are the only way to know what yours should be.
