# Persistent milestone checklist

Update this file as evidence arrives; do not mark physical-device gates from a Mac or simulator run.

## 1. First independent offline prototype

- [x] Establish isolated project and inspect tools/storage.
- [x] Confirm audience/region and record Gemma 4 E2B preference.
- [x] Build original, locally readable seed library with source/date/rights metadata.
- [x] Implement deterministic retrieval and source-identity checks.
- [x] Wire SwiftUI question, library, loading/unavailable/failure states.
- [x] Download and verify complete pinned assets, including the copy inside the iPhone app.
- [x] Build pinned Swift local-only model integration for iPhone (unsigned Release).
- [x] Pass core tests (8) and simulator UI checks (4).
- [x] Run real Mac inference with networking denied and review ten scenarios; preserve quality gaps in VALIDATION.md.
- [x] Connect physical iPhone by USB; developer disk image services ready; signed Release build verifies.
- [x] Install signed build on physical iPhone 15 Pro, iOS 26.6.1.
- [x] Generate a real, cited answer on the connected physical iPhone; record load/response/allocator measurements.
- [ ] Cold launch and answer with Wi-Fi/cellular off and Mac off.
- [ ] Record device memory, load/first-output/total-answer delay, and failures.

Installation completed on 2026-09-05. The development check inside Camping Buddy passed on a physical iPhone without a separate test runner. Version 0.2 also passed the single-Ask flow from a fresh app session. Mac-off/radios-off acceptance remains pending.

## 2. Evidence and data

- [ ] Expand trusted, licensed corpus; retain provenance and regional applicability.
- [ ] Obtain appropriate expert review and identify gaps before field use.
- [ ] Freeze held-out camping scenarios, including uncertainty and insufficient evidence.
- [ ] Compare baseline, baseline with retrieval, and fine-tune with retrieval on the same held-out cases; judge factual support separately from formatting.

## 3. Mac adaptation and custom-weight deployment

- [ ] Verify installed Studio's Gemma E2B architecture/version support in an isolated test; do not assume prior Qwen support transfers.
- [ ] Prepare separately licensed training examples, with no evaluation leakage.
- [ ] Run a small SFT adapter experiment in Studio with measured memory and interactivity; preserve checkpoints, recipe, and base identity.
- [ ] Export fused MLX weights and prove the exact custom checkpoint loads in the iPhone runtime. Do not assume Python adapter sidecars match Swift adapter targets.
- [ ] Evaluate quantization and regression against the original baseline; retain an unchanged control.
- [ ] If choosing Google mobile QAT/LiteRT, verify the exact custom-weight conversion/export separately rather than treating standard MLX 4-bit as equivalent.

## 4. Field validation and release

- [ ] Battery/heat/latency trials, longer offline use, memory pressure, cold launches, and interruption/cancellation tests on target phones.
- [ ] Field trials without connectivity; assess harmful overconfidence and unanswered questions.
- [ ] Private beta with feedback and a clear supported-device list.
- [ ] Content/model licenses, privacy, accessibility, packaging size, signed distribution and App Store review preparation.
- [ ] Release the app only after offline and quality gates pass. Publishing the source repository does not complete these gates.
