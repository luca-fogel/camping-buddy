import SwiftUI

struct CampingHome: View {
    @StateObject private var model = ChatModel()
    @State private var selectedTab = 0
    @State private var selectedPassage: ReferencePassage?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            CampingChat(model: model, openGuide: { selectedPassage = $0 }, openSettings: { selectedTab = 2 })
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }.tag(0)
            FieldLibrary(passages: model.library?.passages ?? [], openGuide: { selectedPassage = $0 })
                .tabItem { Label("Library", systemImage: "books.vertical") }.tag(1)
            CampingSettings(model: model)
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .tint(CampStyle.accent)
        .task { await DeviceSmokeTest.runIfRequested(model: model) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.stop() }
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
