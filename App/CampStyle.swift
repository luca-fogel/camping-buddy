import SwiftUI
import UIKit

enum CampStyle {
    static let accent = adaptive(light: 0x315C46, dark: 0xA3CEAF)
    static let background = adaptive(light: 0xFAFBF8, dark: 0x121613)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1D231E)
    static let subtle = adaptive(light: 0xEEF1EB, dark: 0x272F28)
    static let ink = adaptive(light: 0x202B23, dark: 0xEEF3EC)
    static let secondary = adaptive(light: 0x647066, dark: 0xACB7AC)
    static let line = adaptive(light: 0xDEE4DB, dark: 0x354035)
    static let pine = Color(red: 0.15, green: 0.28, blue: 0.21)
    static let cream = Color(red: 0.96, green: 0.96, blue: 0.89)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct CampMark: View {
    var size: CGFloat = 56
    var body: some View {
        Image("CampMark")
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}

struct GuidePresentation {
    let passage: ReferencePassage
    init(_ passage: ReferencePassage) { self.passage = passage }
    var category: String {
        switch passage.id {
        case "trip-plan", "check-local-rules", "offline-navigation": "Plan"
        case "sleep-system", "essentials": "Gear"
        default: "Camp"
        }
    }
    var icon: String {
        switch passage.id {
        case "trip-plan": "map"
        case "check-local-rules": "checklist"
        case "essentials": "backpack"
        case "offline-navigation": "location.north.line"
        case "sleep-system": "moon.stars"
        case "choose-campsite": "tent"
        case "food-storage": "pawprint"
        default: "mug"
        }
    }
    var question: String {
        switch passage.id {
        case "trip-plan": "How should I plan my first camping weekend?"
        case "check-local-rules": "What should I check before leaving home?"
        case "essentials": "What essential gear should I pack?"
        case "offline-navigation": "How should I prepare for navigating without service?"
        case "sleep-system": "What sleeping gear should I pack?"
        case "choose-campsite": "What should I look for when setting up my tent?"
        case "food-storage": "How should I store food around bears?"
        default: "How should I plan simple meals for camp?"
        }
    }
}

extension View {
    func campCard() -> some View {
        self.padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CampStyle.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(CampStyle.line.opacity(0.6), lineWidth: 0.5))
    }
}
