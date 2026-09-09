# Model catalog

The app ships one model: **Bonsai 27B**, Prism ML's 1-bit MLX conversion of Qwen3.6-27B. There is no model picker, no fallback, and no second choice. The catalog file still exists because it is the runtime contract that pins the download — repository, revision, every file, and every hash — not because there is anything to choose between.

The single entry is a **compatible candidate**. Configuration and template checks support loading it with MLX Swift LM 3.31.4, and the publisher documents MLX Swift support. Those checks do not establish successful inference, acceptable memory use, or answer quality on this project's phone.

## The shipped snapshot

| | |
| --- | --- |
| Model | [Bonsai 27B, MLX 1-bit](https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit/tree/ef22f239c670078e1507f9769bcaa66657332b96) |
| Revision | `ef22f239c670078e1507f9769bcaa66657332b96` |
| Download | 5,159,412,937 bytes (5.159 GB decimal, 4.81 GiB) across 11 assets |
| Weights | `model.safetensors`, 5,129,115,752 bytes in one file |
| Base model | [Qwen/Qwen3.6-27B](https://huggingface.co/Qwen/Qwen3.6-27B) |
| License | [Apache-2.0](https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit/blob/ef22f239c670078e1507f9769bcaa66657332b96/LICENSE.txt) |
| Quantization | 1-bit affine, group size 128; the publisher describes a true ~1.125 bits per weight |
| Evidence | Metadata and architecture checked. No iPhone generation test. |

Download size is disk size, **not peak memory**. `LICENSE.txt` and `NOTICE.txt` are downloaded with the weights, so the attribution travels with the files rather than depending on this document.

## Why this model loads at all

Three things had to be true, and each was checked against the pinned dependencies rather than assumed:

- **Architecture.** `config.json` declares `model_type: qwen3_5` with a nested `text_config` of `qwen3_5_text`. MLX Swift LM 3.31.4 registers `"qwen3_5"` in `LLMModelFactory`, and its `Qwen35.swift` implements the hybrid backbone this config uses — 64 mixed `layer_types` with `GatedDeltaNet` linear attention and `full_attention_interval: 4`. No model code was written for this app.
- **Quantization.** MLX only rejects `bits <= 0`; 1-bit affine dequantization is supported by the pinned mlx-swift 0.31.4. The catalog validator's allowed widths were widened from `[2,3,4,5,6,8]` to include 1.
- **Modality.** The architecture string is `Qwen3_5ForConditionalGeneration` and the repository carries a vision tower in 4-bit HQQ, along with image and video preprocessor configurations. Those preprocessor files are deliberately **not** in the download manifest: `model_type` routes through the text factory, and the app never sends an image.

## Memory, which is the open risk

The publisher reports a **~3.9 GB deployed footprint and ~11 tok/s on an iPhone 17 Pro Max**, a 12 GB device. This project's verified phone is an **iPhone 15 Pro with 8 GB**.

The app therefore declares `com.apple.developer.kernel.increased-memory-limit` (`Resources/Entitlements/CampingBuddy.entitlements`). Without it an 8 GB device caps a foreground app near 3 GB and the load is killed outright. With it the ceiling rises but does not disappear, and a 4.8 GiB weight file plus a KV cache may still be refused. The 262K-token context the publisher advertises is not a context this app attempts to fill; requests are short and each Ask starts a fresh session.

**No load has been attempted on a phone yet.** Until it has, treat the memory question as open, and expect a jetsam kill rather than a graceful error if it fails.

## Download and storage workflow

The transfer starts only after an explicit download action. URLs come from the bundled catalog's pinned repository, revision, and file path. The downloader accepts trusted HTTPS model hosts and checks redirects. The app does not import arbitrary model URLs, local folders, or executable model code. Opening a source link is a separate online action; model loading and generation use local files.

Downloads go into app-owned staging storage excluded from device backups. Before a transfer, storage removes abandoned `transfer-UUID` files for that inactive model and checks available disk space for the remaining assets plus a 256 MiB reserve. Other device activity can still consume space after this check. Keep the app open until the download finishes; there is no background-download guarantee, and this is a large file to lose.

Pause cancels the current transfer: completed files remain, are verified again on retry, and are reused only if they match the manifest. The interrupted current file starts over; this is file-level recovery, not byte-range resume. Because the weights are a single 4.78 GiB asset, an interruption during that file costs the whole of it.

Each asset must match its exact size and recorded SHA-256 or small-file Git blob digest. The full set is verified again — architecture, quantization, local chat template, and the weight index's shard coverage — before a ready marker is written and the staging directory is atomically promoted. A failed or incomplete transfer is never selectable. Downloaded files are hashed before first use in each app session and again if their file metadata changes.

The ready marker fingerprints the model's revision and asset identity, so an incompatible catalog update cannot silently reuse an older installed copy. A model held by the chat coordinator, during loading or generation, cannot be removed. Otherwise the download **can** be removed, including while it is the selection: with one model that is the only way to reclaim 4.8 GB short of deleting the app, and the app simply reports that no model is installed until it is downloaded again. Network errors, cancellation, insufficient space, checksum failure, and unavailable runtime support remain reported failures, not evidence that a model was tested successfully.

## Provenance and reproducibility

`Resources/ModelCatalog/catalog.json` is the runtime contract. `scripts/model_catalog_source.json` holds the immutable metadata observations and `scripts/generate_model_catalog.py` turns them into the catalog.

The metadata came from Hugging Face's primary model API, first resolving a revision and then reading `/api/models/<repository>/revision/<commit>?blobs=true` on 2026-09-09. Only the configuration, tokenizer configuration, templates, card, vocabulary, merges, and shard index were downloaded, and their SHA-256 values were computed from those bytes. The weight and `tokenizer.json` SHA-256 values come from LFS metadata; **the weights were not downloaded for catalog assembly**. Git assets use the repository's Git blob SHA-1 only when at most 16 MiB; larger assets require SHA-256. A Git blob digest hashes `blob <byte-count>\0` followed by the bytes, not just the file contents.

Generate or verify entirely offline:

```sh
python3 scripts/generate_model_catalog.py
python3 scripts/generate_model_catalog.py --check
```

The generator validates the publisher, the immutable revision, paths, required assets, hash formats, quantization, the per-asset size ceiling, and the exact total. It never resolves `main` or performs a download. A refresh means deliberately updating the embedded observations after inspecting primary metadata and the pinned runtime, then reviewing the generated diff. Download-time verification must still check every listed asset before selection.

`model-lock.json` pins the same repository and revision for the Mac evaluation path, so `CampingModelCheck` and the provisioning scripts cannot drift onto a different model from the one the app ships.

## Validation boundary

Nothing here is device evidence. The catalog entry is labeled `compatible-candidate`, and the app's own interface says "Compatible format · Not yet phone-tested" until that changes.

The next test is the obvious one: download and verify the model in the app, load it on the physical iPhone, ask a saved-guide question, and inspect both the raw draft and the cited guide. Record device, model, revision, load time, first-output time, total answer time, and the MLX allocator peak before changing a validation label. Because of the memory question above, record whether the app survived the load at all — a jetsam kill is a result worth writing down. A successful single answer is still not a camping-safety or broad model-quality evaluation.
