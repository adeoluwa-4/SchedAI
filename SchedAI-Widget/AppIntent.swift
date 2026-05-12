//
//  AppIntent.swift
//  SchedAI-Widget
//
//  Created by Adeoluwa Adekoya on 4/17/26.
//

import WidgetKit
import AppIntents
import Foundation

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "SchedAI Plan" }
    static var description: IntentDescription { "Shows your current SchedAI plan." }
}

struct OpenVoicePlannerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Voice Planner"
    static var description = IntentDescription("Open SchedAI and start voice planning.")
    static var openAppWhenRun: Bool = true

    private enum WidgetBridge {
        static let appGroupID = "group.me.SchedAI.shared"
        static let voiceRequestKey = "widget_voice_request_v1"
    }

    func perform() async throws -> some IntentResult {
        if let defaults = UserDefaults(suiteName: WidgetBridge.appGroupID) {
            defaults.set(true, forKey: WidgetBridge.voiceRequestKey)
        }
        return .result()
    }
}
