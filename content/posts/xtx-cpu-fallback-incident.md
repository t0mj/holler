---
title: "A kill→respawn race left my 7900 XTX serving at CPU speed for 2.5 hours"
date: 2026-09-06
draft: false
tags: [llama.cpp, llama-swap, vulkan, amd, rdna3, troubleshooting]
summary: "llama-swap's hot reload killed my 27B server; the respawn six seconds later landed on the dying server's VRAM residue and llama.cpp silently fell back to CPU. Nothing errored. Here's the failure, the A/B proof, and the 9-second probe I now run after every deploy."
crossposts: []
---

## TL;DR

- A llama-swap config hot-reload (triggered by a config deploy) killed my running 27B model server — a hot reload stops **all** running model servers, not just the one that changed.
- A new server spawned **6 seconds later**, while the dying server's ~20 GiB of VRAM was still draining. llama.cpp makes its offload decision once, at load time. It silently chose CPU, and the server then served correct tokens at CPU speed for the rest of its lifetime.
- Nothing errored. The KV/prefix cache worked. The prompt was cached. It was just 6–10× slower, for 2.5 hours, until the TTL cycled the server.
- The fix is cheap: a timed 200-token probe after every deploy (healthy ≈ 9–12 s wall; > ~40 s = CPU-fallback spawn → unload and re-request), plus a watchdog that checks fresh spawns for the RAM-resident signature.

## The setup

One box: Arch Linux, AMD RX 7900 XTX 24 GB, [llama-swap](https://github.com/mostlygeek/llama-swap) fronting llama.cpp Vulkan servers. Config-as-code: a deploy is an rsync of the YAML plus `systemctl reload`, which llama-swap hot-reloads (`-watch-config`).

## Symptoms

An agent session on the box started looking slow around 13:10 (the server had spawned at 13:09:29):

- Prompt eval pinned at 47–49 t/s (1,750 tok / 36.9 s · 2,345 tok / 51.9 s · 13,087 tok / 279 s)
- Decode 3.5–4.3 t/s at ~50k ctx, with MTP speculative decoding *active* (draft acceptance 0.51, mean accepted length 2.54)
- Baseline from the day before: cold prefill ≈ 243–276 t/s; a sibling 27B probe at pp 435–480 t/s, tg 32 → a 6–10× deficit. Classic 27B Q4 **CPU** signature.
- The KV/prefix cache was working: `selected slot by LCP similarity, sim_best = 0.999` — prompt preserved across turns, per-turn delta prefill only ~2k tokens. Not a re-prompt problem.

## Ruled out

- **Device pin:** `GGML_VK_VISIBLE_DEVICES` set correctly in the live process env; `vulkaninfo --summary` confirmed the device order.
- **Flags:** live command line byte-identical to the config entry (99 GPU layers, flash attention on, Q4 KV cache, draft-mtp n-max 3).
- **Driver/kernel:** 9 days uptime, no reboot, nothing changed since the previous day's A/B pass.
- **Contention:** no other GPU consumers; the other inference app on the box was idle.

## Root cause

1. 13:09:23 — config deploy → llama-swap hot-reload → the running model server is killed (it stops **all** servers, a trap I'd already recorded from an earlier incident).
2. 13:09:29 — a new server spawns, 6 s after the kill, while the dying server's ~17–22 GiB of VRAM is still draining. The load-time offload decision silently degrades to CPU. The server stays up. It serves correct tokens. Nothing errors.
3. Offload is decided **once, at load** → the degradation is locked in for the server's entire lifetime, here 2.5 h until the TTL cycled it.

Same failure class as the "flip within TTL" trap: *a freshly spawned server that finds VRAM residue can silently fall back to CPU*. The difference this time: the residue source was the killed sibling llama-server, not the other inference app's copy.

## A/B proof (same day, clean state)

| spawn | path | result |
|---|---|---|
| 13:09:29 | llama-swap, 6 s after kill | pp 47 / tg 3.6 t/s (the bad 2.5 h) |
| ~15:58 | scratch spawn, identical flags | 200 tok in 1.90 s = **105 t/s** decode; draft acceptance 0.92 |
| ~16:03 | llama-swap, fresh request | **9.0 s** wall for cold load + 200 tok; VRAM 22.3 GiB; VmRSS 1.27 GiB; GPU render fd open |

Same box, same model, same flags: 3.6 vs 105 t/s decode.

## The rule I now follow

After any llama-swap config deploy or reload: a timed 200-token probe per respawned model before relying on the box. Healthy ≈ 9–12 s wall (cold load + 200 tokens). **> ~40 s = CPU-fallback spawn** → `POST /api/models/unload/<model_id>` (all: `POST /api/models/unload`) and re-request — a clean respawn is fast.

Secondary: schedule config deploys around active sessions when possible.

## The watchdog

A small box-side service now polls the llama-swap `/running` endpoint every 10 s. On a fresh spawn it reads the server's `VmRSS` at +20 s and +90 s — above 8 GiB means the weights are in system RAM, which is this race's signature (healthy ≈ 0.9–1.3 GiB vs broken ≈ 16 GiB). When it sees that, it unloads the model so the next request respawns clean. On a config reload it pre-spawns previously-loaded models once VRAM is drained (< 1 GiB), to win the race before a client request does.

The watchdog's own first deploy had two bugs: a `pgrep` pattern that matched the model name instead of the port (every check false-negatived "no server"), and a re-rsync that stripped the exec bit and crash-looped the systemd unit for ~80 s. Shipping watchdogs is a fleet of one.

## Diagnostic traps from this run

- `ls /proc/<pid>/fd` on a dead (TTL-unloaded) pid reads as "no GPU fds" — verify the pid is alive first.
- Idle amdgpu sysfs values (`gpu_busy_percent`, `sclk`, `vram_used`) collapse to ~0 — sample during a live generation, not at rest.
- A 3 s-interval GPU sampler can miss a ~2 s decode window. End-to-end wall time of a fixed-token request (+ one VRAM read after load) is the speed test that can't be fooled.

## A grain of salt

Single box, single engine, one incident. Your llama-swap version, kernel, or driver may behave differently — the pattern (offload decided once at load + VRAM residue at spawn time) is the transferable part, not the exact thresholds.

I'm posting this in the hope it becomes part of a pile. Every time someone writes down the wall they hit — and how they got over it — the next person who hits the same wall spends an hour instead of a day. If you're running local models and hit something weird: post it. It might be the thing that saves me next month. And if you've hit the silent CPU fallback with a better probe than "time 200 tokens", even better — corrections get folded in with a note.
