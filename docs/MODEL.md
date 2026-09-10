# The model

Camping Buddy ships **one** model: **Ternary Bonsai 8B, Prism ML's ternary checkpoint packed as MLX 2-bit**. Nothing is bundled inside the app. The phone downloads the weights once through the in-app model manager, and the Mac evaluation path provisions the same pinned revision through the scripts below, so the two cannot drift apart.

| Item | Pinned value |
| --- | --- |
| Repository | `prism-ml/Ternary-Bonsai-8B-mlx-2bit` |
| Snapshot | `9260b24298e4211e804663e9f519962cf59f34be` |
| Base checkpoint | `prism-ml/Ternary-Bonsai-8B-unpacked` |
| Project directory (Mac evaluation) | `Resources/Models/Ternary-Bonsai-8B-mlx-2bit` |
| Total locked assets | 2,315,174,152 bytes (2.16 GiB), 9 files |
| Weights | One `model.safetensors`, 2,303,661,704 bytes, 907 tensors |
| Architecture | `qwen3`, `Qwen3ForCausalLM`, 36 layers, text only |
| Quantization | Ternary {-1, 0, +1} weights packed at 2 bits, group size 128 |
| Chat formatting | Unmodified local `chat_template.jinja` and tokenizer files |

`model-lock.json` records exact URLs, sizes, SHA-256 checksums, the source revision, and required configuration values. No model weights were fine-tuned, converted, stripped, or otherwise changed locally.

## Provision before running the Mac check

Run from the project directory with Python 3.9 or newer on the Mac while online:

```sh
python3 scripts/provision_model.py
python3 scripts/verify_model.py
```

No Python package installation, Hugging Face login, token, or subscription is required for this public snapshot. Provisioning downloads only the listed files, including the publisher's `LICENSE.txt` and `NOTICE.txt`. Large model assets stay outside source control; the lock and scripts stay in it.

This is a 2.16 GiB download into `Resources/Models/`, and it is only needed for the Mac evaluation path. The iPhone does not use it — the phone downloads its own copy through the app.

The downloader verifies completed files and reuses them. Interrupted transfers remain clearly marked `.part` under `.build/model-provision/Ternary-Bonsai-8B-mlx-2bit.download`; rerunning resumes where the host supports byte ranges. A file is moved out of `.part` only after its size and full checksum match. The final directory appears only after every file and the model structure verify, via an atomic directory rename. A separate advisory lock, `.build/model-provision/Ternary-Bonsai-8B-mlx-2bit.provision.lock`, prevents concurrent provisioners. Both staging and locking stay outside app resources, so partial downloads cannot be packaged by Xcode. It refuses symlinks, path traversal, and replacement of an existing invalid final bundle. If a checksum failure reports a specific partial or staged file, inspect and remove that specific file before retrying; do not delete other projects or model directories.

After a successful initial installation, both commands work without networking. Re-running the provisioner with a valid final bundle performs verification and makes no network requests.

Verification checks exact file membership, sizes, hashes, architecture/quantization, presence of a local tokenizer and template, tensor data boundaries, and coverage of every tensor by the shard index. It does not establish inference correctness, memory fit, latency, or camping advice quality.

## Runtime contract

The app passes an existing local model directory to MLX Swift LM's LLM loader. A missing or incompatible model must produce a visible failure state. The inference loader never receives a repository ID that could trigger an implicit download, and never uses an inference endpoint. The user-initiated download manager, documented in [MODEL_CATALOG.md](MODEL_CATALOG.md), checks pinned files before making them available to the local loader. Templates, special tokens, tokenizer, weights, and sources must all be present before generation.

No model code was written for this app. MLX Swift LM 3.31.4 registers `"qwen3"` in `LLMModelFactory`, and mlx-swift 0.31.4 supports 2-bit affine quantization with group size 128. The app uses the repository's own chat template unmodified and disables thinking mode.

Prism's `-mlx-1bit` line is **not** loadable here: `affine_quantize` rejects anything below 2 bits, and the loader converts every quantized layer through it. See [MODEL_CATALOG.md](MODEL_CATALOG.md#why-2-bit-and-not-prisms-1-bit-line).

Because there is only one model, there is no switching, no fallback, and no substitution. If the model is not downloaded, the app says so and does not answer.

## Memory

The Mac evaluation peaked at **2,584 MiB** in the MLX allocator — the allocator's process-lifetime peak, not total process memory, and a Mac is not a phone.

The app declares `com.apple.developer.kernel.increased-memory-limit` as headroom. At roughly 2.6 GB of allocator use the app would sit close to the ~3 GB ceiling an 8 GB iPhone applies without it. The phone figure is unknown until the device check runs.

## License and attribution

Prism ML published this checkpoint and its ternary training. The [repository](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit/tree/9260b24298e4211e804663e9f519962cf59f34be) and its card declare Apache-2.0, and the repository carries its own `LICENSE` and `NOTICE.txt`. Both are in the download manifest, so a downloaded copy on the phone keeps its own attribution rather than relying on this document. The card names `Ternary-Bonsai-8B-unpacked` as the base without pinning an upstream commit, which is why the lock repeats the conversion revision for `upstream_revision` and says so.

This local prototype is not a publication or a claim of endorsement.

## Validation status

**Mac: real generation, networking denied.** Ten scenarios ran through the shared engine under `scripts/no-network.sb`. Six produced cited answers, three were correctly routed without generation, and one fabricated source was caught and withheld. Load 0.49 s, first text 0.93–1.72 s, answers 1.93–4.27 s, allocator peak 2,584 MiB. See [VALIDATION.md](VALIDATION.md).

**iPhone: nothing.** The catalog entry stays `compatible-candidate` and the interface says "Compatible format · Not yet phone-tested".

The metadata was read from Hugging Face's primary model API at the pinned revision on 2026-09-10. Small assets were downloaded and hashed locally; the weight and `tokenizer.json` digests come from LFS metadata.

Earlier records under `evaluation/records/` describe **different models** — the Gemma 4 E2B baseline this project once shipped, and the Bonsai 27B 1-bit checkpoint that could not load. They are retained as history.

Do not infer phone memory requirements from the Mac allocator peak or from the download size. Record actual load/response/memory/failure behavior on the phone, and later battery and heat.
