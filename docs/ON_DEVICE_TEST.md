# Physical iPhone acceptance test

Recorded status: signed installation and connected physical generation passed on an iPhone 15 Pro / iOS 26.6.1 with the earlier interface. A real cited sleeping-gear answer completed in 6.42 seconds after a 2.55-second model load. Version 0.2 subsequently passed four simulator interface tests and a real single-Ask cold app-session check on the phone: 2.50-second model load and 3.97-second answer. The Mac remained connected and radio state was not changed. The independent test below still needs to be performed with the Mac off and the phone's radios disabled.

## Before disconnecting

1. No model weights ship inside the app. The build must contain `ReferenceLibrary/references.json`; the model itself is downloaded on the phone. Open Settings → Manage the model and complete the Ternary Bonsai 8B download (2.16 GiB) **while online**, before beginning this offline test. Confirm the card reads "Saved on this iPhone", and record the model ID and revision.
2. Open `CampingBuddy.xcodeproj` in Xcode. Select the CampingBuddy target, Signing & Capabilities, and your development team. Set a bundle identifier available to that team and keep automatic signing enabled. A personal development install may expire and need reinstalling; do not treat that as a shipping distribution solution.
3. Connect the intended iPhone by USB, unlock it, and accept Trust if shown. In Xcode → Window → Devices and Simulators, wait for preparation to finish. If a developer disk image error appears, resolve it there before continuing; use Xcode's required platform/support updates if offered. Record the actual phone model and iOS version used.
4. Select the physical iPhone and the CampingBuddy scheme. Edit Scheme → Run → Build Configuration → Release. Build and Run. Open Ask and send a camping-preparation question; the first Ask automatically prepares the downloaded model before answering. Settings → Prepare assistant is optional if you want to load it first. A load failure is a failed model gate; preserve the error and do not substitute a remote answer.
5. Confirm all eight Library entries open and the real generated answer has clickable local passage labels. Record app load/response/MLX allocator measurements as preliminary observations; model details are available in Settings. Xcode Instruments can measure total process memory during this separate connected run; MLX allocator peak is not total process memory.

## Independent offline gate

1. Stop the app and debugger. Disconnect the USB cable. Power the Mac off.
2. On the iPhone, enable Airplane Mode and explicitly switch Wi-Fi off in Settings (Airplane Mode alone can leave Wi-Fi enabled). Disable cellular and Bluetooth as well for this test. No tethering or other active network path should remain.
3. Force-quit Camping Buddy, then cold-launch it from the Home Screen. In Library, open a passage **before** your first Ask or manual model preparation. It must remain readable.
4. In Ask, send: “What sleeping bag and sleeping pad should I pack?” The first Ask automatically prepares the downloaded model, then generates the answer. Record load seconds and the complete response, source references, first-output and total-response times, and reported MLX memory; measurements are available under Settings → Model details. Tap a cited passage; it must open inside the app without a browser, authentication, or a download.
5. Ask a second independent question about food storage. Confirm a fresh answer is generated with local references while the Mac remains off.
6. Ask “Are campfires allowed at Acadia today?” and “Which wild mushrooms can I eat?” Expect a clear scope/evidence limitation with no invented current information or identification. Ask “Explain quantum cryptography” and expect insufficient local evidence.
7. Force-quit and repeat the first Ask with one supported question, confirming automatic model preparation works again. You may separately check Settings → Prepare assistant as the optional manual path. Record crashes, OS termination, low-memory warnings, timeouts, or missing files as failures. Never enter invented timing or memory values.
8. Repeat with ten short questions, using Stop at least once and checking that another question works afterward. In a later field trial, record battery percentage before/after, ambient conditions, thermal state, screen settings, and elapsed use. One short run does not establish battery life or heat suitability.

## What counts as a pass

The physical phone produces real fresh answers after cold launch and opens cited local passages with the Mac off and networking disabled. All required files are already on the phone; no account session, cached remote answer, server, or simulator is involved. Save the exact build/model/dependency pins alongside results. Good formatting alone does not establish correct or safe camping advice.

Use `evaluation/device-results-template.json` for the record. Leave unknown fields null. The full first milestone remains pending until this gate passes.
