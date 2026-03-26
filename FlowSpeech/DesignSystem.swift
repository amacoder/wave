//
//  DesignSystem.swift
//  FlowSpeech
//
//  Centralized design tokens for the blue palette
//

import SwiftUI

enum DesignSystem {
    enum Colors {
        /// #0F172A - darkest background, overlays, menu bar popover
        static let deepNavy = Color(hex: "0F172A")
        /// #2563EB - primary accent, recording indicator, gradients
        static let vibrantBlue = Color(hex: "2563EB")
        /// #E0F2FE - light text on dark backgrounds, highlights
        static let softBlueWhite = Color(hex: "E0F2FE")
        /// #0D9488 - legacy teal for existing gradient endpoints
        static let teal = Color(hex: "0D9488")

        /// Semantic aliases for common uses
        static let accentGradient = LinearGradient(
            colors: [vibrantBlue, teal],
            startPoint: .leading,
            endPoint: .trailing
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
