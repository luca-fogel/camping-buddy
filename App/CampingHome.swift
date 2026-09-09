import SwiftUI

struct CampingHome: View {
    @State private var setup = Result { try ModelLibrary.bundled() }

    var body: some View {
        switch setup {
        case .success(let library): CampingTabs(library: library)
        case .failure(let error):
            ContentUnavailableView {
                Label("Model library unavailable", systemImage: "exclamationmark.circle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try again") { setup = Result { try ModelLibrary.bundled() } }
            }.tint(CampStyle.accent)
        }
    }
}

private struct CampingTabs: View {
    @StateObject private var model: ChatModel
    @StateObject private var modelLibrary: ModelLibrary
    @State private var selectedTab = 0
    @State private var selectedPassage: ReferencePassage?
    @State private var showsModels = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize

    init(library: ModelLibrary) {
        _modelLibrary = StateObject(wrappedValue: library)
        _model = StateObject(wrappedValue: ChatModel(modelLibrary: library))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CampingChat(model: model, modelLibrary: modelLibrary,
                        openGuide: { selectedPassage = $0 }, openModels: { showsModels = true })
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }.tag(0)
            FieldLibrary(passages: model.library?.passages ?? [], openGuide: { selectedPassage = $0 })
                .tabItem { Label("Library", systemImage: "books.vertical") }.tag(1)
            CampingSettings(model: model, modelLibrary: modelLibrary, openModels: { showsModels = true })
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .tint(CampStyle.accent)
        .task {
            await modelLibrary.prepare()
            await DeviceSmokeTest.runIfRequested(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.stop() }
            if phase == .active { Task { await modelLibrary.refresh() } }
        }
        .sheet(isPresented: $showsModels) {
            ModelsView(model: model, library: modelLibrary)
                .dynamicTypeSize(textSize)
        }
        .sheet(item: $selectedPassage) { passage in
            GuideReader(passage: passage) {
                model.draft = GuidePresentation(passage).question
                selectedPassage = nil
                selectedTab = 0
            }
        }
    }
}
