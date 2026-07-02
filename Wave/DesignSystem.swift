//
//  DesignSystem.swift
//  Wave
//
//  Centralized design tokens for the amber/yellow palette
//

import SwiftUI

enum DesignSystem {
    enum Colors {
        /// #FBBF24 - primary accent, amber yellow from the app icon
        static let accent = Color(hex: "FBBF24")
        /// #F59E0B - darker amber for gradient endpoints and emphasis
        static let accentDeep = Color(hex: "F59E0B")
        /// #1C1917 - darkest surface: overlay pill, dark chrome
        static let surfaceDark = Color(hex: "1C1917")
        /// #FEF3C7 - warm near-white for text on dark surfaces
        static let textOnDark = Color(hex: "FEF3C7")

        static let accentGradient = LinearGradient(
            colors: [Color(hex: "FDE68A"), Color(hex: "F59E0B")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 6
        static let card: CGFloat = 10
        static let sheet: CGFloat = 18
    }

    enum Typography {
        /// Inline page title (Flow-style); semantic font so Dynamic Type works
        static let pageTitle = Font.title.weight(.bold)
        static let pageSubtitle = Font.subheadline
        static let sectionLabel = Font.subheadline.weight(.medium)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
