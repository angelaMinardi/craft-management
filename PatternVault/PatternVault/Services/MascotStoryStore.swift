//
//  MascotStoryStore.swift
//  PatternVault
//

import Foundation

@MainActor
final class MascotStoryStore: ObservableObject {
    static let shared = MascotStoryStore()

    private static let appGroupId = "group.com.patternvault.app"
    private static let progressKey = "mascot_story_progress"

    @Published private(set) var progress: MascotStoryProgress
    @Published var showingChapterId: String?
    @Published var showUnlockBanner = false

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupId) ?? .standard
        if let data = defaults.data(forKey: Self.progressKey),
           let decoded = try? JSONDecoder().decode(MascotStoryProgress.self, from: data) {
            progress = decoded
        } else {
            progress = MascotStoryProgress()
        }
    }

    var chapters: [MascotStoryChapter] {
        [
            chapter("chapter_1", "The Nest", .onboardingReturn,
                    ["[Name]'s nest is full of suspiciously shiny crafting supplies.",
                     "The best items are definitely not borrowed forever.",
                     "Someone downstairs is looking for their needles."],
                    hook: "This might become a problem."),
            chapter("chapter_2", "Caught", .streak3,
                    ["The crafter looks up. [Name] freezes with needles in both wings.",
                     "Nobody moves. Nobody blinks.",
                     "[Name] is out of excuses."],
                    hook: "There are not many escape routes."),
            chapter("chapter_3", "The Deal", .firstPatternComplete,
                    ["The crafter makes a deal: help use the supplies instead of stealing them.",
                     "[Name] sits down, deeply offended.",
                     "The needles start clicking."],
                    hook: "This is unexpectedly fun."),
            chapter("chapter_4", "Surprisingly Good", .streak7,
                    ["The first dishcloth is lumpy and heroic.",
                     "It is also not terrible.",
                     "[Name] pretends not to be proud."],
                    hook: "The nest now has twelve more."),
            chapter("chapter_5", "Pattern Problem", .saved10,
                    ["Pages of patterns. Tiny symbols everywhere.",
                     "[Name] cannot read them, but memorizes pictures.",
                     "Improvisation begins."],
                    hook: "This will be fine. Probably."),
            chapter("chapter_6", "Stitch Marker Incident", .firstNote,
                    ["Twenty stitch markers are missing.",
                     "A faint rattling sound comes from the nest.",
                     "[Name] avoids eye contact."],
                    hook: "The crafter starts keeping notes."),
            chapter("chapter_7", "Something Beautiful", .completed3,
                    ["[Name] finishes a perfect little square.",
                     "The color matches their feathers.",
                     "They add it to the nest immediately."],
                    hook: "No one gets to have this one."),
            chapter("chapter_8", "Thimble Confession", .saved25,
                    ["A thimble appears on the table, then buttons, then a tiny star marker.",
                     "This is as close to an apology as crows get.",
                     "The crafter labels a jar: [Name]'s Corner."],
                    hook: "Trust is rebuilding."),
            chapter("chapter_9", "Nest Revised", .streak14,
                    ["The nest now holds finished projects and zero stolen needles.",
                     "[Name] did not expect to feel proud.",
                     "Cable lessons are next."],
                    hook: "The cable needle is very shiny."),
            chapter("chapter_10", "One More Thing", .seasonal,
                    ["A new yarn color appears on the table.",
                     "[Name] reaches out one wing very slowly.",
                     "Old habits are watching."],
                    hook: "Season 2 begins.")
        ]
    }

    func evaluateUnlocks(
        hasSeenOnboarding: Bool,
        streak: Int,
        savedCount: Int,
        completedCount: Int,
        hasAnyNote: Bool
    ) {
        let month = Calendar.current.component(.month, from: Date())
        let seasonalWindow = [3, 6, 9, 12].contains(month)
        tryUnlock(trigger: .onboardingReturn, condition: hasSeenOnboarding)
        tryUnlock(trigger: .streak3, condition: streak >= 3)
        tryUnlock(trigger: .firstPatternComplete, condition: completedCount >= 1)
        tryUnlock(trigger: .streak7, condition: streak >= 7)
        tryUnlock(trigger: .saved10, condition: savedCount >= 10)
        tryUnlock(trigger: .firstNote, condition: hasAnyNote)
        tryUnlock(trigger: .completed3, condition: completedCount >= 3)
        tryUnlock(trigger: .saved25, condition: savedCount >= 25)
        tryUnlock(trigger: .streak14, condition: streak >= 14)
        tryUnlock(trigger: .seasonal, condition: seasonalWindow)
    }

    func chapter(for id: String?) -> MascotStoryChapter? {
        guard let id else { return nil }
        return chapters.first(where: { $0.id == id })
    }

    func openPendingChapter() {
        guard let id = progress.pendingId else { return }
        showingChapterId = id
        showUnlockBanner = false
    }

    func markViewed(id: String) {
        progress.viewedIds.insert(id)
        if progress.pendingId == id {
            progress.pendingId = nil
        }
        persist()
    }

    #if DEBUG
    func forceUnlock(chapterId: String) {
        guard let chapter = chapters.first(where: { $0.id == chapterId }) else { return }
        progress.unlockedIds.insert(chapter.id)
        progress.pendingId = chapter.id
        showUnlockBanner = true
        persist()
    }

    func resetProgressForDebug() {
        progress = MascotStoryProgress()
        showingChapterId = nil
        showUnlockBanner = false
        persist()
    }
    #endif

    private func tryUnlock(trigger: MascotStoryTrigger, condition: Bool) {
        guard condition else { return }
        guard let chapter = chapters.first(where: { $0.trigger == trigger }) else { return }
        guard !progress.unlockedIds.contains(chapter.id) else { return }
        progress.unlockedIds.insert(chapter.id)
        progress.pendingId = chapter.id
        showUnlockBanner = true
        persist()
    }

    private func chapter(_ id: String, _ title: String, _ trigger: MascotStoryTrigger, _ lines: [String], hook: String) -> MascotStoryChapter {
        MascotStoryChapter(id: id, title: title, trigger: trigger, lines: lines, hook: hook)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(progress) {
            defaults.set(data, forKey: Self.progressKey)
        }
    }
}

