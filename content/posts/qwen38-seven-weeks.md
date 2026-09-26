---
title: "Seven weeks of Qwen 3.8: marking the milestone with Qwen 4 on the horizon"
subtitle: "One box, one benchmark, and the reference line the next generation has to clear — by axis, not by headline."
date: 2026-09-25
draft: false
tags: [qwen3.8, qwen4, llama.cpp, spec-decode, quantization, fine-tune]
summary: "The 3.8 base ties the strongest fine-tune on the roster within measured noise; the peak — 0.931 — is a configuration, not a download."
crossposts: []
---

## TL;DR

- **The new base didn't beat the old champion. It tied it.** The Qwen3.8-27B base scores 0.883 against 0.900 for qwythos, a Qwen3.5-27B fine-tune, on the 80 items both runs share — 0.900 − 0.883 = 0.017, inside my measured noise band — and the best 3.8 build (Swift, a community fine-tune, at medium thinking) reaches 0.931 on those same 80 items. The peak is a configuration, not a download.
- **The load-bearing number:** fix/implement went from 0/40 to 39/40 when speculative decoding, on by default in the stock serving config, was switched off (09-15/16 A/B, 364 cells, seed 42). The shipped default had been collapsing hard reasoning on the base family without an error.
- **The setup:** one 24 GB 7900 XTX running llama.cpp, one model at a time. The FP8 speed reference and the long session ride on a rented A100.
- **The caveat:** n=1 box and one workload class (coding-agent daily driving). The suite is a bespoke 91-item battery, so its absolute scores do not carry over to public model cards.

## Tom Notes

The 3.8 base is a strong brain, and the next wave is clearly the refinements built on top of it. The pattern is the same every time: take a base model, tune it toward a specific use. Mine is coding and building locally — high context, good reasoning, fully local. The arc to Swift was a run through those lanes in order, and with Qwen 4 on the horizon, Swift is the best version of Qwen available right now for daily driving.

GSQ proved the 3-bit could carry the window; in the hand it felt a little too loose. Vibes on Swift so far run the other way — a bit more sterile, more structured, the 3-bit looseness tamed, and the 228k window is what that buys. And the spec-decode cliff that ate the base family simply doesn't reproduce on it.

The practical shift: the rented A100 gets called up less. Swift carries more of the daily work on the box, and the A100 is for throughput and bandwidth across multiple projects — not raw speed.

I'm excited for Qwen 4, and more excited to watch what the next wave of refinements does to it. It's like getting an awesome car and adding a few things for extra horsepower when you want it at the track, or fuel mileage for a long trip. They don't all work at once — and it looks like Qwen is building the best car that can do either, with the rest of the world fitting it to its own needs. With this stuff changing daily, it's an exciting time for anyone who wants in on making it work for their use case.

## Seven weeks on one card

Qwen3.8-27B was released on 2026-08-05 and became my daily coding model at the 09-05 migration. That makes seven weeks from release to this post, with four before the switch and three after. The setup is one 24 GB 7900 XTX running llama.cpp behind llama-swap, with one model loaded at a time and nothing else on the card. This card once dropped to the CPU and ran there for 2.5 hours without saying so — [the incident](/holler/posts/xtx-cpu-fallback-incident/). Every decode figure below therefore comes with a speed check. Four numbers decide whether the model stays.

- **Quality:** the base scores 0.912 at medium thinking, which is where daily use runs, and 0.882 averaged across all four thinking levels (full 91-item run, 09-15/16, spec off). Agentic work at xhigh reaches 0.97 on the same suite with Smaug-Mini, an agentic fine-tune of the base (09-15, spec off). Hard work is the family's weakest axis: Swift scores 0.717 on the hard-30 screen at effort off.
- **Speed:** a clean A/B on this card (09-16, Q4_K_M, one payload per arm) gave 40.5 t/s decode with speculative decoding off and 77.8 t/s with it on, a 1.92× difference. Spec on costs the base its hard reasoning, so the base runs at the lower figure. Swift keeps a spec-on rate of 76.8 t/s with its quality inside noise.
- **Context:** the full 262k-token window fits in 18.0 GiB of VRAM on GSQ-RCO, a community 3-bit quant. Swift carries 228k.
- **Cost:** the 24 GB box costs $0 to run. The rented A100 that served as the FP8 speed reference hosted the long session, which closes the post.

