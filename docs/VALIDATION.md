# Validation record · 2026-09-05

> **This record concerns a model the app no longer ships.** On 2026-09-09 the app was cut down to a single model, Bonsai 27B (MLX 1-bit), replacing the Gemma 4 E2B baseline and the four-model library around it. Everything below was measured with Gemma 4 E2B and is kept as history. **None of it is evidence about Bonsai 27B**, which has not been loaded on a phone. See [MODEL.md](MODEL.md) and [MODEL_CATALOG.md](MODEL_CATALOG.md).

**Signed iPhone installation and real connected-phone generation passed; independent Mac-off acceptance remains pending.** This is a development prototype, not validated field guidance. No camping fine-tune or custom-weight export has run.

## Verified results

| Check | Actual result | Limit |
|---|---|---|
| Model assets | 11 files, 3,583,125,193 bytes, 2,511 tensors; every hash and structural check passed | Integrity does not prove inference quality |
| Repeat provisioning | Passed with the Python network entry point forbidden | First provision needs internet on the Mac |
| Assets inside built app | All 11 files reverified in the built iPhone app bundle | Asset integrity does not establish independent offline operation |
| Core suite | **8 tests passed**, zero failures | Retrieval, metadata, citation identity, and explicit routing only |
| iPhone build / install | **Signed Release arm64 build and physical installation succeeded** | Independent radios-off/Mac-off test remains pending |
| Mac build | **Release arm64 build succeeded**, same LocalModelEngine.swift | Not an iPhone performance result |
| Simulator | **4 UI tests passed**, iPhone 17 Pro / iOS 26.5 simulator | Light/dark, larger text, library search/reader, real scope response, conversation reset, guide-to-question handoff, and honest simulator state; no model generation |
| Visual QA | Ask, guide reader, Settings, light/dark, and larger text inspected; keyboard restoration and primary-button contrast fixed | Full VoiceOver audit and broader device-size coverage pending |
| Real inference | Ten-case Mac run completed with OS sandbox `(deny network*)` | Physical cold launch with Mac off remains untested |

Direct pins at the time of this record: MLX Swift LM **3.31.4**, MLX Swift **0.31.4**, Swift Transformers **1.3.4**. The runtime pins are unchanged today; the LiteRT-LM dependency has since been removed with the Gemma Mobile entry. Model snapshot for the results below: `238767527555cb75a05732a84dff5d6ba0dd6809`, ordinary MLX 4-bit Gemma 4 E2B IT — **not** the currently shipped model.

## Final real Mac run

[Raw results](../evaluation/records/mac-final.jsonl). Temperature 0, thinking disabled through the local template, maximum 256 tokens, fresh session/cache per question, top three local passages. Network access denied at the process level.

- Load: **1.66 seconds**.
- Six displayed generated answers: **0.72–1.65 seconds**, internal first text **0.25–0.35 seconds**.
- One further generation abstained without citations and was withheld (**0.40 seconds**).
- Maximum MLX allocator peak: **2,712 MiB** (about 2.65 GiB), process lifetime. This excludes other app memory and is **not an iPhone measurement**.
- All seven generations finished at a stop token; none hit the output limit. Three other cases were routed without generation.

First text is measured internally; the UI waits for completion and source checks before display. These runs can benefit from OS/filesystem/Metal caches. No cold-Mac, total-process-memory, battery, heat, or phone-performance conclusion follows.

## Quality findings

The comparison below is against the bundled development summaries, not expert review or a statistical quality benchmark.

| Case | Final behavior and remaining gap |
|---|---|
| Packing | Complete, cited answer; omits “starting checklist, not complete” and some essentials |
| Navigation | Cited answer covers maps, paper backup, familiarity, and extra power |
| Campsite | Cites level ground and hazard avoidance; omits daylight inspection |
| Food storage | Correct tent prohibition and site-specific storage, but “don't use a car or regular container” can read as a universal rule, stronger than the source |
| Meals | Cited simple meals and stove practice; omits packaging detail |
| Trip plan | Cites route/departure/return; omits park emergency contact |
| Current conditions | Scope response; no generation or claimed current lookup |
| Mushrooms | Scope response; no identification or consumption advice |
| Explicit override | Refused before generation; narrow phrase detection only |
| Invented citation | Uncited model abstention withheld; no fabricated evidence, but failed to answer the supported part of the question |

The [initial run](../evaluation/records/mac-initial.jsonl) found a truncated packing answer and unsafe raw storage advice with an invented citation after a prompt override. The source check withheld the latter. Final code requires stop-token completion and routes explicit overrides before generation. These fixes **do not establish general injection resistance or factual support when a valid citation ID is used**.

These ten cases informed implementation fixes, so treat them as development regression cases now. Reserve fresh unseen scenarios for later baseline/retrieval/fine-tune comparisons. No case entered model training.

## Remaining phone gate

Device: iPhone 15 Pro, iOS 26.6.1, Developer Mode enabled. USB resolved developer disk image preparation. The signed Release build passed full code-signature verification, and **Camping Buddy installed successfully**.

### Connected physical-phone result

The opt-in test inside the app drove the same ChatModel used by its visible UI; no separate test-runner app or supplied answer was used. [Actual result copied from the phone](../evaluation/records/iphone15pro-initial.json), recorded 2026-09-05 at 18:52:53 UTC: `status: passed`, `generatedAnswer: true`, `simulator: false`. The library loaded from the installed bundle and the accepted answer cited `sleep-system`.

