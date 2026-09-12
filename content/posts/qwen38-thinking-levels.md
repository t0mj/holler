---
title: "Qwen3.8's thinking knob is not a volume knob"
date: 2026-09-07
draft: false
tags: [llama.cpp, qwen, reasoning, thinking-models, amd, rdna3]
summary: "off / low / medium / xhigh on the same 27B model, same trap prompt, temp 0 — xhigh turns out to be a near-duplicate of default, the instruction-less 'medium' thinks more than 'low', and no level drifted off the right answer."
crossposts: []
---

## TL;DR

- I ran the Qwen3.8-27B thinking knob through four positions — `off`, `low`, `medium`, `xhigh` — on one fixed multiple-choice trap prompt, temp 0, and measured the thinking trace and the prompt each one produced.
- **The knob is a set of instructions, not a volume control.** The model's own chat template decides what each level means, and the measured prompt fingerprints prove it: `low` adds a ~30-token reasoning instruction, `medium` adds **nothing at all**.
- **The dial has three real states, not five.** `xhigh`'s output was a near-duplicate of `default` — same 111 prompt tokens, same 213 completion tokens, traces identical down to the last clause. The xhigh branch is a near-verbatim copy of the default branch's own instruction.
- **Instructions don't set the length of the thinking.** `medium` — the position with no instruction — produced a *longer* trace than `low` (477 vs 454 chars). And the self-doubt drift I was looking for showed up at **no** level: every trace committed to the right answer within its first 1–3 sentences.

## Why I looked at this

My day-to-day coding agent runs on this model. What I kept noticing in the highest-thinking traces: the model would work through the problem, **arrive at the right option, keep thinking, and talk itself toward the wrong one** — the actual output still picked the right answer, but the thinking context had wandered past it. The more "reasoning" I was buying, the more I seemed to be buying second-guessing.

So I built a small deterministic probe: one prompt with a unique correct answer and a classic misread as the distractor, run through every thinking level, and I read the traces. I expected the drift to show up at `xhigh`. It didn't. The knob turned out to be stranger than the drift was.

## The setup

The model is the Q4_K_M gate on my 24 GB 7900 XTX box — that's the one from [the quant comparison post](/holler/posts/qwen38-xtx-quant-comparison/) (Q4_K_M, 15.64 GiB, pinned at 185k ctx), served by llama-swap over llama.cpp **b9999** (`47c7869`), Vulkan. (The box itself has [a post worth reading](/holler/posts/xtx-cpu-fallback-incident/) about how a respawn race left it serving at CPU speed for 2.5 hours.)

The prompt — one, identical byte-for-byte at every level, `temperature: 0`, `max_tokens: 4096`:

```
A farmer has 17 sheep. All but 9 die. How many sheep are left?
A) 8
B) 9
C) 17
D) 26
Think step by step, then end with your answer as a single option letter.
```

The correct answer is **B** — "all but 9" means 9 survive. The classic misread is 17 − 9 = 8, which is option A. That's exactly where a self-doubt spiral lands, which made this a good overthinking trap.

The levels, as per-request `chat_template_kwargs`:

| level | kwargs |
|---|---|
| default | *(none — whatever the server does by default)* |
| off | `{"enable_thinking": false}` |
| low | `{"enable_thinking": true, "reasoning_effort": "low"}` |
| medium | `{"enable_thinking": true, "reasoning_effort": "medium"}` |
| xhigh | `{"enable_thinking": true, "reasoning_effort": "xhigh"}` |

## The knob, as the template actually defines it

Here's the piece that makes the results make sense. I pulled the chat template out of the GGUF (`gguf-py`, key `tokenizer.chat_template`) and read the `reasoning_effort` branches. The template is **asymmetric**:

- `low` — injects a reasoning instruction into the prompt
- `xhigh` — injects a reasoning instruction
- `medium` — **injects nothing. Empty branch, by design.**

So "medium" isn't half volume — it's the template choosing not to tell the model to reason at all. And "low" isn't a little thinking — it's an explicit instruction to.

The prompt-token fingerprint from the box agrees with the template exactly:

| level | prompt tokens |
|---|---:|
| off | 71 |
| medium | 69 |
| low | 99 |
| default | 111 |
| xhigh | 111 |

