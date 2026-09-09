import SwiftUI

struct ModelsView: View {
    @ObservedObject var model: ChatModel
    @ObservedObject var library: ModelLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var detail: ModelDescriptor?
    @State private var removal: ModelDescriptor?
    @State private var actionError: String?

    private var savedBytes: Int64 { library.inventory.reduce(0) { $0 + $1.totalBytes } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    introduction
                    if let error = library.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.callout).campCard().accessibilityIdentifier("modelLibraryError")
                    }
                    ForEach(library.catalog.models) { descriptor in modelCard(descriptor) }
                    Text("The model runs entirely on this iPhone. It has not yet been tested on this device, and answer quality varies; check the saved guides behind an answer.")
                        .font(.caption).foregroundStyle(CampStyle.secondary).lineSpacing(3).padding(.top, 6)
                }.padding(22).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .background(CampStyle.background).foregroundStyle(CampStyle.ink)
            .navigationTitle("Model").navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("modelsDone")
                }
            }
            .task { await library.prepare() }
            .sheet(item: $detail) { ModelDetailView(descriptor: $0).dynamicTypeSize(textSize) }
            .confirmationDialog("Remove \(removal?.name ?? "model")?", isPresented: Binding(
                get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                    if let descriptor = removal {
                        Button("Remove download", role: .destructive) {
                            Task {
                                do { try await library.remove(descriptor.id) }
                                catch { actionError = error.localizedDescription }
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) { removal = nil }
                } message: {
                    Text("This frees the downloaded files. You can download the model again later, but you cannot ask questions until you do.")
                }
            .alert("Couldn’t change the model", isPresented: Binding(
                get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                    Button("OK", role: .cancel) { actionError = nil }
                } message: { Text(actionError ?? "") }
        }.tint(CampStyle.accent)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "internaldrive").font(.title2).foregroundStyle(CampStyle.accent)
                    .frame(width: 44, height: 44).background(CampStyle.subtle, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your assistant, on your phone.").font(.title3.weight(.semibold))
                    Text("Save the model once while you have signal. After that, answers need no connection.")
                        .font(.subheadline).foregroundStyle(CampStyle.secondary).lineSpacing(3)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(savedBytes > 0 ? "\(ModelSize.string(savedBytes)) downloaded" : "Nothing downloaded yet")
                    .font(.caption.weight(.medium))
                Spacer(minLength: 8)
                if let bytes = library.availableDiskBytes {
                    Text("\(ModelSize.string(bytes)) available").font(.caption)
                }
            }.foregroundStyle(CampStyle.secondary)
            Divider().overlay(CampStyle.line)
            Label("This is a large download. Keep the app open until it finishes, and use Wi-Fi.", systemImage: "wifi")
                .font(.caption).foregroundStyle(CampStyle.secondary).lineSpacing(3)
        }.campCard()
    }

    private func modelCard(_ descriptor: ModelDescriptor) -> some View {
        let installed = library.installed(descriptor.id)
        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(descriptor.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("\(formatLabel(descriptor)) · \(ModelSize.string(descriptor.totalBytes))")
                        .font(.caption).foregroundStyle(CampStyle.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    detail = descriptor
                } label: {
                    Image(systemName: "info.circle").font(.body).frame(width: 44, height: 44)
                }.foregroundStyle(CampStyle.secondary)
                    .accessibilityLabel("About \(descriptor.name)")
                    .accessibilityIdentifier("modelInfo-\(descriptor.id)")
            }
            HStack(spacing: 6) {
                Image(systemName: "cpu").font(.caption2)
                Text(verificationLabel(descriptor)).font(.caption2.weight(.medium))
            }.foregroundStyle(CampStyle.accent)
            downloadState(descriptor)
            if installed {
                HStack(spacing: 12) {
                    Label("Saved on this iPhone", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(CampStyle.accent)
                        .frame(minHeight: 44)
                    Spacer(minLength: 0)
                    removeButton(descriptor, label: "Remove \(descriptor.name)")
                }
            } else if !isDownloading(descriptor.id) {
                HStack {
                    Button { library.download(descriptor.id) } label: {
                        Label(downloadLabel(descriptor.id), systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 8).frame(minHeight: 38)
                    }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 12))
                        .disabled(!library.isInitialized)
                        .accessibilityIdentifier("downloadModel-\(descriptor.id)")
                    Spacer(minLength: 0)
                    removeButton(descriptor, label: "Remove incomplete \(descriptor.name) download")
                }
            }
        }.campCard().accessibilityElement(children: .contain)
            .accessibilityIdentifier("modelCard-\(descriptor.id)")
    }

    @ViewBuilder private func removeButton(_ descriptor: ModelDescriptor, label: String) -> some View {
        if library.removable(descriptor.id) {
            Button { removal = descriptor } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }.foregroundStyle(CampStyle.secondary)
                .accessibilityLabel(label)
                .accessibilityIdentifier("removeModel-\(descriptor.id)")
        }
    }

    @ViewBuilder private func downloadState(_ descriptor: ModelDescriptor) -> some View {
        if let state = library.downloads[descriptor.id] {
            switch state {
            case .progress(let received, let total):
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(received), total: Double(max(total, 1))).tint(CampStyle.accent)
                    HStack {
                        Text("\(ModelSize.string(received)) of \(ModelSize.string(total))").font(.caption).monospacedDigit()
                        Spacer()
                        Button("Pause") { library.cancelDownload(descriptor.id) }.font(.caption.weight(.medium)).frame(minHeight: 44)
                    }
                }
            case .verifying:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking download…").font(.caption)
                }.foregroundStyle(CampStyle.secondary)
            case .paused:
                Label("Download paused", systemImage: "pause.circle").font(.caption).foregroundStyle(CampStyle.secondary)
            case .failed(let reason):
                Text(reason).font(.caption).foregroundStyle(CampStyle.secondary).fixedSize(horizontal: false, vertical: true)
            case .ready: EmptyView()
            }
        }
    }

    private func isDownloading(_ id: String) -> Bool {
        switch library.downloads[id] {
        case .progress, .verifying: true
        default: false
        }
    }
    private func downloadLabel(_ id: String) -> String {
        switch library.downloads[id] {
        case .paused(let resumable): resumable ? "Resume download" : "Retry download"
        case .failed: "Retry download"
        default: "Download"
        }
    }
}

