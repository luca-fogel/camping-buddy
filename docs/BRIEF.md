# Camping Buddy · first milestone

Camping Buddy is an iPhone camping companion designed to answer entirely on the phone with the Mac switched off and Wi-Fi/cellular disabled. The development plan includes adapting a camping model on an Apple Silicon Mac with MLX LoRA Studio and deploying those weights. Proving an actual phone inference path comes before a camping training run.

## Confirmed scope

English-language beginner weekend camping in the northeastern United States. A small native SwiftUI app offers text questions and an offline reference library for general packing, preparation, equipment, campsite setup, and food storage. Each question is independent; the chat transcript lives only in memory. The eight reference summaries are original development seed content grounded in NPS sources, not expert-reviewed production guidance.

Excluded from this milestone: accounts, cloud inference, voice, payments, App Store release, live weather or closure claims, medical diagnosis, and edible-plant identification. There is no silent endpoint or Apple-model fallback. Missing assets, load failures, uncited generated answers, and unsupported questions have explicit states.

## Model choice and proof required

The selected model family is Gemma 4 E2B. The first implementation uses **Gemma 4 E2B IT in ordinary MLX 4-bit format**, with MLX Swift LM 3.31.4 and text-only loading. This follows the documented MLX route and allows a later fused-weight export from Mac adaptation. This artifact is distinct from Google's mobile QAT model for LiteRT-LM. It does not establish the mobile-QAT pipeline, quality, RAM, or latency. If that specific mobile artifact is required, benchmark the LiteRT Swift route separately before settling the shipping runtime.

Gemma E2B has about 2.3B effective parameters and 5.1B including embeddings; its name is not a phone RAM estimate. Use actual phone memory, response, and thermal measurements to decide suitability. [Google model card](https://ai.google.dev/gemma/docs/core/model_card_4), [Google MLX integration](https://ai.google.dev/gemma/docs/integrations/mlx), [mobile QAT distinction](https://huggingface.co/google/gemma-4-E2B-it-qat-mobile-transformers).

## Acceptance gate

A signed build installed on the intended iPhone contains model weights, configuration, tokenizer, chat template, and the reference library. After a cold launch with all network access disabled and Mac powered off, it generates real answers, opens cited passages locally, and reports unavailable evidence honestly. Record startup, first output, total answer delay, memory, and any OS termination. An unsigned build, simulator library test, or Mac model run is useful preparation but does not pass this gate.

## Working arrangement

This is a standalone implementation; no source was copied from Solvr. Model provisioning and future training experiments use project-local directories without modifying other projects or installed runtimes. Keep source content, training data, and held-out evaluation separate. Source publication does not mean the app has passed its offline, quality, or release gates.
