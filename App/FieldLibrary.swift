import SwiftUI
import UIKit

struct FieldLibrary: View {
    let passages: [ReferencePassage]
    let openGuide: (ReferencePassage) -> Void
    @State private var search = ""
    @State private var category = "All"
    @FocusState private var searchFocused: Bool

    private var filtered: [ReferencePassage] {
        passages.filter { passage in
            (category == "All" || GuidePresentation(passage).category == category) &&
            (search.trimmingCharacters(in: .whitespaces).isEmpty ||
             ([passage.title, passage.text] + passage.keywords).joined(separator: " ").localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("SAVED ON YOUR PHONE", systemImage: "arrow.down.circle")
                                .font(.caption2.weight(.semibold)).tracking(1)
                            Text("Good preparation\ngoes a long way.")
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                            Text("\(passages.count) quick guides for a weekend outside.")
                                .font(.caption).foregroundStyle(CampStyle.cream.opacity(0.85))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "tree.fill").font(.system(size: 50, weight: .light))
                            .foregroundStyle(CampStyle.cream.opacity(0.75)).accessibilityHidden(true)
                    }.foregroundStyle(CampStyle.cream).padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CampStyle.pine, in: RoundedRectangle(cornerRadius: 24))
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").foregroundStyle(CampStyle.secondary)
                            TextField("Search your guides", text: $search)
                                .focused($searchFocused).submitLabel(.search)
                                .onSubmit { searchFocused = false }
                                .accessibilityIdentifier("librarySearch")
                            if !search.isEmpty {
                                Button { search = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(CampStyle.secondary)
                                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                                }.accessibilityLabel("Clear search")
                            }
                        }.padding(.horizontal, 15).frame(minHeight: 50)
                            .background(CampStyle.subtle, in: RoundedRectangle(cornerRadius: 15))
                        Picker("Guide category", selection: $category) {
                            ForEach(["All", "Plan", "Gear", "Camp"], id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("guideCategory")
                    }
                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: search.isEmpty ? category : search)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filtered) { passage in
                                Button {
                                    searchFocused = false
                                    openGuide(passage)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: GuidePresentation(passage).icon)
                                            .font(.system(size: 22)).foregroundStyle(CampStyle.accent)
                                            .frame(width: 47, height: 49)
                                            .background(CampStyle.subtle, in: RoundedRectangle(cornerRadius: 14))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(passage.title).font(.subheadline.weight(.medium)).foregroundStyle(CampStyle.ink)
                                            Text("\(GuidePresentation(passage).category) · 1 min read")
                                                .font(.caption).foregroundStyle(CampStyle.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(CampStyle.secondary)
                                    }.padding(.vertical, 15).contentShape(Rectangle())
                                }.buttonStyle(.plain).multilineTextAlignment(.leading)
                                    .accessibilityIdentifier("guide-\(passage.id)")
                                if passage.id != filtered.last?.id { Divider().padding(.leading, 61) }
                            }
                        }
                    }
                    Text("Original summaries based on National Park Service guidance. This starter library has not been reviewed by an expert.")
                        .font(.caption).foregroundStyle(CampStyle.secondary).lineSpacing(3)
                }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
                .background(CampStyle.background)
                .navigationTitle("Field library")
                .onDisappear { searchFocused = false }
        }
    }
}

struct GuideReader: View {
    let passage: ReferencePassage
    let askQuestion: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: GuidePresentation(passage).icon)
                            .font(.system(size: 30)).foregroundStyle(CampStyle.accent)
                            .frame(width: 64, height: 64).background(CampStyle.subtle, in: RoundedRectangle(cornerRadius: 20))
                        Text("\(GuidePresentation(passage).category.uppercased())  /  1 MIN READ")
                            .font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(CampStyle.secondary)
                        Text(passage.title).font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .tracking(-0.6).fixedSize(horizontal: false, vertical: true)
                        Label("Available offline", systemImage: "checkmark.circle")
                            .font(.caption).foregroundStyle(CampStyle.accent)
                    }
                    Text(passage.text).font(.system(.body)).lineSpacing(7).textSelection(.enabled)
                        .accessibilityIdentifier("guideBody")
                    Button(action: askQuestion) {
                        Label("Ask about this guide", systemImage: "bubble.left")
                            .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 14)
                    }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 16))
                        .accessibilityIdentifier("askAboutGuide")
                    VStack(alignment: .leading, spacing: 12) {
                        Label("ABOUT THIS GUIDE", systemImage: "book.closed")
                            .font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(CampStyle.secondary)
                        Text(passage.sourceTitle).font(.subheadline.weight(.medium))
                        Text("An original summary, saved September 5, 2026. It has not been reviewed by an expert.")
                            .font(.caption).foregroundStyle(CampStyle.secondary).lineSpacing(3)
                        DisclosureGroup("Source details") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(passage.sourceURL).textSelection(.enabled)
                                Button {
                                    UIPasteboard.general.string = passage.sourceURL
                                    copied = true
                                } label: {
                                    Label(copied ? "Link copied" : "Copy source link", systemImage: copied ? "checkmark" : "doc.on.doc")
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }
                                Text("Source accessed: \(passage.accessedDate)")
                                Text(passage.region)
                                Text(passage.reviewStatus)
                                Text(passage.rights)
                            }.font(.caption).foregroundStyle(CampStyle.secondary).padding(.top, 12)
                        }.font(.subheadline)
                    }.campCard()
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.foregroundStyle(CampStyle.ink).background(CampStyle.background)
                .navigationTitle("Guide").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(CampStyle.accent).presentationDragIndicator(.visible)
    }
}