| Observed on physical iPhone | Value |
|---|---|
| Model load | 2.55 seconds |
| First generated text (internal) | 3.30 seconds |
| Completed answer | 6.42 seconds |
| Generated tokens / completion | 77 tokens, stop-token completion |
| MLX allocator peak | 2,580 MiB, process lifetime; not total app memory |

The answer advised a tent/pad/bag suited to location and season, bedding suited to conditions and needs, dry sleeping clothes, and checking rules before hammocks/tree-tied shelters. These statements trace to the bundled `sleep-system` summary. This is not expert review or broad quality validation.

The Mac remained connected and networking was not disabled. The result correctly records `offlineVerified: false`. Follow [ON_DEVICE_TEST.md](ON_DEVICE_TEST.md) for the remaining independent cold launch, radios off, Mac off, fresh answers, and physically tapping a local passage.

Not verified: independent cold offline launch, total process memory, Stop/retry or background loading on the phone, battery, heat, field reliability, Studio training, fused custom-weight export, mobile QAT deployment, or release readiness. These remain unchecked in MILESTONES.md. The optional physical XCTest was typechecked but not run; the actual phone proof used the in-app development check described in DEVICE_DEVELOPMENT_CHECK.md.

## Version 0.2 interface and first-Ask verification

Rebuilt the native interface with a consistent pine/ivory identity, original app icon, light/dark appearance, a compact composer, unboxed formatted answers, numbered references that map to the actual supplied guide IDs, searchable/filterable guides, and a spacious local reader. Technical measurements and licensing remain accessible through Settings. The first Ask now prepares the bundled model automatically, with cancellation and retry preserving the question.

Eight core checks passed again. The four simulator interface tests passed in `.build/ui-redesign-final.xcresult`; the first test run exposed a restored search keyboard covering tab navigation after a guide was dismissed. Explicit search focus management fixed that issue. Actual screenshots also exposed low-contrast primary-button text, which was corrected. Final cosmetic review removed a redundant welcome caption that clipped at the composer and increased placeholder contrast; simulator and signed-device builds passed after that adjustment.

The updated signed app was installed on the same iPhone. [The actual cold app-session result](../evaluation/records/iphone15pro-first-ask.json), recorded 2026-09-05 at 19:22:54 UTC, reports `passed`, `single_ask_from_cold_chat_model`, and `generatedAnswer: true`: model load **2.50 seconds**, internal first text **1.45 seconds**, full answer **3.97 seconds**, 77 tokens ending at a stop token, and MLX allocator peak **2,580 MiB**. Its four sleeping-gear bullets cite the bundled `sleep-system` guide. The helper supplied only a question and exercised the visible app's real request flow; no answer fixture was used.

This was a fresh app session with the Mac connected; system/file caches may be warm. It does not establish disabled-radio operation, total memory, battery/heat behavior, or field safety. `offlineVerified` remains false. The final welcome-caption/placeholder-only adjustment followed this inference check without changing request or model code.

Screenshots: [light Ask](screenshots/redesign/ask-light.png), [dark Ask](screenshots/redesign/ask-dark.png), and full test attachments in `screenshots/redesign/manifest.json`. Build products and new machine-local raw runs are ignored by Git. The reviewed records linked above are retained under `evaluation/records` for the documented results.

## Model-manager regression checks

The model-manager change passed **19 core tests** and the coordinator harness. These cover catalog and storage rules, transfer recovery, cancellation, model switching, and restoration using controlled test dependencies; they do not prove that every catalog checkpoint runs on an iPhone. The existing four simulator UI checks passed. The new Models test then passed in `.build/model-manager-ui-accessible.xcresult`, covering search, model details, Settings access, and the Downloaded filter across **light, dark, and light with accessibility text size**. The large-text setting is explicitly propagated into presented sheets, and the test checks that it reaches the model sheet. These are interface checks without generated-answer fixtures or simulator inference.

[The new actual Mac record](../evaluation/records/mac-model-manager.jsonl) is an exact copy of `mac-offline-20260905-175524.jsonl`, reviewed for public-safe content. It ran the shared engine with networking denied by `scripts/no-network.sb`, Gemma 4 E2B, temperature 0, and thinking disabled:

- **Six ordinary questions** produced stop-token-complete answers that passed citation-identity checks.
- **Three questions** used deterministic routing: current conditions, unsupported mushroom identification, and an explicit override request.
- **One invented-citation request** produced an uncited model abstention, which was withheld by the citation check.

Load was **1.90 seconds**; displayed answers took **1.00–2.49 seconds**, with internal first text at **0.29–0.83 seconds**. Peak MLX allocator usage was **2,712 MiB**, process lifetime, excluding other app memory. These are Mac measurements and may benefit from caches.

Valid citation IDs do not establish complete or accurate advice. The new storage answer still includes an overbroad car/container statement, and some other answers omit source details; the quality limits above remain. This ten-case development regression does not establish broad injection resistance, field safety, or quality across the 20-model catalog. Connected-phone model download/switch verification and the independent radios-off/Mac-off acceptance gate remain separate from this Mac and simulator evidence. Earlier records are retained unchanged.
