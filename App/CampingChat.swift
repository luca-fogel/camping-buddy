import SwiftUI
import UIKit

struct CampingChat: View {
    @ObservedObject var model: ChatModel
    var openGuide: (ReferencePassage) -> Void
    var openSettings: () -> Void
    @FocusState private var composerFocused: Bool
    private var busy: Bool { model.isBusy }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 28) {
                        if model.entries.isEmpty { welcome }
                        ForEach(model.entries) { entry in
                            AnswerView(entry: entry, isWorking: model.isGenerating && entry.id == model.entries.last?.id,
                                       openGuide: openGuide).id(entry.id)
                        }
                        if model.isLoading {
                            HStack(spacing: 12) {
                                ProgressView().tint(CampStyle.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Preparing your assistant").font(.subheadline.weight(.medium))
                                    Text("Opening the model saved on this iPhone.").font(.caption).foregroundStyle(CampStyle.secondary)
                                }
                                Spacer(minLength: 0)
                            }.campCard()
                        }
                        if let error = model.libraryError {
                            Label(error, systemImage: "exclamationmark.circle").font(.callout).campCard()
                        }
                        if !model.isReady && !busy && model.status != "Model has not been loaded" {
                            Text(model.status).font(.callout).foregroundStyle(CampStyle.secondary).campCard()
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 8)
                        .frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.entries.last?.id) { _, id in
                    if let id {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) }
                    }
                }
                .onChange(of: model.isLoading) { _, loading in
                    if loading {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .background(CampStyle.background)
                .navigationTitle("Camping Buddy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            model.clearConversation()
                            composerFocused = false
                        } label: { Image(systemName: "square.and.pencil") }
                            .disabled(model.entries.isEmpty || busy)
                            .accessibilityLabel("New conversation")
                            .accessibilityIdentifier("newConversation")
                    }
                }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            Button(action: openSettings) {
                HStack(spacing: 6) {
                    Circle().fill(CampStyle.accent).frame(width: 5, height: 5)
                    Text("Gemma 4 E2B").font(.caption.weight(.medium))
                    Text("· On device").font(.caption)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }.foregroundStyle(CampStyle.secondary).padding(.vertical, 9).padding(.horizontal, 13)
                    .background(CampStyle.subtle, in: Capsule())
                    .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Gemma 4 E2B, on device. Open settings")

            VStack(spacing: 16) {
                CampMark(size: 66)
                Text("A little more ready.\nA little more outside.")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .tracking(-0.6).multilineTextAlignment(.center).foregroundStyle(CampStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your pocket companion for\nplanning a weekend under the stars.")
                    .font(.subheadline).multilineTextAlignment(.center)
                    .foregroundStyle(CampStyle.secondary).lineSpacing(3)
            }.padding(.top, 4)

            VStack(spacing: 0) {
                prompt("Pack for a good night", subtitle: "Shelter, sleeping bags & the essentials", icon: "moon.stars", question: "What sleeping gear should I pack?")
                Divider().overlay(CampStyle.line).padding(.leading, 54)
                prompt("Keep food camp-ready", subtitle: "Simple storage around wildlife", icon: "pawprint", question: "How should I store food around bears?")
                Divider().overlay(CampStyle.line).padding(.leading, 54)
                prompt("Plan your first weekend", subtitle: "The things to check before you go", icon: "map", question: "What should I do before leaving home?")
            }
            .padding(.horizontal, 16)
            .background(CampStyle.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(CampStyle.line.opacity(0.7), lineWidth: 0.5))
        }.padding(.bottom, 4)
    }

    private func prompt(_ title: String, subtitle: String, icon: String, question: String) -> some View {
        Button {
            model.draft = question
            composerFocused = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 21, weight: .regular))
                    .frame(width: 26).foregroundStyle(CampStyle.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(CampStyle.ink)
                    Text(subtitle).font(.caption).foregroundStyle(CampStyle.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(CampStyle.secondary)
            }.padding(.vertical, 17).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(busy)
    }

    private var composer: some View {
        VStack(spacing: 9) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask a question…", text: $model.draft,
                          prompt: Text("Ask a question…").foregroundStyle(CampStyle.secondary), axis: .vertical)
                    .font(.body).lineLimit(1...5).focused($composerFocused)
                    .padding(.vertical, 11).padding(.leading, 6)
                    .accessibilityIdentifier("questionInput")
                    .disabled(busy)
                Button {
                    if busy { model.stop() } else {
                        composerFocused = false
                        model.sendWithPreparation()
                    }
                } label: {
                    Image(systemName: busy ? "stop.fill" : "arrow.up")
                        .font(.system(size: busy ? 13 : 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(model.canSend || busy ? CampStyle.background : CampStyle.secondary)
                        .background(model.canSend || busy ? CampStyle.accent : CampStyle.subtle, in: Circle())
                }.disabled(!busy && !model.canSend)
                    .accessibilityLabel(busy ? "Stop answer" : "Send question")
                    .accessibilityIdentifier(busy ? "stopAnswer" : "sendQuestion")
            }.padding(8).background(CampStyle.surface, in: RoundedRectangle(cornerRadius: 30))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(CampStyle.line, lineWidth: 1))
            Text(model.draft.count > 1200 ? "Keep your question under 1,200 characters." : "On-device AI · Each question starts fresh")
                .font(.caption2).foregroundStyle(CampStyle.secondary)
        }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
            .frame(maxWidth: 650).frame(maxWidth: .infinity)
            .background(CampStyle.background)
    }
}

