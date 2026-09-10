# Model catalog

The app ships one model: **Ternary Bonsai 8B**, Prism ML's ternary checkpoint packed as MLX 2-bit. There is no model picker, no fallback, and no second choice. The catalog file still exists because it is the runtime contract that pins the download — repository, revision, every file, and every hash — not because there is anything to choose between.

## The shipped snapshot

| | |
| --- | --- |
| Model | [Ternary Bonsai 8B, MLX 2-bit](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit/tree/9260b24298e4211e804663e9f519962cf59f34be) |
| Revision | `9260b24298e4211e804663e9f519962cf59f34be` |
| Download | 2,315,174,152 bytes (2.32 GB decimal, 2.16 GiB) across 9 assets |
| Weights | `model.safetensors`, 2,303,661,704 bytes in one file |
| Architecture | `qwen3`, `Qwen3ForCausalLM`, 36 layers, text only |
| Quantization | Ternary {-1, 0, +1} weights packed at 2 bits, group size 128 |
| License | [Apache-2.0](https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit/blob/9260b24298e4211e804663e9f519962cf59f34be/LICENSE) |
| Evidence | **Real Mac generation, networking denied.** No iPhone test yet. |

Download size is disk size, not peak memory. `LICENSE` and `NOTICE.txt` are downloaded with the weights, so attribution travels with the files rather than depending on this document.

## Why 2-bit and not Prism's 1-bit line

Prism ML also publishes a `-mlx-1bit` line, including a 27B. **Those cannot load on stock MLX**, and this was established by trying it, not by reading:

```
[quantize] The requested number of bits 1 is not supported.
The supported bits are 2, 3, 4, 5, 6 and 8.
```

`MLXLMCommon/Load.swift:41` reads the `quantization` block from `config.json` and calls `quantize(model:)` to convert every layer that has loaded scales into a `QuantizedLinear`. That conversion runs `affine_quantize`, which rejects anything below 2 bits *before* the real weights are ever applied. `dequantize` does accept 1 bit, but it is not on the load path — reading only that function gives a false positive for support.

No version bump fixes this: upstream `ml-explore/mlx` `main` carries the same 2–8 bit whitelist, and mlx-swift's newest release is 0.31.6. Prism's card advertises "custom 1-bit hybrid-attention kernels on Apple MLX", which is consistent with that path living in their own kernels. The full record is in [`evaluation/records/mac-bonsai27b-1bit-load-failure.json`](../evaluation/records/mac-bonsai27b-1bit-load-failure.json).

The catalog validator and the generator therefore both refuse a sub-2-bit entry. A 1-bit entry passes every metadata and hash check and then dies at load, so the guard belongs in the catalog rather than in a reviewer's memory.

## Memory

The Mac evaluation peaked at **2,584 MiB** in the MLX allocator for this model. That is the allocator's process-lifetime peak, not total process memory, and a Mac is not a phone.

The app still declares `com.apple.developer.kernel.increased-memory-limit`. At roughly 2.6 GB of allocator use the app would be close to the ~3 GB ceiling an 8 GB iPhone applies without it, so the entitlement is retained as headroom rather than as the thing that makes the load possible at all. The phone figure is unknown until the device check runs.

## Download and storage workflow

The transfer starts only after an explicit download action. URLs come from the bundled catalog's pinned repository, revision, and file path. The downloader accepts trusted HTTPS model hosts and checks redirects. The app does not import arbitrary model URLs, local folders, or executable model code. Opening a source link is a separate online action; model loading and generation use local files.

Downloads go into app-owned staging storage excluded from device backups. Before a transfer, storage removes abandoned `transfer-UUID` files for that inactive model and checks available disk space for the remaining assets plus a 256 MiB reserve. Other device activity can still consume space after this check. Keep the app open until the download finishes; there is no background-download guarantee.

Pause cancels the current transfer: completed files remain, are verified again on retry, and are reused only if they match the manifest. The interrupted current file starts over; this is file-level recovery, not byte-range resume. The weights are a single 2.3 GB asset, so an interruption during that file costs the whole of it.

Each asset must match its exact size and recorded SHA-256 or small-file Git blob digest. The full set is verified again — architecture, quantization, local chat template, and the weight index's shard coverage — before a ready marker is written and the staging directory is atomically promoted. A failed or incomplete transfer is never selectable. Downloaded files are hashed before first use in each app session and again if their file metadata changes.

The ready marker fingerprints the model's revision and asset identity, so an incompatible catalog update cannot silently reuse an older installed copy. A model held by the chat coordinator, during loading or generation, cannot be removed. Otherwise the download **can** be removed, including while it is the selection: with one model that is the only way to reclaim the space short of deleting the app, and the app reports that no model is installed until it is downloaded again. Network errors, cancellation, insufficient space, checksum failure, and unavailable runtime support remain reported failures, not evidence that a model was tested successfully.

## Provenance and reproducibility

`Resources/ModelCatalog/catalog.json` is the runtime contract. `scripts/model_catalog_source.json` holds the immutable metadata observations and `scripts/generate_model_catalog.py` turns them into the catalog.

The metadata came from Hugging Face's primary model API, first resolving a revision and then reading `/api/models/<repository>/revision/<commit>?blobs=true` on 2026-09-10. Only the configuration, tokenizer configuration, template, card, and shard index were downloaded, and their SHA-256 values were computed from those bytes. The weight and `tokenizer.json` digests come from LFS metadata; **the weights were not downloaded for catalog assembly**. Git assets use the repository's Git blob SHA-1 only when at most 16 MiB; larger assets require SHA-256. A Git blob digest hashes `blob <byte-count>\0` followed by the bytes, not just the file contents.

Generate or verify entirely offline:

```sh
python3 scripts/generate_model_catalog.py
python3 scripts/generate_model_catalog.py --check
```

The generator validates the publisher, the immutable revision, paths, required assets, hash formats, quantization, the per-asset size ceiling, and the exact total. It never resolves `main` or performs a download.

`model-lock.json` pins the same repository and revision for the Mac evaluation path, so `CampingModelCheck` and the provisioning scripts cannot drift onto a different model from the one the app ships. The CLI also passes the catalog descriptor into the engine: without it the engine falls back to a placeholder identity, and an early run of this model was recorded under the wrong model's name.

## Validation boundary

There is now real inference evidence, on a Mac, with networking denied at the process level. See [VALIDATION.md](VALIDATION.md) for the ten-scenario results, including the case where the model fabricated a source and the app withheld the answer.

There is still **no iPhone evidence**. The catalog entry stays `compatible-candidate` and the interface still says "Compatible format · Not yet phone-tested" until the device check runs. A Mac result establishes that the checkpoint loads and generates cited answers; it says nothing about phone memory, latency, battery, or heat.
