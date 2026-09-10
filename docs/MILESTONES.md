# Persistent milestone checklist

Update this file as evidence arrives; do not mark physical-device gates from a Mac or simulator run.

**2026-09-09/10: the shipped model changed twice.** The app was cut to a single model, first Bonsai 27B (MLX 1-bit) and then — after that checkpoint proved unloadable on stock MLX, which has no sub-2-bit affine quantization — Ternary Bonsai 8B (MLX 2-bit). Device gates earned by Gemma 4 E2B do not carry over and have been un-ticked below; the Gemma results and the 1-bit failure stay in [VALIDATION.md](VALIDATION.md) as history.

## 1. First independent offline prototype

- [x] Establish isolated project and inspect tools/storage.
- [x] Confirm audience/region and record a model preference (Gemma 4 E2B originally; Ternary Bonsai 8B since 2026-09-10).
- [x] Build original, locally readable seed library with source/date/rights metadata.
- [x] Implement deterministic retrieval and source-identity checks.
- [x] Wire SwiftUI question, library, loading/unavailable/failure states.
- [x] Download and verify complete pinned assets, including the copy inside the iPhone app.
- [x] Build pinned Swift local-only model integration for iPhone (unsigned Release).
- [x] Pass core tests (8) and simulator UI checks (4).
- [x] Run real Mac inference with networking denied and review ten scenarios; preserve quality gaps in VALIDATION.md. *(Gemma 4 E2B)*
- [x] Connect physical iPhone by USB; developer disk image services ready; signed Release build verifies.
- [x] Install signed build on physical iPhone 15 Pro, iOS 26.6.1.
- [x] Run real Mac inference with the current model, networking denied, over ten scenarios. *(Ternary Bonsai 8B, 2026-09-10: six cited answers, three correctly routed, one fabricated source withheld.)*
- [ ] Load Ternary Bonsai 8B on the physical iPhone; a jetsam kill is a possible outcome and counts as a recorded result.
- [ ] Generate a real, cited answer on the connected physical iPhone; record load/response/allocator measurements.
- [ ] Cold launch and answer with Wi-Fi/cellular off and Mac off.
- [ ] Record device memory, load/first-output/total-answer delay, and failures.

Installation completed on 2026-09-05 and a real cited answer was generated on the phone — **with Gemma 4 E2B**, which the app no longer ships. Ternary Bonsai 8B generates on a Mac but has never run on a phone, so the device generation gate is open. Mac-off/radios-off acceptance remains pending behind it.

## 2. Evidence and data

- [ ] Expand trusted, licensed corpus; retain provenance and regional applicability.
- [ ] Obtain appropriate expert review and identify gaps before field use.
- [ ] Freeze held-out camping scenarios, including uncertainty and insufficient evidence.
- [ ] Compare baseline, baseline with retrieval, and fine-tune with retrieval on the same held-out cases; judge factual support separately from formatting.

## 3. Mac adaptation and custom-weight deployment

- [ ] Verify installed Studio's `qwen3` architecture/version support, and whether a 2-bit ternary base is a viable LoRA target at all, in an isolated test; the earlier Gemma E2B audit does not transfer.
- [ ] Prepare separately licensed training examples, with no evaluation leakage.
- [ ] Run a small SFT adapter experiment in Studio with measured memory and interactivity; preserve checkpoints, recipe, and base identity.
- [ ] Export fused MLX weights and prove the exact custom checkpoint loads in the iPhone runtime. Do not assume Python adapter sidecars match Swift adapter targets.
- [ ] Evaluate quantization and regression against the original baseline; retain an unchanged control.
- [ ] Verify any custom-weight export back into Prism ML's 2-bit ternary packing separately; do not assume a standard MLX quantized export reloads in the same runtime path.

## 4. Field validation and release

- [ ] Battery/heat/latency trials, longer offline use, memory pressure, cold launches, and interruption/cancellation tests on target phones.
- [ ] Field trials without connectivity; assess harmful overconfidence and unanswered questions.
- [ ] Private beta with feedback and a clear supported-device list.
- [ ] Content/model licenses, privacy, accessibility, packaging size, signed distribution and App Store review preparation.
- [ ] Release the app only after offline and quality gates pass. Publishing the source repository does not complete these gates.