`low` = `medium` + 30 → that's low's instruction. `default` = `medium` + 42 → the default branch carries **its own** thinking instruction, a bigger one. `xhigh` = `default` to the token, differing only in the last ~4 prompt tokens.

## The grid

| level | wall (s) | prompt tokens | completion tokens | reasoning (chars) | content (chars) | answer |
|---|---:|---:|---:|---:|---:|:--:|
| default | 3.40 | 111 | 213 | 773 | 41 | B ✓ |
| off | 3.02 | 71 | 242 | 0 | 825 | B ✓ |
| low | 3.31 | 99 | 245 | 454 | 384 | B ✓ |
| medium | 2.81 | 69 | 220 | 477 | 239 | B ✓ |
| xhigh | 2.80 | 111 | 213 | 775 | 41 | B ✓ |

Five calls, zero retries, all `finish_reason: stop` — no level hit the token cap. Two shape notes if you're reproducing this: the trace comes back in a `reasoning_content` field (clean `content`, no reasoning tags inside it), and `usage` does **not** split reasoning vs content tokens — char counts are the measurement, and anything token-shaped derived from them is an estimate (~3.8–4 chars/token observed here). Wall time isn't an effort proxy: it's ~200 tokens of generation at ~80 t/s, and the whole spread is 2.8–3.4 s.

## What the traces actually show

All five land on B. The interesting part is *how*:

- **default** commits in the first inference pass — *"All but 9 die" means 9 survive. So B.* — and the remaining trace is format-wrangling only: *"Ensure final ends with B maybe only B?"*
- **off** has no trace at all. The 825-char direct answer works the phrasing, names the trap ("the common mistake is to subtract 9 from 17"), walks all four options with A marked *(Incorrect: This is the number that died)* — and its final line is just *B*.
- **low** pre-empts the trap: *"This is a common trick question where people might subtract 9 from 17 to get 8, but the correct interpretation is that 'all but 9' means 9 remain."*
- **medium** gets the best line of the day: *"Let me make sure I'm not overthinking this. … The answer is B) 9."*
- **xhigh** is default. The *only* textual difference in the entire pair of traces: "Ensure last is B." (default) vs "Ensure ends with B." (xhigh).

And the drift I was hunting: **not present at any level.** Every thinking trace commits within its first 1–3 sentences, then verifies or formats. The 17−9=8 misread appears only as an *explicitly refuted* distractor — the model names the trap it never entertains. To be honest about the negative: the overthinking I saw in agent-workload traces was real, and this probe is too shallow to reproduce it. On a one-step riddle there's no room to wander. The drift is probably a function of context length and task shape, not the level alone — that's the follow-up I'm parking, not a verdict that it doesn't exist.

## So which level do you run at

The effective dial is four positions: `off` / `low` / `medium` / `default` — and `xhigh` is `default` wearing a scarier name. The labels and the semantics don't line up:

- **"medium"** is the model thinking at its own default, no instruction attached. On this prompt it thought *more* than the position with the explicit "reason" instruction.
- **"low"** is a short instruction. It changed *where* the thinking went (it's the level that named and refuted the trap by name) more than *how long* it was.
- **"xhigh"** is a duplicate of the free default. If your consumer is sending it, you're paying prompt tokens for a label.

My agent's fleet default is thinking-off, and this data says that's defensible on this model: no trace, still walked every option, still refuted the distractor. My stance: the level is a **prompt, not a dial** — read your build's template branches before you benchmark, and pick the level for what its instruction says, not for what its name promises.

## A grain of salt

One box, one model, one quant, one shallow prompt, temp 0, one shot per level. Char counts, not token counts (the API doesn't split them). One genuine wobble in the data: `xhigh` ran with 107 of its 111 prompt tokens cached, and spec-decode (draft-mtp, ~61% acceptance) was live and stochastic — that's my prime suspect for the ~4-token divergence between default and xhigh, and a byte-reproducible rerun would need the spec flags off. The interesting output here is the *behavior of the knob*, not a leaderboard. If you've read Qwen3.8-class thinking traces at different levels — especially if your template's branches don't match mine, or your `xhigh` isn't a duplicate — post it. Knowing what the middle position of the knob actually does is the kind of thing I'd rather learn from your logs.