private struct AnswerView: View {
    let entry: ChatEntry
    let isWorking: Bool
    let openGuide: (ReferencePassage) -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Spacer(minLength: 28)
                Text(entry.question).font(.body).textSelection(.enabled)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(CampStyle.subtle, in: RoundedRectangle(cornerRadius: 22))
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 9) {
                    CampMark(size: 27)
                    Text("Camping Buddy").font(.subheadline.weight(.semibold))
                    if isWorking { ProgressView().scaleEffect(0.75) }
                    Spacer()
                }
                if isWorking {
                    Text("Thinking with your saved guides…").font(.body).foregroundStyle(CampStyle.secondary)
                } else {
                    answerText
                }
                if !isWorking && !entry.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.isGenerated ? "REFERENCES" : "RELATED GUIDES")
                            .font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(CampStyle.secondary)
                        ForEach(Array(entry.sources.enumerated()), id: \.element.id) { index, passage in
                            Button { openGuide(passage) } label: {
                                HStack(spacing: 10) {
                                    Text("\(index + 1)").font(.caption.weight(.medium))
                                        .frame(width: 23, height: 23).background(CampStyle.subtle, in: RoundedRectangle(cornerRadius: 6))
                                    Text(passage.title).font(.caption.weight(.medium)).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                }.padding(10).frame(minHeight: 44).background(CampStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).foregroundStyle(CampStyle.accent)
                                .accessibilityIdentifier("answer-guide-\(passage.id)")
                        }
                    }
                }
                if entry.isGenerated {
                    HStack(alignment: .center) {
                        Text("AI answer · Check the guides").font(.caption2).foregroundStyle(CampStyle.secondary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = entry.answer
                            copied = true
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption).frame(width: 44, height: 44)
                        }.accessibilityLabel(copied ? "Answer copied" : "Copy answer")
                    }
                }
            }
        }.foregroundStyle(CampStyle.ink)
    }

    private var answerText: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(displayText.components(separatedBy: "\n").filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, line in
                let bullet = line.hasPrefix("- ") || line.hasPrefix("* ")
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    if bullet { Text("•").foregroundStyle(CampStyle.accent) }
                    Text(markdown(bullet ? String(line.dropFirst(2)) : line))
                        .font(.body).lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var displayText: String {
        guard entry.isGenerated else { return entry.answer }
        return entry.sources.enumerated().reduce(entry.answer) { text, item in
            text.replacingOccurrences(of: "[\(item.element.id)]", with: "[\(item.offset + 1)]")
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
