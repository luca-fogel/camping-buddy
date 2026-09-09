# The model

Camping Buddy ships **one** model: **Bonsai 27B, Prism ML's MLX 1-bit conversion of Qwen3.6-27B**. Nothing is bundled inside the app. The phone downloads the weights once through the in-app model manager, and the Mac evaluation path provisions the same pinned revision through the scripts below, so the two cannot drift apart.

| Item | Pinned value |
| --- | --- |
| Repository | `prism-ml/Bonsai-27B-mlx-1bit` |
| Snapshot | `ef22f239c670078e1507f9769bcaa66657332b96` |
| Base model | `Qwen/Qwen3.6-27B` |
| Project directory (Mac evaluation) | `Resources/Models/Bonsai-27B-mlx-1bit` |
| Total locked assets | 5,159,412,937 bytes (4.81 GiB), 11 files |
| Weights | One `model.safetensors`, 5,129,115,752 bytes |
| Architecture | `qwen3_5`, nested `qwen3_5_text`, 64 layers, hybrid linear attention every 4th layer |
| Quantization | Affine 1-bit, group size 128 (~1.125 bits per weight per the publisher) |
| Included modalities | The snapshot carries a 4-bit HQQ vision tower; this app uses text only and does not download the preprocessor configs |
| Chat formatting | Unmodified local `chat_template.jinja` and tokenizer files |

`model-lock.json` records exact URLs, sizes, SHA-256 checksums, the source revision, and required configuration values. No model weights were fine-tuned, converted, stripped, or otherwise changed locally.

## Provision before running the Mac check

Run from the project directory with Python 3.9 or newer on the Mac while online:

```sh
python3 scripts/provision_model.py
python3 scripts/verify_model.py
```

No Python package installation, Hugging Face login, token, or subscription is required for this public snapshot. Provisioning downloads only the listed files, including the publisher's `LICENSE.txt` and `NOTICE.txt`. Large model assets stay outside source control; the lock and scripts stay in it.

This is a 4.81 GiB download into `Resources/Models/`, and it is only needed for the Mac evaluation path. The iPhone does not use it — the phone downloads its own copy through the app.

The downloader verifies completed files and reuses them. Interrupted transfers remain clearly marked `.part` under `.build/model-provision/Bonsai-27B-mlx-1bit.download`; rerunning resumes where the host supports byte ranges. A file is moved out of `.part` only after its size and full checksum match. The final directory appears only after every file and the model structure verify, via an atomic directory rename. A separate advisory lock, `.build/model-provision/Bonsai-27B-mlx-1bit.provision.lock`, prevents concurrent provisioners. Both staging and locking stay outside app resources, so partial downloads cannot be packaged by Xcode. It refuses symlinks, path traversal, and replacement of an existing invalid final bundle. If a checksum failure reports a specific partial or staged file, inspect and remove that specific file before retrying; do not delete other projects or model directories.

After a successful initial installation, both commands work without networking. Re-running the provisioner with a valid final bundle performs verification and makes no network requests.

Verification checks exact file membership, sizes, hashes, architecture/quantization, presence of a local tokenizer and template, tensor data boundaries, and coverage of every tensor by the shard index. It does not establish inference correctness, memory fit, latency, or camping advice quality.

## Runtime contract

The app passes an existing local model directory to MLX Swift LM's LLM loader. A missing or incompatible model must produce a visible failure state. The inference loader never receives a repository ID that could trigger an implicit download, and never uses an inference endpoint. The user-initiated download manager, documented in [MODEL_CATALOG.md](MODEL_CATALOG.md), checks pinned files before making them available to the local loader. Templates, special tokens, tokenizer, weights, and sources must all be present before generation.

No model code was written for this app. MLX Swift LM 3.31.4 registers `"qwen3_5"` in `LLMModelFactory` and implements the hybrid `GatedDeltaNet` layers this checkpoint uses; mlx-swift 0.31.4 accepts 1-bit affine quantization. The app uses the repository's own chat template unmodified and disables thinking mode.

Because there is only one model, there is no switching, no fallback, and no substitution. If the model is not downloaded, the app says so and does not answer.

## Memory

Bonsai 27B is a 4.78 GiB weight file that must be resident to generate. The app declares `com.apple.developer.kernel.increased-memory-limit`; without it an 8 GB iPhone is killed during the load. The publisher reports a ~3.9 GB deployed footprint and ~11 tok/s on a 12 GB iPhone 17 Pro Max. This project's verified phone is an 8 GB iPhone 15 Pro, and **the load has not been attempted there yet**. See [MODEL_CATALOG.md](MODEL_CATALOG.md#memory-which-is-the-open-risk).

## License and attribution

Prism ML published this conversion; Qwen published the `Qwen3.6-27B` base model. The [repository](https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit/tree/ef22f239c670078e1507f9769bcaa66657332b96) and its card declare Apache-2.0, and the repository carries its own `LICENSE.txt` and `NOTICE.txt`. Both are in the download manifest, so a downloaded copy on the phone keeps its own attribution rather than relying on this document. The model card names the base model without pinning an upstream commit, which is why the lock repeats the conversion revision for `upstream_revision` and says so.

This local prototype is not a publication or a claim of endorsement.

## Validation status

**None on a phone.** The catalog entry is `compatible-candidate`, and the app's interface says "Compatible format · Not yet phone-tested".

The metadata was read from Hugging Face's primary model API at the pinned revision on 2026-09-09. Small assets were downloaded and hashed locally; the weight and `tokenizer.json` digests come from LFS metadata. Architecture support was confirmed by reading the pinned `mlx-swift-lm` and `mlx-swift` sources rather than by loading the model.

Earlier records under `evaluation/records/` describe a **different model** — the Gemma 4 E2B baseline this project previously shipped. They are retained as history and are not evidence about Bonsai. See [VALIDATION.md](VALIDATION.md).

Do not infer memory requirements from the download size or from simulator results. Record actual load/response/memory/failure behavior on the phone, and later battery and heat.
