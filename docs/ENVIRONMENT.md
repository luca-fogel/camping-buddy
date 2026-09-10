# Verified development environment

Checked 2026-09-05. Hardware identifiers and device serial numbers are intentionally omitted.

| Item | Observed |
|---|---|
| Mac | MacBook Pro, Apple M2 Max, 12 CPU cores, 64 GB unified memory |
| Free storage before setup | Approximately 377 GiB on the data volume |
| Xcode | 26.6, build 17F113, selected `/Applications/Xcode.app/Contents/Developer` |
| Metal compiler | Apple's Metal Toolchain 17F109, installed through Xcode (687.9 MB download) |
| Swift | 6.3.3 |
| iPhone SDK | 26.5 |
| XcodeGen | Installed locally at `/opt/homebrew/bin/xcodegen` |
| Simulator runtimes | Includes iOS 17.2, 18.1, 26.3, 26.4, 26.5 |
| Physical device | iPhone 15 Pro, iOS 26.6.1, Developer Mode enabled |
| Phone readiness | Subsequent USB connection resolved the disk image issue; developer image services are available |
| Signing / installation | Signed Release build installed successfully on the physical iPhone |
| Model assets | The pinned Ternary Bonsai 8B MLX 2-bit snapshot is the only model; unrelated adapters or models were not substituted |
| Training application | Installed MLX LoRA Studio beta-102.57.7; see STUDIO_COMPATIBILITY.md for the separate read-only compatibility audit |

This records the environment actually used, not a minimum supported-device specification. Developer setup requires working Xcode platform services and access to public dependencies for the initial build. No existing training process was stopped or installed training runtime changed during this prototype's preparation.

Keep the checkout in a dedicated project directory of your choice. No source from Solvr was copied. Public package source downloads are in project-local `.build/packages` or disposable `.research`; model assets are in the ignored `Resources/Models` subtree. Keep the Xcode package resolution file and `model-lock.json` with the project for reproducibility.
