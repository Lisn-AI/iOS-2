import Foundation

/// Growth-focused onboarding survey. See DESIGN.md Part 5 + Part 6b.
///
/// Three questions:
///   Q1 (single-select): How did you find Lisn?
///   Q2 (multi-select):  What do you want Lisn to remember?
///   Q3 (multi-select, optional): What were you using before?

enum AcquisitionSource: String, CaseIterable, Identifiable {
    case tiktok, x, instagram, friend, search, productHunt = "product_hunt", appStore = "app_store", other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiktok: return "TikTok"
        case .x: return "X / Twitter"
        case .instagram: return "Instagram"
        case .friend: return "A friend"
        case .search: return "Google search"
        case .productHunt: return "Product Hunt"
        case .appStore: return "App Store browsing"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .tiktok: return "music.note"
        case .x: return "bird"
        case .instagram: return "camera"
        case .friend: return "person.2.fill"
        case .search: return "magnifyingglass"
        case .productHunt: return "flame.fill"
        case .appStore: return "app.fill"
        case .other: return "ellipsis"
        }
    }
}

enum UseCaseIntent: String, CaseIterable, Identifiable {
    case workMeetings = "work_meetings"
    case personalChats = "personal_chats"
    case voiceNotes = "voice_notes"
    case family
    case calls
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workMeetings: return "Work meetings"
        case .personalChats: return "Personal conversations"
        case .voiceNotes: return "Voice notes & ideas"
        case .family: return "Time with family"
        case .calls: return "Phone calls"
        case .other: return "Something else"
        }
    }

    var subtitle: String {
        switch self {
        case .workMeetings: return "Standups, 1:1s, client calls"
        case .personalChats: return "Friends, coffee chats, deep talks"
        case .voiceNotes: return "Thoughts while walking, brainstorms"
        case .family: return "Conversations you don't want to forget"
        case .calls: return "What was said, who promised what"
        case .other: return "Tell us in a review later"
        }
    }

    var icon: String {
        switch self {
        case .workMeetings: return "briefcase.fill"
        case .personalChats: return "bubble.left.and.bubble.right.fill"
        case .voiceNotes: return "mic.fill"
        case .family: return "heart.fill"
        case .calls: return "phone.fill"
        case .other: return "ellipsis"
        }
    }
}

enum PriorTool: String, CaseIterable, Identifiable {
    case notion, appleVoiceMemos = "apple_voice_memos", otter, granola, dayOne = "day_one", nothing, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notion: return "Notion"
        case .appleVoiceMemos: return "Apple Voice Memos"
        case .otter: return "Otter.ai"
        case .granola: return "Granola"
        case .dayOne: return "Day One"
        case .nothing: return "Nothing — I lose it all"
        case .other: return "Something else"
        }
    }
}

/// Aggregated survey response — what gets sent to backend + Mixpanel
struct SurveyResponse {
    var acquisitionSource: AcquisitionSource?
    var useCaseIntents: Set<UseCaseIntent> = []
    var priorTools: Set<PriorTool> = []

    /// Q1 + Q2 required; Q3 optional
    var isComplete: Bool {
        acquisitionSource != nil && !useCaseIntents.isEmpty
    }

    /// Shape sent to POST /api/users/me/survey
    func backendPayload() -> [String: Any] {
        var body: [String: Any] = [
            "use_case_intents": useCaseIntents.map { $0.rawValue },
            "onboarding_version": "v1",
        ]
        if let source = acquisitionSource {
            body["acquisition_source"] = source.rawValue
        }
        if !priorTools.isEmpty {
            body["prior_tool"] = priorTools.map { $0.rawValue }
        }
        return body
    }
}
