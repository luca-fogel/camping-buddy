# Camping Buddy · first milestone

Camping Buddy is an iPhone camping companion designed to answer entirely on the phone with the Mac switched off and Wi-Fi/cellular disabled. The development plan includes adapting a camping model on an Apple Silicon Mac with MLX LoRA Studio and deploying those weights. Proving an actual phone inference path comes before a camping training run.

## Confirmed scope

English-language beginner weekend camping in the northeastern United States. A small native SwiftUI app offers text questions and an offline reference library for general packing, preparation, equipment, campsite setup, and food storage. Each question is independent; the chat transcript lives only in memory. The eight reference summaries are original development seed content grounded in NPS sources, not expert-reviewed production guidance.

Excluded from this milestone: accounts, cloud inference, voice, payments, App Store release, live weather or closure claims, medical diagnosis, and edible-plant identification. There is no silent endpoint or Apple-model fallback. Missing assets, load failures, uncited generated answers, and unsupported questions have explicit states.

## Model choice and proof required

The app ships exactly one model: **Ternary Bonsai 8B, Prism ML's ternary checkpoint packed as MLX 2-bit**, loaded with MLX Swift LM 3.31.4 as text only. It is downloaded on the phone; nothing is bundled. There is no picker, no fallback, and no substitution — if it is not downloaded or will not load, the app says so.

*History.* The first implementation used Gemma 4 E2B IT in ordinary MLX 4-bit and was measured on the phone; a five-model library briefly followed; on 2026-09-09 the app was cut to a single model. Bonsai 27B 1-bit was that single model for one day and **could not load** — stock MLX has no sub-2-bit affine quantization — so the 2-bit ternary checkpoint replaced it on 2026-09-10. Those records are retained in [VALIDATION.md](VALIDATION.md) and describe models the app no longer offers.

Ternary Bonsai 8B is a 2.16 GiB download. Its parameter count is not a phone RAM estimate, and neither is its download size: the Mac evaluation peaked at 2,584 MiB in the MLX allocator, which is a Mac number. Use actual phone memory, response, and thermal measurements to decide suitability. [Model card](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit).

## Acceptance gate

A signed build installed on the intended iPhone contains model weights, configuration, tokenizer, chat template, and the reference library. After a cold launch with all network access disabled and Mac powered off, it generates real answers, opens cited passages locally, and reports unavailable evidence honestly. Record startup, first output, total answer delay, memory, and any OS termination. An unsigned build, simulator library test, or Mac model run is useful preparation but does not pass this gate.

## Working arrangement

This is a standalone implementation; no source was copied from Solvr. Model provisioning and future training experiments use project-local directories without modifying other projects or installed runtimes. Keep source content, training data, and held-out evaluation separate. Source publication does not mean the app has passed its offline, quality, or release gates.