It earned the slot.

## What moved from 3.5

Before 3.8, the strongest model on my roster was [qwythos-27b-v1](https://huggingface.co/empero-ai/Qwythos-27B-v1), a community fine-tune of the Qwen3.5-27B base from two generations back. On the 80 items both eras share, the 3.8 base scores 0.883 against qwythos's 0.900 — 0.900 − 0.883 = 0.017, inside the noise band I measured — and the 3.8 number comes with no community training on top. On this suite, the gap closed.

The first head-to-head was a pilot on 09-07. It used the 80-item suite, ran both arms at Q4_K_M with seed 42 and production sampling, and served 3.8 as shipped, with speculative decoding on. Results are the mean and passes out of 80, in the order off / low / medium / xhigh:

- **[qwen38-27b](https://huggingface.co/lmstudio-community/Qwen3.8-27B-GGUF), spec on:** 0.871 (67), 0.908 (70), 0.888 (68), **0.792 (61)**
- **qwythos-27b-v1, served without MTP:** 0.900 (70), 0.904 (70), 0.888 (68), **0.908 (71)**. Stable across efforts, xhigh its best level, zero cap-hits.

Across the seed-42 320-cell matrix, 3.8 passed 266/320 (83.1%) and qwythos passed 279/320 (87.2%). qwythos was best-or-tied in 11 of the 16 effort cells. Knowledge went 10/10 for both arms at every level.

xhigh is where 3.8 fell apart. The pilot had 12 length-finish cells, and 11 of them were 3.8 at xhigh. Each spent 27k–36k reasoning characters and returned almost no content. At xhigh, implement dropped to 0.300 and review to 0.433, against 0.60–0.80 and 0.77–0.80 at the other levels. The net was −0.117 against the arm's own low-effort score.

qwythos runs long by habit. In the pilot it spent 2.2–3.6× the reasoning characters of 3.8, which cost 3–4× the wall time at thinking levels. [The thinking-levels post](/holler/posts/qwen38-thinking-levels/) covers that knob and its price. At the time, the collapse read as a model property. Part of it was the engine.

The daily driver before 3.8 was qwen3.6-27b-obliterated. Benched on the same 80 items on 09-24, it scores 0.910 / 0.885 / 0.879 / 0.888 — 267/320, mean 0.890, flat across efforts with no xhigh collapse. That matches the 3.8 base's spec-off 267/320 and sits 12 cells under qwythos, the same boundary tie. One caveat: the build bakes its own sampling into the file (temp 0.45, top_p 0.90), and the bench ran that served default rather than the instrument's temp 1.0 / top_p 0.95, so this row shows the artifact as a pass-through client runs it, not an instrument-matched score.

Context moved further. [GSQ-RCO](https://huggingface.co/ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF), a community IQ3_S build of the base, drops to 3 bits at 11.3 GiB. It loads all 262k tokens of context in 18.0 GiB of VRAM, a pool the 4-bit build could not load at all. p50 decode tied at spec off: 47.3 t/s on the 3-bit and 44.9 on the 4-bit, measured over a production day with both quants side by side. The ceiling was the 4-bit weights, not the card.

Swift covers the rest. UkisAI's suppression fine-tune of the base carries 228k context at 13.35 GiB. It runs 76.8 t/s with spec on, 1.76× its own spec-off rate (09-21 full run). The xhigh collapse does not reproduce on it.

## The TomBench scoreboard

I call the instrument the TomBench. Nobody else has it, and that's the point. It is a private, machine-graded battery that can't be gamed, and it runs the same way on every model that crosses the box. The aim is access: someone with a gaming PC should get the same AI the big players get. The battery shows, with measured numbers, where the options available today stand. Each row is one model arm on this box. The suite has 91 machine-graded coding items across seven blocks (implement, fix, review, reasoning, agentic/tool-use, instruction-following, knowledge), run at four thinking levels for 364 cells per row.

| Model arm | Quant | Spec | off | low | medium | xhigh | all | pass |
|---|---|---|---|---|---|---|---|---|
| Qwen3.8-27B base | Q4_K_M | off | 0.886 | 0.894 | 0.912 | 0.835 | 0.882 | 308/364 |
| Smaug-Mini (agentic fine-tune) | Q4_K_M | off | 0.897 | 0.903 | **0.929** | 0.810 | 0.885 | 312/364 |
| GSQ-RCO (3-bit community build) | IQ3_S | off | **0.919** | **0.925** | 0.921 | 0.762 | 0.882 | 314/364 |
| Swift (suppression fine-tune) | Q3_K_L | off | 0.901 | 0.916 | 0.907 | **0.899** | **0.906** | **319/364** |
| Swift (same arm, spec on) | Q3_K_L | on | 0.863 | 0.892 | 0.918 | 0.916 | 0.897 | 314/364 |

Bold marks the best **spec-off** arm per column; the one spec-on row sits out of the running.

How to read it:

- **Partial credit.** Scores run from 0 to 1, and "pass" counts the items that earned full credit. When two rows have the same pass count but different means, partial credit accounts for the difference.
- **Effort levels.** The columns off → xhigh are how hard the model is made to think. A model can hold at one level and collapse at the next.
- **Noise floor.** This is measured, not assumed. A seed-jitter probe flipped one reasoning result in fifteen, so a delta of three passes or fewer in 80 counts as noise.
- **Setup and comparability.** Every cell uses production sampling (temp 1.0, top_k 20, top_p 0.95, min_p 0.05) with seed 42 pinned. The suite is bespoke, so rows compare to each other, not to public model cards. Every row is a named run, and the ledger at the end lists each one.

## The default flag that zeroed hard reasoning

The stock serving config shipped with speculative decoding on. On the base family it scored fix/implement 0/40 with no crash, no error in the logs, and plausible-looking output. A failure with no alarm attached is the kind that reaches production. Zero points, nothing flagged.

An A/B on 09-15/16 held everything constant except the spec flag: 364 cells, seed 42, identical payload. Switching spec off moved the 3.8 base from 0.704 to 0.882, and fix/implement from 0/40 to 39/40. Smaug moved from 0.700 to 0.885, with 27/40 on fix/implement at spec on. The control block held steady across the flip.

Turning spec off has a price, measured on a scratch server with one payload per arm (09-16, Q4_K_M). With spec on, decode was 1.92× faster at standard context (40.5 → 77.8 t/s) and 1.50× faster at 64k (34.5 → 51.7 t/s). Prefill ran −4–6%, and VRAM use rose by +1.4 GiB. (The 40.5 t/s is one clean payload on an idle server. The p50s quoted in the 3.5 comparison come from a full production day, and the two measurements don't subtract.) A wrong answer decoded twice as fast is still wrong. The price stays on record for the day the upstream fix lands, and a write-up of the speed side is in the works.

The mechanism, as reported in the open [llama.cpp issue #25618](https://github.com/ggml-org/llama.cpp/issues/25618), is batch invariance. Batched verification of draft tokens is a different computation from serial decode. At a greedy near-tie, a 1-ULP logit difference flips the argmax, and on a long chain that one flip cascades. It reproduces on Q8, so it isn't a low-bit artifact, though quantization amplifies it. It also reproduces across every draft method, which rules out MTP; ngram drafting is reportedly lossless.

That is the signature: long chains collapse, short items pass, the output reads fine, and nothing crashes. The pilot's xhigh collapse matched it. Eighteen points came back from a default flag.

## GSQ: the whole window on a 3-bit

In an OOM probe, the 4-bit base ran out of memory at ~191k tokens, so I pinned it at 185k. GSQ-RCO is the community IQ3_S build, with its MTP head confirmed present in the file. It serves the full 262k pool, a window the 4-bit could not load.

A production day ran both quants side by side for 795k output tokens. Prefill p50 came in at 128 t/s on the 3-bit and 174 on the 4-bit. Dequantizing IQ3 weights costs time, and prefill is where that cost lands. VRAM use was 18.0 GiB on the 3-bit and 22.0 on the 4-bit.

The workday after that pushed ~400k tokens through 8 sessions, and five of those sessions overflowed the box's cram budget. It did not feel like a step down, only a little looser. I went back to the 4-bit the next day.

GSQ's TomBench run (09-16, spec off) scored 0.882, 314/364. At off/low/medium it scored 0.919–0.925, best-or-tied, with a best reasoning score of 0.953 and implement at 0.775. At xhigh it fell to 0.762. The 3-bit sheds long chains.

To test whether KV precision caused the drop, I ran an f16 KV-cache probe on both quant families. It changed nothing on either, which puts the xhigh softness in the weights. Hard long-chain work therefore stays on the 4-bit. Three sibling posts have the detail: [the quant comparison](/holler/posts/qwen38-xtx-quant-comparison/), [the production day](/holler/posts/qwen38-gsq-production-day/), and [the workday](/holler/posts/qwen38-gsq-workday/).

## Smaug: the agentic fine-tune with an inherited draft head

Abacus.AI released [Smaug-Mini](https://huggingface.co/abacusai/Smaug-Mini) on 2026-09-02. It is an agentic GRPO fine-tune of Qwen3.8-27B with vision. Per the release card, its MTP head was inherited from the base and not retrained after the GRPO merge. HuggingFace carried bf16 only (55.6 GB across 18 shards) and no community GGUF existed, so I converted it in-house on llama.cpp b10970. The unattended two-hour pipeline hit four build incidents. One of them, a GGUF overwrite that silently replaced the running file, is a story for a shorter post.

Its TomBench run (09-15, spec off) scored 0.885, 312/364, the best overall of the base family that week. The agentic block at xhigh hit 0.97, the best single number on the roster. Its medium band, 0.929, was also the best on the board.

The release card also carried a warning. Because the MTP head was never retrained, the card said MTP-based speculative decoding "should be left off" — standard decoding unaffected. The advice was written for this one model. The A/B in the previous section showed it applied to the whole family, and that line on the card is where the spec-off hunt started.

## Swift: the build on the right side of the bug

UkisAI's [Swift-Qwen3.8-27B](https://huggingface.co/ukisai/Swift-Qwen3.8-27b) is a suppression fine-tune. I run it at Q3_K_L, where it is 13.35 GiB with a 228.3k context pool, and I verified its MTP head in the file by tensor name.

It took four runs to go from rejected to served:

1. **Screen, 09-20: failed.** The 29-item screen scored 0.707 (17/29) with four errors, below the 0.762 acceptable corner. Every non-off effort refused to emit reasoning, so the screen ran off-only. My first read was "suppression head, no live reasoning."
2. **Full run, 09-20/21, spec off: top of the roster.** It scored 0.906, 319/364, the best full-run mean on the roster, with a flat effort curve of 0.901 / 0.916 / 0.907 / 0.899. The xhigh cliff is gone. There were zero cap-hits, and mean xhigh reasoning was 4,244 characters, against ~7,558 for Smaug and GSQ. Its xhigh efficiency, 6.71, is the best on the roster.
3. **Spec probe, 09-21: flat.** I took the 25 longest xhigh chains and flipped spec off → on. The net change in full-credit results was zero. The base family lost 18 points to the same flag.
4. **Spec-on full run, 09-21: a dip inside noise.** It scored 0.897 against 0.906 at spec off, a −0.009 dip that is ~1.2σ of the calibrated noise band. In exchange, wall-clock time fell by 2.00× (109.4 → 54.6 min) at 76.8 t/s (1.76×), and xhigh reasoning ran 21% shorter. The loss is concentrated in the two greediest efforts, off and low, which is the batch-invariance signature. Medium and xhigh are flat to positive.

Swift is the one entry I now serve with spec on, and I made that switch only after the runs above. Its limit is hard work. On the hard-30 screen at effort off it scores 0.717, below the hard-work corner. 3.8's peak is a daily-driver and long-context peak, not a hard-work primary.

Swift is the base family's failure run in reverse. The bug needs long reasoning chains to do damage, and this fine-tune shortens them. With a short enough reasoning tail, decoding rarely runs long enough to hit the 1-ULP flip, so the cliff never forms. The same flag that cost the base family eighteen points gives Swift 2.00× wall-clock with nothing to lose.

## Peak against peak on the shared 80

The 91-item suite is the pilot's 80 items plus eleven added later (mip-01…10 and rea-16). Restricting each run to the shared 80 puts a 3.8 peak and a 3.5 peak on one instrument. I recomputed this on 2026-09-21 from the raw run files, with seed 42 and production sampling.

On the 3.8 side, the peak is Swift at medium: 0.931 (70/80). Spec on and spec off tie at that level, but averaged across all four efforts, spec off leads with 0.916 against 0.902. On the 3.5 side, the peak is qwythos at xhigh: 0.908 (71/80). Each is the best effort level for its own family, picked the same way for both.

Averaged over all four efforts on the shared 80, Swift at spec off scores 0.916 (278/320) and qwythos scores 0.900 (279/320). The means favor Swift through partial credit, while the pass counts are a wash. The 3.8 base at spec off sits at 0.883 (267/320).

Here is how the two peaks compare block by block:

| Block | Swift, medium (3.8) | qwythos, xhigh (3.5) |
|---|---|---|
| agentic | 0.967 | 0.867 |
| fix | 1.0 | 0.9 |
| implement | 0.9 | 0.8 |
| instruction-following | 0.967 | 1.0 |
| reasoning | 0.933 | 0.933 |
| review | 0.733 | 0.867 |
| knowledge | 1.0 | 1.0 |

The 3.8 peak wins agentic, fix, and implement. The 3.5 peak takes review and instruction-following, and reasoning and knowledge tie.

For the base weights alone, the comparison is 0.883 for the 3.8 base against 0.900 for the 3.5 fine-tune. On the 320-cell matrix that is a 12-cell gap, which lands exactly on the 3-in-80 noise boundary. A tie at the boundary.

The margins above that line belong to the ecosystem. Swift's 0.931 peak beats qwythos's 0.908 by 2.3 points, and it beats the base's 0.883 by 4.8 points, well outside the band. That 4.8-point gap came from a fine-tune, a quant decision, and a spec lesson, not a download. The base weights earned the draw, and the configuration earned the peak.

## The reference line for Qwen 4

This is what the next generation has to clear, by axis and by spec mode:

| Axis | The 3.8 line | Evidence |
|---|---|---|
| Overall quality (91-item run, 4 efforts) | 0.906 spec-OFF / 0.918 medium spec-ON (Swift) | the Swift section |
| Agentic xhigh | 0.97 (Smaug, spec-OFF) | the Smaug section |
| Hard-work screen (hard-30 @ off) | 0.717–0.762 — the family's weak axis | the Swift section |
| Context window on 24 GB | 262k (GSQ, 11.3 GiB) / 228k (Swift) / 185k (Q4) | the GSQ section |
| Decode speed | 44.9–47.3 t/s p50 spec-OFF; 76.8 t/s Swift spec-ON; 48.7 t/s (rented A100, FP8) | the GSQ and Swift sections |
| Cost | $0 on the 24 GB box; one rented A100 for the FP8 speed reference and the 1.9M-token session | the opening |
| Daily-driver test | An 8h38m, 1.9M-token idea→launch session at medium thinking, two compactions sailed through | the long-session post |
| Traps to re-check on 4 | Stock template defaults to xhigh (the $0 lever); spec-decode batch-invariance on quants (issue #25618, open); min_p baked into GGUF metadata drifts between sources | the pilot; the spec-decode section |

When Qwen 4 ships, I will measure it on the same suite, seed, sampling, and box, and ask which of these seven axes moves and by how much. On the full run, the floor is Swift's 0.906 at spec off. For context on this card, the line is 262k at 11.3 GiB. The traps row lists three things that are not model properties: a template default, an engine bug with an open issue, and min_p drift in GGUF metadata between quant sources. All three get re-checked on any new model before the first headline.

Keep in mind that a successor's download is not comparable to a predecessor's configuration. 3.8's peak came from a fine-tune, a quant decision, and a spec lesson on top of the base. If Qwen 4's base lands where 3.8's did, tied within noise with the best fine-tune on the roster, that is a normal result, and the ecosystem has already closed that kind of gap once.

So far the only official Qwen 4 signal is Alibaba's own. Qwen3.8-Flash-Next, released 2026-08-28, was described as "an experimental preview of the architecture that will underpin Qwen4." The reference line leans on that one sentence.

Looking back, the month split into three jobs. The first was building the instrument: the suite, the effort levels, the sampling profile, and the measured noise floor, none of which a model card shows. The second was daily driving: the 09-05 migration, the production days, and the workdays. The third was the bug hunt, and it is the one that changes what the other two mean. The pilot's xhigh collapse started out as a model property. The 18-point A/B showed it was an engine property. Swift's flat spec probe then showed it was a configuration property.

The suite measures what a model can do, and the daily driver measures what it survives. The test of survival was one 8h38m session on the rented A100: 1.9M tokens from idea to launch at medium thinking, through two context compactions ([the long session](/holler/posts/qwen38-27b-long-session-launch/)). Across the month, this box ran ~2,500 machine-graded completions. The suite and the session agree on the shape of the peak: strong at the effort level daily work runs at, stable across a working day, and clear about where it is not a primary.

## The ledger, laid out

The numbers above come from named runs, each with a seed and a serving config — that is the provenance the reference-line table points at, in full:

| Run | Config | Result |
|---|---|---|
| Pilot, 80 items × 4 efforts | Q4_K_M, spec ON, seed 42 | 680 rows, 0 errors; pass 83.1% (3.8) vs 87.2% (qwythos) on the 320-cell matrix |
| Obliterated shared-80 run | Q4_K_M, spec OFF, seed 42, served-default sampling (temp 0.45 / top_p 0.90 baked) | 267/320, mean 0.890; 0.910 / 0.885 / 0.879 / 0.888 |
| Gate A/B, 364 cells | Q4_K_M, spec ON→OFF, seed 42 | 0.704 → 0.882; fix/implement 0/40 → 39/40 |
| Smaug A/B, 364 cells | Q4_K_M, spec ON→OFF, seed 42 | 0.700 → 0.885 (27/40 at spec on) |
| GSQ run, 364 cells | IQ3_S, spec OFF, seed 42 | 0.882, 314/364 |
| Smaug run, 364 cells | Q4_K_M, spec OFF, seed 42 | 0.885, 312/364; agentic xhigh 0.97 |
| Swift 29-item screen | Q3_K_L, off-only, seed 42 | 0.707 (17/29), 4 errors |
| Swift full run, 364 cells | Q3_K_L, spec OFF, seed 42 | 0.906, 319/364 |
| Swift spec probe, 25 xhigh chains | Q3_K_L, spec OFF→ON, seed 42 | net-zero full-credit flips |
| Swift spec-ON run, 364 cells | Q3_K_L, spec ON, seed 42 | 0.897; 2.00× wall; 76.8 t/s |
| Speed A/B, scratch server | Q4_K_M, one payload per arm | 1.92× decode standard; 1.50× at 64k |

The shared-80 restriction in the peak section — Swift spec-off 0.931 at medium, qwythos 0.908 at xhigh — is computed from the raw files of the pilot and the two Swift runs, restricted to the 80 item ids they share, seed 42, production sampling. It is a re-restriction of measurements already in the table, not a new run.

Two more provenance notes. The pilot's "630 rows" figure in the original report is a record error; the raw file holds 680, and that is the number this post uses. And an earlier pass rate of "84.0%" carried a 350-row denominator that included variance rows — it must not be used; the seed-42 matrix figure is 83.1% versus 87.2%.

## A grain of salt

n=1 box, one workload class — coding-agent daily driving. The 91-item suite is bespoke, so its absolute scores are not comparable to public model cards. The suite was also constructed over time: the 3.5-era pilot predates the eleven items added later, so "same instrument" is exact in items, not in temporal construction, and I don't know the effect size. Every matrix cell is seed 42; the measured noise floor is the 1/15 reasoning flip and the 3-in-80 delta rule, and the base-versus-fine-tune comparison in the peak section lands exactly on that boundary, so it stays "within noise," full stop. Both "peaks" in the peak section are best-of-efforts picks, symmetric across families, and the all-effort pass counts are a wash — the mean advantage is partial credit. Swift's hard-30 at off, 0.717, sits below the hard-work corner: the peak is a daily-driver peak. The FP8 run on the rented A100 was a speed and cost slice only; it was never quality-baselined against the TomBench. The batch-invariance mechanism in the spec-decode section is as reported in an open issue, not established fact. And the Qwen 4 hook is only as firm as one official line: Flash-Next as a preview of the architecture that will underpin Qwen4.

## Further reading

- [The CPU-fallback incident](/holler/posts/xtx-cpu-fallback-incident/) — why a quiet box deserves a decode-speed check, not a shrug
- [The Q4/GSQ quant comparison](/holler/posts/qwen38-xtx-quant-comparison/) — the window purchase in full
- [The thinking-levels post](/holler/posts/qwen38-thinking-levels/) — the effort knob and its wall-time price
- [The GSQ production day](/holler/posts/qwen38-gsq-production-day/) and [the workday](/holler/posts/qwen38-gsq-workday/) — both quants, 795k and ~400k tokens
- [The 1.9M-token long session](/holler/posts/qwen38-27b-long-session-launch/) — the daily-driver test
- llama.cpp issue [#25618](https://github.com/ggml-org/llama.cpp/issues/25618) — batch-invariance in draft speculative decoding; open, as reported

<p class="harness-meter"><span style="color:var(--accent)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><circle cx="7" cy="4.2" r="2.9" fill="currentColor"/><path d="M1.8 13.2c.5-3.4 2.6-5 5.2-5s4.7 1.6 5.2 5z" fill="currentColor"/></svg></span> ~4,500 words · 44 prompts <span class="sep">||</span> <span style="color:var(--gold)"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><rect x="2.4" y="4.6" width="9.2" height="7.4" rx="1.8" fill="currentColor"/><line x1="7" y1="4.6" x2="7" y2="2.6" stroke="currentColor" stroke-width="1.1"/><circle cx="7" cy="2" r="1" fill="currentColor"/><circle cx="5.3" cy="8.3" r="1.1" fill="var(--paper)"/><circle cx="8.7" cy="8.3" r="1.1" fill="var(--paper)"/></svg></span> 428 messages · ~1.1M tokens <span class="sep">||</span> <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" style="color:var(--ink);opacity:.7"><circle cx="7" cy="7" r="5.4" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M7 3.9V7l2.3 1.5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg> ~8.5 hours active</p>
