import SwiftUI

struct CampingSettings: View {
    @ObservedObject var model: ChatModel
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 13) {
                            CampMark(size: 50)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Gemma 4 E2B").font(.title3.weight(.semibold))
                                Label("Saved on this iPhone", systemImage: "internaldrive")
                                    .font(.caption).foregroundStyle(CampStyle.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                if model.isLoading { ProgressView().controlSize(.small) }
                                else { Circle().fill(CampStyle.accent).frame(width: 6, height: 6) }
                                Text(model.modelStateLabel).font(.subheadline.weight(.medium))
                            }
                            Text(model.isReady ? "Your assistant is ready to answer from the guides on your phone." : "Your assistant loads automatically when you ask your first question.")
                                .font(.subheadline).foregroundStyle(CampStyle.secondary).lineSpacing(3)
                        }
                        if !model.isReady {
                            Button { model.loadModel() } label: {
                                Text(model.isLoading ? "Preparing…" : "Prepare assistant")
                                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .foregroundStyle(CampStyle.background)
                            }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 14))
                                .disabled(model.isBusy).accessibilityIdentifier("loadModel")
                        }
                        Text(model.status).font(.caption).foregroundStyle(CampStyle.secondary)
                            .accessibilityIdentifier("modelStatus")
                    }.campCard()
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Appearance", systemImage: "circle.lefthalf.filled").font(.subheadline.weight(.medium))
                        Picker("Appearance", selection: $appearance) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }.pickerStyle(.segmented).accessibilityIdentifier("appearancePicker")
                    }.campCard()
                    VStack(alignment: .leading, spacing: 18) {
                        info("Private by design", text: "Answers run on your iPhone. No account, cloud service, or connection is needed.", icon: "lock.shield")
                        Divider()
                        info("A fresh start each time", text: "Each question is independent. Your conversation stays in memory and clears when the app closes.", icon: "bubble.left")
                    }.campCard()
                    VStack(spacing: 0) {
                        NavigationLink { AboutCamping() } label: { settingsRow("About Camping Buddy", icon: "info.circle") }
                        Divider().padding(.leading, 32)
                        NavigationLink { ModelDiagnostics(model: model) } label: { settingsRow("Model details", icon: "cpu") }
                        Divider().padding(.leading, 32)
                        NavigationLink { NoticesView() } label: { settingsRow("Licenses & acknowledgments", icon: "doc.text") }
                    }.padding(.horizontal, 20).background(CampStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                    VStack(spacing: 5) {
                        Text("CAMPING BUDDY").font(.system(size: 10, weight: .semibold)).tracking(2)
                        Text("Made for a little more outside.").font(.caption)
                    }.foregroundStyle(CampStyle.secondary).frame(maxWidth: .infinity).padding(.bottom, 14)
                }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.foregroundStyle(CampStyle.ink).background(CampStyle.background)
                .navigationTitle("Settings")
        }
    }

    private func info(_ title: String, text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon).font(.title3).foregroundStyle(CampStyle.accent).frame(width: 25)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.medium))
                Text(text).font(.caption).foregroundStyle(CampStyle.secondary).lineSpacing(3)
            }
        }
    }

    private func settingsRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(CampStyle.accent)
            Text(title).font(.subheadline).foregroundStyle(CampStyle.ink)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(CampStyle.secondary)
        }.padding(.vertical, 19).contentShape(Rectangle())
    }
}

private struct AboutCamping: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CampMark(size: 70)
                Text("A companion for\nyour first weekends.").font(.system(.largeTitle, design: .rounded, weight: .semibold))
                Text("Camping Buddy helps with general gear and preparation for beginner weekend camping in the northeastern US.")
                Text("The eight saved guides are original summaries based on National Park Service sources. This development library has not been reviewed by an expert.")
                Text("AI answers can make mistakes. References show which saved guides were used; they do not guarantee that an answer interpreted them correctly.")
                Text("Check weather, closures, permits, and fire rules with your destination before leaving. Camping Buddy cannot provide live conditions, medical diagnosis, or edible-plant identification.")
                Text("Version 0.2 · Development preview").font(.caption).foregroundStyle(CampStyle.secondary)
            }.lineSpacing(4).padding(24)
        }.foregroundStyle(CampStyle.ink).background(CampStyle.background)
            .navigationTitle("About").navigationBarTitleDisplayMode(.inline)
    }
}

private struct ModelDiagnostics: View {
    @ObservedObject var model: ChatModel
    var body: some View {
        List {
            Section("On this device") {
                LabeledContent("Model", value: "Gemma 4 E2B IT")
                LabeledContent("Format", value: "MLX · 4-bit")
                LabeledContent("Bundled files", value: "3.58 GB")
                Text("Standard MLX affine quantization. This is distinct from Google's LiteRT mobile QAT artifact.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Current session") {
                Text(model.status)
                Text(model.metrics).font(.caption).monospacedDigit().textSelection(.enabled)
                Text("Memory figures measure the MLX allocator, not the app's total memory. Battery, heat, and performance away from the Mac still need field testing.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Model details").navigationBarTitleDisplayMode(.inline)
    }
}

private struct NoticesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Gemma 4 by Google DeepMind · MLX conversion by MLX Community").font(.headline)
                Text("Model snapshot: 238767527555cb75a05732a84dff5d6ba0dd6809. Standard MLX 4-bit; distinct from the LiteRT mobile QAT artifact.")
                Text("The original Google model card declares Apache 2.0. The conversion card has an inconsistent Gemma license label; both original cards and the full license are included in this build.")
                Text(localText("LICENSE-APACHE-2.0", directory: "Models/gemma-4-E2B-it-4bit"))
                Text(localText("ThirdPartyNotices", directory: "Acknowledgments"))
            }.font(.caption).textSelection(.enabled).padding(24)
        }.background(CampStyle.background).navigationTitle("Acknowledgments").navigationBarTitleDisplayMode(.inline)
    }

    private func localText(_ name: String, directory: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: directory),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "This license file is missing from the build. Rebuild with the complete resource bundle."
        }
        return text
    }
}
