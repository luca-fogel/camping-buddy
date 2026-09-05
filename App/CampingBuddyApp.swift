import SwiftUI
import UIKit

@main
struct CampingBuddyApp: App {
    @AppStorage("appearance") private var appearance = "system"

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ui-testing-appearance"), arguments.indices.contains(index + 1) {
            UserDefaults.standard.set(arguments[index + 1], forKey: "appearance")
        }
        #endif
    }

    private var largeTestText: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing-large-text")
        #else
        false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if largeTestText { CampingHome().dynamicTypeSize(.accessibility2) }
                else { CampingHome() }
            }
            .tint(CampStyle.accent)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}
