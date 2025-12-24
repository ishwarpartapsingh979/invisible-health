//
//  OpenHomeIntent.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 23/12/25.
//

import AppIntents
import Foundation
public struct OpenHomeIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Open Home"
    public static var openAppWhenRun: Bool = true
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        return .result()
    }
}
