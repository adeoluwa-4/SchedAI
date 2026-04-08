//
//  Theme.swift
//  SchedAI
//
//  Created by Adeoluwa Adekoya on 9/23/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// ✅ App-wide theme preference
enum AppTheme: String, CaseIterable, Identifiable, Codable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System Default"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// nil = follow system
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

extension Color {
    // ✅ Theme colors that won’t crash if an asset is missing
    struct theme {
        static var background: Color {
            #if canImport(UIKit)
            return Color(uiColor: UIColor(named: "Background") ?? UIColor.systemBackground)
            #else
            return Color(.systemBackground)
            #endif
        }

        static var card: Color {
            #if canImport(UIKit)
            return Color(uiColor: UIColor(named: "Card") ?? UIColor.secondarySystemBackground)
            #else
            return Color(.secondarySystemBackground)
            #endif
        }

        static var separator: Color {
            #if canImport(UIKit)
            return Color(uiColor: UIColor(named: "Separator") ?? UIColor.separator)
            #else
            return Color.gray.opacity(0.3)
            #endif
        }

        static var accent: Color { Color.accentColor }
    }

    static func priority(_ p: TaskPriority) -> Color {
        #if canImport(UIKit)
        func named(_ name: String, fallback: UIColor) -> Color {
            Color(uiColor: UIColor(named: name) ?? fallback)
        }
        switch p {
        case .high:   return named("PriorityHigh", fallback: .systemRed)
        case .medium: return named("PriorityMedium", fallback: .systemOrange)
        case .low:    return named("PriorityLow", fallback: .systemGreen)
        }
        #else
        switch p {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
        #endif
    }
}
