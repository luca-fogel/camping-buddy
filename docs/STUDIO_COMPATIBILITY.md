# Installed Studio compatibility — inspected 2026-09-05

> **Audited against a model the app no longer ships.** This is a Gemma 4 E2B audit, written when Gemma was the shipped model. The app moved to a single Bonsai 27B (MLX 1-bit, `qwen3_5`) model on 2026-09-09, so the architecture-specific findings below — the `gemma4.py` and `gemma4_text.py` observations, the Gemma template and EOS notes, the export dataclass concern — do **not** transfer. The generic findings about Studio's export helper and the GGUF restriction still apply. Milestone 3 needs a fresh audit against `qwen3_5` and 1-bit weights before any adapter work; a 1-bit base is a materially harder LoRA target than a 4-bit one, and that has not been assessed.

Gemma 4 E2B has text-model and generic LoRA support in an existing Mac Python environment. **A Gemma 4 training, adapter reload, or fused-export round trip in MLX LoRA Studio has not been tested.** This audit read source files and package metadata only; it did not import MLX, load weights, train, change settings, or modify an installed environment.

## What is installed

| Component | Verified finding |
| --- | --- |
| Studio app | `/Applications/MLX LoRA Studio.app`, version `beta-102.57.7` from `Contents/Info.plist`. |
| Bundled training code | `Contents/Resources/StudioSupport/vendor/mlx-lm-lora`, version `2.1.0` from `mlx_lm_lora/_version.py`. |
| Runtime arrangement | The bundle contains training source; no Python interpreter/site-packages were found in its Resources. Its executable contains Python discovery, selection, virtual-environment creation, and `PYTHONPATH` handling. Do not describe it as a self-contained Python runtime. |
| Inspected candidate Python | Python 3.13 virtual environment: `mlx 0.32.1`, `mlx-metal 0.32.1`, `mlx-lm 0.31.3`, `transformers 5.15.1`, from installed distribution metadata. Your environment path can differ. |
| Candidate completeness | `mlx-lm-lora` is not installed as a distribution in that environment; Studio has its vendored copy. The candidate also lacks declared vendor requirements `datasets`, `pymupdf`, and `openai`. Dependency readiness and backend imports remain to be checked in an isolated training environment. |
| Secondary inspected Python | Homebrew Python 3.14 had `mlx 0.31.1`; `mlx-lm`, `mlx-lm-lora`, and `transformers` were absent. This illustrates why the selected interpreter must be checked. |
| Studio's selected Python | Unverified during the audit. A discoverable environment is not proof Studio currently uses it. Select the intended interpreter and verify backend imports before a training experiment. |

## Code evidence and limits

Paths below beginning with `site-packages/` are relative to the inspected Python environment's `lib/python3.13/` directory. Substitute your own environment path. Paths beginning with `StudioSupport/` are under the installed app's `Contents/Resources/`.

- `site-packages/mlx_lm/utils.py:185` resolves the model architecture by importing the `model_type` module. `models/gemma4.py:15` accepts the nested `text_config`; `:55` removes vision/audio tensors; `:84` exposes the language-model layers. `models/gemma4_text.py:183` creates K/V projections only for layers owning them. This is current E2B-relevant code, separate from older E4B observations.
- `site-packages/mlx_lm/tuner/utils.py:38` adapts model layers, including ordinary and quantized linear modules. `tuner/lora.py:34` implements fusion. This supports a small E2B text LoRA experiment in principle; gradient correctness and useful training behavior are untested here.
- `StudioSupport/Backend/training_runner.py:640` calls the vendor loader. The vendor `mlx_lm_lora/utils.py:169` delegates to `mlx_lm.utils.load` and then applies generic LoRA/DoRA conversion. `Backend/training_runner.py:400` forwards batch size, sequence limit, checkpointing, accumulation, evaluation, and save intervals.
- Studio's text export at `Backend/training_runner.py:710` calls `save_pretrained_merged`; the vendor `utils.py:42` writes safetensors, `vars(model.args)`, and tokenizer files. **Export compatibility needs explicit verification:** Gemma's outer argument object includes only `model_type`, `text_config`, and `vocab_size`; its top-level quantization and generation metadata are not retained by that dataclass. A quantized fused export can therefore lose metadata needed for reload. No failure was reproduced in this audit. The default dequantized export is a different, larger artifact and is not the phone benchmark model.
- `generation_config.json` is not explicitly copied by that export helper. Confirm that the Gemma chat template and correct EOS IDs survive export; never infer complete assets from a successful save message. The camping app requires these files locally.
- The bundled GGUF helper explicitly allows only Llama/Mixtral/Mistral (`utils.py:103`). It is not a Gemma conversion route. Use MLX safetensors for the current native prototype.

## Next bounded training/export check — not executed

Do this after the native baseline is working. Use a separate project-local training environment so the experiment does not alter another environment or project.

1. Create a dedicated training environment under this project, reproduce the candidate package versions, and satisfy the vendored trainer requirements. Select its Python in Studio and verify backend imports. Record the interpreter, resolved package versions, and vendor version before any training.
2. Point Studio at the exact provisioned Gemma 4 E2B IT checkpoint. Keep the original snapshot immutable. Choose **text SFT + LoRA**. With a prequantized 4-bit base, leave the additional “load in 4 bits” conversion off. Disable remote datasets, experiment tracking, and uploads.
3. Make a separate compatibility dataset: four original short preparation conversations for training and two separate validation conversations. Do not reuse `evaluation/scenarios.json`. Inspect rendered token sequences: exactly one beginning token, correct Gemma turn markers, no thinking activation, and correct assistant-target masking. The vendor's conversational dataset path renders a template and then encodes it, so inspect rather than assume special-token parity.
4. Use a deliberately tiny wiring check: **2 iterations, batch 1, accumulation 1, maximum sequence 128, last 1 layer, rank 2, dropout 0, learning rate 0.00001, report/save every iteration, validation 1 batch**. Leave QAT, DoRA, and automatic fusion off. Confirm the trainable parameter list, finite loss/gradients, and saved nonempty adapters. These are diagnostic settings, not a recommended training recipe or quality experiment.
5. Reload the original base plus the saved adapter in a fresh process; generate one short prepared prompt with thinking disabled and record output, peak memory, and elapsed time. Preserve the adapter checkpoint and exact run specification.
6. Export to a fresh run-specific folder. Keep “remove adapters” off. First verify a dequantized merged MLX export can reload; then separately make and test the intended phone quantization. Preserve the original full configuration and generation configuration; validate quantization metadata against actual tensors rather than blindly copying it onto dequantized weights. Keep tokenizer/template, license, and provenance together.
7. Test the resulting folder through **this app's pinned Swift text loader**. Compare the base+adapter, merged, and mobile-quantized versions on untouched scenarios for supported claims, missing-evidence behavior, citation IDs, and practical correctness. Saving or loading successfully is not evidence of improved answers. Only then plan a larger camping adaptation and physical-phone measurements.

The Studio-specific environment selection/import checks and the tiny experiment remain open. The native baseline can proceed independently using the already pinned Swift runtime.