private struct ModelDetailView: View {
    let descriptor: ModelDescriptor
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(descriptor.name).font(.title2.weight(.semibold))
                    LabeledContent("Download size", value: ModelSize.string(descriptor.totalBytes))
                        .accessibilityIdentifier("modelDownloadSize")
                    LabeledContent("Family", value: descriptor.family)
                    LabeledContent("Format", value: formatLabel(descriptor))
                        .accessibilityIdentifier("modelFileFormat")
                    if let parameters = descriptor.parameterCount { LabeledContent("Parameters", value: parameters) }
                }
                Section("Compatibility") {
                    Text(verificationLabel(descriptor)).font(.subheadline.weight(.medium))
                    Text(descriptor.compatibilityNote).font(.subheadline)
                    Text("Removing and re-downloading the model starts a fresh conversation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Source & license") {
                    Text(descriptor.provenance.components(separatedBy: " Source:").first ?? descriptor.provenance)
                        .font(.subheadline)
                    LabeledContent("License", value: descriptor.license)
                    if let url = provenanceLink(after: "License: ") {
                        Link(destination: url) { Label("Read the publisher’s license", systemImage: "doc.text") }
                    }
                    if let url = URL(string: "https://huggingface.co/\(descriptor.repository)/tree/\(descriptor.revision)") {
                        Link(destination: url) { Label("View model and license", systemImage: "arrow.up.right.square") }
                    }
                    Text("Source pages open online. Downloaded model files and their included attribution stay on your phone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Model details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("modelDetailsDone")
                } }
        }.tint(CampStyle.accent)
    }

    private func provenanceLink(after marker: String) -> URL? {
        guard let range = descriptor.provenance.range(of: marker),
              let token = descriptor.provenance[range.upperBound...].split(separator: " ").first,
              let url = URL(string: String(token).trimmingCharacters(in: CharacterSet(charactersIn: "."))),
              url.scheme == "https", url.host == "huggingface.co" else { return nil }
        return url
    }
}

private func verificationLabel(_ descriptor: ModelDescriptor) -> String {
    descriptor.validationStatus == "device-smoke-tested" ? "Tested on iPhone 15 Pro" : "Compatible format · Not yet phone-tested"
}

private func formatLabel(_ descriptor: ModelDescriptor) -> String {
    "MLX · \(descriptor.quantizationBits)-bit"
}

enum ModelSize {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        // Otherwise a zero total reads "Zero KB".
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
