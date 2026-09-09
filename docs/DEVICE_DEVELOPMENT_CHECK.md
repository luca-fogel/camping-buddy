# Connected iPhone development check

This check drives the actual visible app, model loader, retrieval, generation and citation validation. It installs no separate test runner, which matters when using Apple's three-app limit for free development profiles. It is separate from the Mac-off acceptance test in ON_DEVICE_TEST.md.

Version 0.2 uses Ask, Library, and Settings. In normal use, the first Ask automatically prepares the model before answering; Settings → Prepare assistant remains optional. The redesigned interface passed four simulator tests. The updated in-app check also passed on an iPhone 15 Pro / iOS 26.6.1: one Ask from a fresh ChatModel prepared the model and produced a real cited answer. The [actual run record](../evaluation/records/iphone15pro-first-ask.json) is dated 2026-09-05 at 19:22:54 UTC. Model load was 2.50 seconds; completed answer was 3.97 seconds. This is a cold app session, not a cold operating system or disabled-radio check. See [VALIDATION.md](VALIDATION.md) for the measured results and limitations.

## Signed build and install

Replace `YOUR_TEAM_ID` and `YOUR_DEVICE_ID` below with your own development team and device identifiers. Select a bundle identifier available to your team in Xcode or `project.yml`; the checked-in prototype identifier is `com.luca.campingbuddy.prototype`. If you change it, use your chosen identifier consistently in the launch and copy commands. A free development profile may have an installed-app limit; the in-app check avoids adding a separate test runner.

```sh
xcodebuild -project CampingBuddy.xcodeproj -scheme CampingBuddy -configuration Release -destination 'generic/platform=iOS' -derivedDataPath .build/iphone -clonedSourcePackagesDirPath .build/packages -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -allowProvisioningUpdates DEVELOPMENT_TEAM=YOUR_TEAM_ID CODE_SIGN_STYLE=Automatic build
xcrun devicectl device install app --device YOUR_DEVICE_ID .build/iphone/Build/Products/Release-iphoneos/CampingBuddy.app
xcrun devicectl device process launch --device YOUR_DEVICE_ID --terminate-existing com.luca.campingbuddy.prototype --camping-smoke-test
```

The last command is explicitly opt-in. Normal Home Screen launches do not automatically start the test or load the model; preparation occurs with the first Ask or the optional Settings action. The test starts from a fresh, unloaded ChatModel, asks “What sleeping gear should I pack?” with one Ask action, and requires an accepted generated answer with local source references. The complete preparation-and-answer flow has a 120-second timeout and cancellation handling. No model answer is supplied by the test.

The app saves `Documents/DeviceSmokeTest.json` and emits the same report with a `CAMPING_DEVICE_SMOKE_TEST` console prefix. A running report is replaced atomically by the completion/failure report. Copy the artifact back after completion:

```sh
xcrun devicectl device copy from --device YOUR_DEVICE_ID --domain-type appDataContainer --domain-identifier com.luca.campingbuddy.prototype --source Documents/DeviceSmokeTest.json --destination evaluation/runs/physical-device-smoke.json
```

Require `status: passed`, `generatedAnswer: true`, and `simulator: false`. Review the actual answer and source texts too. The report explicitly does not claim disabled radios, Mac-off operation, cold independent launch, total process memory, battery, heat, or expert-validated advice. MLX peak is allocator memory only.

An optional XCTest version exists in UITests/PhysicalModelTests.swift, but deploying its separate test runner may require a further free-profile app slot. It has been typechecked; do not label it passed until actually run on a device. The in-app check avoids that additional slot.

## Model download and switching check (version 0.3)

Use this separate opt-in flag while the phone has internet access:

```sh
xcrun devicectl device process launch --device YOUR_DEVICE_ID --terminate-existing com.luca.campingbuddy.prototype --camping-model-manager-smoke
xcrun devicectl device copy from --device YOUR_DEVICE_ID --domain-type appDataContainer --domain-identifier com.luca.campingbuddy.prototype --source Documents/ModelManagerSmokeTest.json --destination evaluation/runs/model-manager-smoke.json
```

This downloads the pinned Bonsai 27B model (5,159,412,937 bytes), using the app's actual download manager. If a verified copy already exists, the report explicitly records reuse. It loads the model, asks the saved sleeping-gear question, checks that an invalid selection is rejected and that the in-use model cannot be deleted, then begins another real request and cancels it. The actual output, completion, citation acceptance, identity, revision, and measurements are recorded. The final report also records app version/build.

This is a 4.81 GiB transfer over the phone's own connection, and Bonsai 27B has never been loaded on this project's iPhone. Expect the load, not the download, to be the step that fails first if memory is short; a jetsam kill ends the process without writing a report, which is itself the result.

The download has a 600-second deadline; loading and answering have 120-second limits. A 4.81 GiB download may well exceed 600 seconds on a slow connection — that is a deadline failure, not a model failure. Cancellation joins the ongoing operation before the failure report is written. A source-check failure still allows the cancellation sequence to run and is retained as a failed result. Overall `status: passed` requires the completed, accepted answer with matching identity/revision plus the cancellation and protection checks. Review the actual advice separately: passing citation identity checks does not establish that every recommendation is supported.

This test needs networking for the download and leaves `offlineVerified` false. It does not change phone radios or establish independent operation with the Mac off. It installs no additional app and does not bulk-download the catalog.
