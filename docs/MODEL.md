# Bundled model

The selected first prototype model is **Gemma 4 E2B IT, MLX affine 4-bit**, following [Google's MLX integration example](https://ai.google.dev/gemma/docs/integrations/mlx). This is the community MLX conversion of the instruction-tuned model; it is a separate artifact from Google's LiteRT Mobile QAT exports. Its iPhone suitability must be measured on the target phone.

| Item | Pinned value |
| --- | --- |
| Repository | `mlx-community/gemma-4-E2B-it-4bit` |
| Snapshot | `238767527555cb75a05732a84dff5d6ba0dd6809` |
| Google source | `google/gemma-4-E2B-it` at `70af34e20bd4b7a91f0de6b22675850c43922a03` |
| App resource directory | `Models/gemma-4-E2B-it-4bit` |
| Project directory | `Resources/Models/gemma-4-E2B-it-4bit` |
| Total locked bundle | 3,583,125,193 bytes (3.337 GiB), 11 files |
| Weights | One `model.safetensors`, 3,550,670,554 bytes |
| Architecture | `gemma4`, nested `gemma4_text`, 35 text layers, 20 shared-KV layers |
| Quantization | Affine 4-bit, group size 64 |
| Included modalities | Original snapshot includes text, audio, and vision configuration/weights; this app uses text only |
| Chat formatting | Unmodified local `chat_template.jinja` and tokenizer files |

`model-lock.json` records exact URLs, sizes, SHA-256 checksums, source revision, and required configuration values. The original conversion snapshot is preserved. No model weights were fine-tuned, converted, stripped, or otherwise changed locally.

## Provision before building

Run from the project directory with Python 3.9 or newer on the Mac while online:

```sh
python3 scripts/provision_model.py
python3 scripts/verify_model.py
```

No Python package installation, Hugging Face login, token, or subscription is required for this public snapshot. Provisioning downloads only the listed files, including both model cards and the full license text. Large model assets should remain outside source control. Preserve the lock and scripts in source control.

The downloader verifies completed files and reuses them. Interrupted transfers remain clearly marked `.part` under `.build/model-provision/gemma-4-E2B-it-4bit.download`; rerunning resumes where the host supports byte ranges. A file is moved out of `.part` only after its size and full checksum match. The final directory appears only after every file and the model structure verify, via an atomic directory rename. A separate advisory lock, `.build/model-provision/gemma-4-E2B-it-4bit.provision.lock`, prevents concurrent provisioners. Both staging and locking stay outside app resources, so partial downloads cannot be packaged by Xcode. It refuses symlinks, path traversal, and replacement of an existing invalid final bundle. If a checksum failure reports a specific partial or staged file, inspect and remove that specific file before retrying; do not delete other projects or model directories.

After a successful initial installation, both commands work without networking. Re-running the provisioner with a valid final bundle performs verification and makes no network requests. The verifier can also check the files copied into a built app:

```sh
python3 scripts/verify_model.py --directory /absolute/path/CampingBuddy.app/Models/gemma-4-E2B-it-4bit
```

Verification checks exact file membership, sizes, hashes, architecture/quantization, presence of a local tokenizer and template, tensor data boundaries, and coverage of every tensor by the shard index. It does not establish inference correctness, memory fit, latency, or camping advice quality.

## Runtime contract

The app must pass an existing local model directory to MLX Swift LM's LLM loader. A missing or incompatible bundle must produce a visible failure state. It must never use a repository ID that can trigger runtime downloading, an inference endpoint, or another built-in model as fallback. Templates, special tokens, tokenizer, weights, and sources all travel with the installed app.

Gemma 4 needs its own template and control tokens. [Google's model card](https://huggingface.co/google/gemma-4-E2B-it) describes enabling thinking through the `<|think|>` system token. Keep the initial app in standard text mode using the local template; do not transplant Qwen-specific `/no_think` formatting. The exact Swift package version and runtime validation belong to the app build record.

## License and attribution

Google DeepMind created Gemma 4; MLX Community published this MLX conversion. The [Google card at the source revision used for conversion](https://huggingface.co/google/gemma-4-E2B-it/blob/70af34e20bd4b7a91f0de6b22675850c43922a03/README.md) declares Apache-2.0. Neither the upstream snapshot nor this conversion contains a standalone license file, so the bundle includes the verbatim [Apache 2.0 license](https://www.apache.org/licenses/LICENSE-2.0.txt), pinned by SHA-256.

The conversion card's front matter says `license: gemma`, which conflicts with the original Google source card. Both cards are retained unchanged as `README.md` and `UPSTREAM-MODEL-CARD.md`, and the discrepancy is recorded in the lock. Use the original Google's Apache declaration as the upstream model-license evidence; confirm the community metadata before a distribution release. This local prototype is not a publication or a claim of endorsement.

## Validation status

On 2026-09-05, provisioning completed and installed all 11 files (3,583,125,193 bytes). Full SHA-256 verification passed for every file; all 2,511 tensors had valid data boundaries and exact shard-index coverage. A second standalone verification passed. Repeat provisioning passed with the network entry point replaced by a function that raises on any network call, confirming that the valid bundle is reused without a download. Both scripts passed Python compilation. Seven temporary structural-fixture checks passed: complete bundle acceptance and rejection of traversal, unexpected partials, checksum corruption, missing tokenizer, symlinks, and absent indexed tensors. A further fresh-install structural fixture verified that staging and locking occur under `.build/model-provision` and only the completed bundle enters `Resources/Models`; the existing full-model checksums and offline repeat also passed after that change. These fixtures contained one scalar tensor and no generated-answer examples.

The copied assets inside the built iPhone app also passed full verification. Real Mac generation ran with networking denied, and a signed build subsequently generated a real cited answer on the physical iPhone 15 Pro; see [VALIDATION.md](VALIDATION.md) for observations and quality gaps. The independent phone test with networking disabled and Mac off remains pending. Do not infer memory requirements from “E2B,” download size, or simulator results. Record actual load/response/memory/failure behavior, and later battery and heat.
