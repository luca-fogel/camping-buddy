# Camping Buddy

[![CI](https://github.com/foggylulu/camping-buddy/actions/workflows/ci.yml/badge.svg)](https://github.com/foggylulu/camping-buddy/actions/workflows/ci.yml)

A little more ready. A little more outside.

A native **iPhone app in Swift and SwiftUI** for planning your first camping weekends. Ask about gear, food storage, or preparing a campsite. Read the saved guides behind an answer. **Answers run on your iPhone**, on one model: [Bonsai 27B](https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit), Prism ML's 1-bit MLX conversion of Qwen3.6-27B. No picker, no fallback, no cloud. No account or API key is used. Downloading the model needs internet; asking questions afterwards does not.

![Camping Buddy — on-device AI and saved camping guides](docs/images/hero.svg)

> **Status: not yet run on a phone.** Version 0.4 replaces the five-model library with a single model, Bonsai 27B. Earlier builds were tested on an iPhone 15 Pro with a *different* model (Gemma 4 E2B); those records are kept as history and are not evidence about Bonsai. Bonsai 27B is 4.78 GiB of weights, and whether an 8 GB iPhone can load it at all is the open question — see [memory](docs/MODEL_CATALOG.md#memory-which-is-the-open-risk). It is not on the App Store. The saved library is a small development collection, not expert-reviewed field guidance. An independent test with the Mac off and the phone's radios disabled is still pending.

## What it does

- **Ask before you pack.** Suggested questions cover sleeping gear, food storage around wildlife, and first-trip planning. The first Ask prepares the local model automatically.
- **Read the reference.** Answers link to the saved guides they cite. A reference opens the actual bundled summary, including its National Park Service source and review status.
- **Keep a small field library.** Eight short guides cover planning, essential gear, navigation preparation, shelter, campsite setup, food storage, and simple meals. Search or filter them without loading the model.
- **Save the model once.** Open the model pill or Settings → Manage the model. See the download and storage size, pause and resume the transfer, and remove the download to reclaim the space. [Catalog and compatibility details](docs/MODEL_CATALOG.md).
- **Make it comfortable to read.** Light, dark, and system appearance; larger text; selectable answers; a compact composer; and a fresh-conversation action.

Each question starts a fresh model session. The visible conversation stays in memory, holds up to 12 entries, and clears when the app process ends. There is no saved chat history or cloud sync.

## The screens

| Ask | Field guide | Model |
|:--:|:--:|:--:|
| ![Camping Buddy in light mode](docs/images/ask-light.png) | ![The saved shelter and bedding guide](docs/images/guide.png) | ![The model screen with its download size and storage](docs/images/models-light.png) |
| A calm starting point and suggested questions | The complete saved summary, with its source | The model download, its size, and storage |

<details>
<summary>See the dark appearance</summary>

<p align="center"><img src="docs/images/ask-dark.png" width="300" alt="Camping Buddy in dark mode"> <img src="docs/images/models-dark.png" width="300" alt="The model screen in dark mode"></p>

</details>

These are actual iPhone simulator captures of the SwiftUI app. They are not generated answer demonstrations. The model download and real inference are checked separately on a physical phone; simulator screenshots demonstrate the interface only. The header is original vector artwork. The interface takes inspiration from Locally AI by LM Studio, with its own camping identity.

## Try the interface

```sh
git clone https://github.com/foggylulu/camping-buddy.git
cd camping-buddy
open CampingBuddy.xcodeproj
```

Let Xcode resolve the pinned packages, select an iPhone simulator, and run. The library and interface can be explored without downloading the model. The simulator explains that generation requires a physical Apple device; it does not substitute a canned AI answer.

The project was built with **Xcode 26.6 / Swift 6.3.3**. If Xcode reports a missing Metal compiler, install its toolchain component:

```sh
xcodebuild -downloadComponent MetalToolchain
```

## Run the model on an iPhone

In Xcode, choose your development team under Signing & Capabilities, select your connected iPhone, and run. No model weights are bundled in the app.

Open **Manage the model** to download Bonsai 27B while online. It is a **4.81 GiB** transfer, pinned to an immutable revision and verified against file hashes before it can be used. Keep the app open until it finishes. You can remove the download afterwards to reclaim the space; the app then reports that no model is installed until you download it again.

The app declares `com.apple.developer.kernel.increased-memory-limit`, because 4.78 GiB of weights must be resident to generate and an 8 GB iPhone otherwise kills the app during the load. The entitlement raises that ceiling; it does not remove it. Prism ML reports a ~3.9 GB deployed footprint and ~11 tok/s on a 12 GB **iPhone 17 Pro Max**. This project's phone is an 8 GB **iPhone 15 Pro**, and the load has not been attempted there. The project has an iOS 17 compilation floor; that does not establish that any given iOS 17 device has enough memory. See the [device test guide](docs/ON_DEVICE_TEST.md) for the remaining independent offline check.

## How an answer reaches the screen

```text
Your question
     │
     ├── Outside the supported scope? → Explain the limit
     │
     ▼
Search the eight saved guides
     │
     ├── No relevant passage? → Say there is not enough evidence
     │
     ▼
Bonsai 27B on this iPhone · fresh session
     │
     ▼
Require a completed answer and check its reference IDs
     │
     ├── Truncated, missing, or unknown references? → Withhold the answer
     │
     ▼
Display the answer with buttons to its saved guides
```

The library search is small and deterministic: titles, keywords, and passage text. It does not query a website or an external vector database. MLX receives local model files only. There is no cloud inference and, with one model, nothing to fall back to.

**Bonsai 27B is the official Prism ML checkpoint in MLX 1-bit packing**, converted from Qwen3.6-27B. No app-side model code was written for it: MLX Swift LM 3.31.4 already implements `qwen3_5` with the hybrid linear-attention layers this checkpoint uses. The repository also carries a 4-bit vision tower, which this app neither downloads nor uses. [Catalog and source details](docs/MODEL_CATALOG.md).

## What has actually been measured

**Nothing has been measured for Bonsai 27B.** It has not been loaded on a phone.

The table below is a **historical Gemma 4 E2B measurement** from the model this app used to ship. It is kept because it describes the same request flow, not because it predicts anything about a 27B model twelve times its size. On **September 5, 2026**, a single Ask from a fresh app session on the physical iPhone prepared that model and generated an accepted sleeping-gear answer.

| Physical iPhone 15 Pro | Observed |
|---|---:|
| Model preparation | 2.50 seconds |
| First generated text, internal | 1.45 seconds |
| Completed answer, after preparation | 3.97 seconds |
| Output | 77 tokens, stop-token completion |
| MLX allocator peak | 2,580 MiB |

The [actual phone record](evaluation/records/iphone15pro-first-ask.json) includes the answer and the saved passage it cited. Memory is the MLX allocator's process-lifetime peak, **not total app memory**. This was a fresh app process with the Mac connected; caches may be warm, and networking was not disabled. The record therefore leaves `offlineVerified` false.

Separate [Mac evaluation records](evaluation/records/mac-final.jsonl) were collected with networking denied to the process. They helped expose truncation, citation, and advice-quality issues. Those results are not phone performance measurements. The [validation notes](docs/VALIDATION.md) include the unsuccessful cases as well as the successful ones.

## The part worth checking

**A valid reference ID does not prove that advice is supported by its source.**

The app checks whether a reference exists and was supplied to the model. That catches an invented label; it cannot establish that every sentence accurately interprets the passage. During development, one food-storage answer used a real source but made its wording stronger than the saved guidance. Another raw answer invented a source after a prompt override and was withheld.

Those findings are retained in the [initial evaluation record](evaluation/records/mac-initial.jsonl). MLX generation also requires normal stop-token completion and rejects a small set of explicit override phrases before generation. This is not a claim of general prompt-injection resistance or expert-level camping advice.

The app does not provide current weather, closures, permits, fire permissions, medical diagnosis, or edible-plant identification. Its eight guides are original summaries based on National Park Service material, with attribution kept in the app. See [content provenance](docs/CONTENT.md).

## Tests

The core checks need no model, API key, or network:

```sh
swift test --scratch-path .build/core
python3 scripts/check_public_repo.py
```

**Core tests** cover local content, retrieval, scope routing, citations, catalog validation, download integrity, and model storage. Model-management checks include interrupted transfers, corruption, storage limits, trusted paths, and persistence. [CI](.github/workflows/ci.yml) runs the same core suite and public repository checks.

**Five simulator interface tests** cover light/dark appearance, larger text, searching and reading a guide, the model screen and its details, simulator availability, the real scope response, clearing a conversation, and asking about a guide:

```sh
xcodebuild -project CampingBuddy.xcodeproj -scheme CampingBuddy \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/simulator CODE_SIGNING_ALLOWED=NO \
  -only-testing:CampingBuddyUITests/CampingBuddyUITests test
```

The deterministic [model-loading check](DeveloperChecks/ChatModelFlowCheck.swift) compiles the actual chat coordinator against controlled dependencies. It covers cancellation, failed loads, failed selection commits, restoring the previous model, and persisted selection. Run `zsh scripts/check_chat_model_flow.sh`; these controlled responses are not inference evidence.

The [connected-device check](docs/DEVICE_DEVELOPMENT_CHECK.md) documents the opt-in in-app test that produced the earlier phone record. It has not been run against Bonsai 27B. Physical inference is not run by CI. Battery, heat, total memory, wider device support, and field reliability still need testing.

## Project map

```text
App/                         SwiftUI screens, chat state, the MLX engine
Core/                        Retrieval, answer policy, model catalog and storage
Tests/                       Fast core and retrieval checks
UITests/                     Interface checks and optional phone test
Resources/ReferenceLibrary/  Eight original, attributed preparation guides
Resources/ModelCatalog/      The pinned download manifest: sizes, hashes, and provenance
Resources/Acknowledgments/  Third-party notices
Resources/Entitlements/      The increased memory limit the 27B weights require
Resources/Models/            Mac evaluation weights; ignored by Git
scripts/                     Provisioning, verification, and repository checks
evaluation/records/          Actual development runs, including failed cases
docs/                        Model, content, validation, and device notes
```

`project.yml` is the XcodeGen source; the generated Xcode project and all resolved package revisions are committed. Run `xcodegen generate` if you change the project definition. No camping fine-tune or custom-weight export has been performed.

## Related work

[**solvr.ai**](https://github.com/foggylulu/solvr-ai) — the on-device maths tutor that inspired this repository's presentation.

## Licenses and acknowledgments

The app's original source does not yet have a redistribution license. Publishing this repository does not change the licenses of its dependencies or model. Their notices are retained in [Resources/Acknowledgments](Resources/Acknowledgments/ThirdPartyNotices.txt); model provenance and the upstream Apache 2.0 declaration are documented in [docs/MODEL.md](docs/MODEL.md). Model weights are downloaded separately and are not hosted in this repository.
