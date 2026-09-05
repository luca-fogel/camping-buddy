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
