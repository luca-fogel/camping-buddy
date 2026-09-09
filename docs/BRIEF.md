# Camping Buddy · first milestone

Camping Buddy is an iPhone camping companion designed to answer entirely on the phone with the Mac switched off and Wi-Fi/cellular disabled. The development plan includes adapting a camping model on an Apple Silicon Mac with MLX LoRA Studio and deploying those weights. Proving an actual phone inference path comes before a camping training run.

## Confirmed scope

English-language beginner weekend camping in the northeastern United States. A small native SwiftUI app offers text questions and an offline reference library for general packing, preparation, equipment, campsite setup, and food storage. Each question is independent; the chat transcript lives only in memory. The eight reference summaries are original development seed content grounded in NPS sources, not expert-reviewed production guidance.

Excluded from this milestone: accounts, cloud inference, voice, payments, App Store release, live weather or closure claims, medical diagnosis, and edible-plant identification. There is no silent endpoint or Apple-model fallback. Missing assets, load failures, uncited generated answers, and unsupported questions have explicit states.

## Model choice and proof required

The app ships exactly one model: **Bonsai 27B, Prism ML's MLX 1-bit conversion of Qwen3.6-27B**, loaded with MLX Swift LM 3.31.4 as text only. It is downloaded on the phone; nothing is bundled. There is no picker, no fallback, and no substitution — if it is not downloaded or will not load, the app says so.

*Superseded on 2026-09-09.* The first implementation used Gemma 4 E2B IT in ordinary MLX 4-bit, which was measured on the phone; a five-model library briefly followed it. Those records are retained in [VALIDATION.md](VALIDATION.md) and describe models the app no longer offers.

Bonsai 27B is a 4.78 GiB weight file at ~1.125 bits per weight. Its name is not a phone RAM estimate, and neither is its download size. The publisher targets a 12 GB iPhone 17 Pro Max; this project's phone is an 8 GB iPhone 15 Pro, so the app declares the increased memory limit entitlement and the load remains unproven. Use actual phone memory, response, and thermal measurements to decide suitability. [Model card](https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit), [base model](https://huggingface.co/Qwen/Qwen3.6-27B).

## Acceptance gate

A signed build installed on the intended iPhone contains model weights, configuration, tokenizer, chat template, and the reference library. After a cold launch with all network access disabled and Mac powered off, it generates real answers, opens cited passages locally, and reports unavailable evidence honestly. Record startup, first output, total answer delay, memory, and any OS termination. An unsigned build, simulator library test, or Mac model run is useful preparation but does not pass this gate.

## Working arrangement

This is a standalone implementation; no source was copied from Solvr. Model provisioning and future training experiments use project-local directories without modifying other projects or installed runtimes. Keep source content, training data, and held-out evaluation separate. Source publication does not mean the app has passed its offline, quality, or release gates.
