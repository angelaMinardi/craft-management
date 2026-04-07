//
//  MascotStoryChapter.swift
//  PatternVault
//

import Foundation

enum MascotStoryTrigger: String, Codable {
    case onboardingReturn
    case streak3
    case firstPatternComplete
    case streak7
    case saved10
    case firstNote
    case completed3
    case saved25
    case streak14
    case seasonal
}

struct MascotStoryChapter: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let trigger: MascotStoryTrigger
    let lines: [String]
    let hook: String
}

struct MascotStoryProgress: Codable {
    var unlockedIds: Set<String> = []
    var viewedIds: Set<String> = []
    var pendingId: String?
}

