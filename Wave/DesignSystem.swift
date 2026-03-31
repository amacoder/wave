//
//  DesignSystem.swift
//  Wave
//
//  Centralized design tokens for the amber/yellow palette
//

import SwiftUI

enum DesignSystem {
    enum Colors {
        /// #1C1917 - darkest background, overlays, menu bar popover
        static let deepNavy = Color(hex: "1C1917")
        /// #FBBF24 - primary accent, amber yellow from icon
        static let vibrantBlue = Color(hex: "FBBF24")
        /// #FEF3C7 - light warm white for text on dark backgrounds
        static let softBlueWhite = Color(hex: "FEF3C7")
        /// #F59E0B - darker amber for gradient endpoints
        static let teal = Color(hex: "F59E0B")

        /// Semantic aliases for common uses
        static let accentGradient = LinearGradient(
            colors: [Color(hex: "FDE68A"), Color(hex: "F59E0B")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
