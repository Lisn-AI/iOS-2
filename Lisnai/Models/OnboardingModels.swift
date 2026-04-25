import Foundation
import EventKit

/// User domain selection for personalization
enum UserDomain: String, CaseIterable, Codable {
    case sales = "Sales"
    case projectManager = "Project Manager"
    case healthcare = "Healthcare"
    case student = "Student"
    case entrepreneur = "Entrepreneur"
    case customerSuccess = "Customer Success"
    case creator = "Content Creator"

    /// Display title for domain selection cards
    var title: String {
        switch self {
        case .sales: return "Remembering client details"
        case .projectManager: return "Tracking team commitments"
        case .healthcare: return "Patient care preferences"
        case .student: return "Class notes & assignments"
        case .entrepreneur: return "Strategic business insights"
        case .customerSuccess: return "Customer relationships"
        case .creator: return "Interview highlights"
        }
    }

    /// SF Symbol icon name for each domain
    var iconName: String {
        switch self {
        case .sales: return "briefcase.fill"
        case .projectManager: return "checklist"
        case .healthcare: return "cross.case.fill"
        case .student: return "book.fill"
        case .entrepreneur: return "chart.line.uptrend.xyaxis"
        case .customerSuccess: return "person.2.fill"
        case .creator: return "mic.fill"
        }
    }

    /// Subtitle for domain selection cards
    var subtitle: String {
        switch self {
        case .sales: return "Sales professionals"
        case .projectManager: return "Project managers"
        case .healthcare: return "Healthcare/Caregivers"
        case .student: return "Students"
        case .entrepreneur: return "Entrepreneurs"
        case .customerSuccess: return "Customer success teams"
        case .creator: return "Content creators"
        }
    }
}

/// Demo result structure for "Show Me What You Got" screen
struct DemoResult: Codable {
    let paragraph: String
    let insights: [Insight]
    let actions: [Action]
    let summaryText: String

    struct Insight: Codable, Identifiable {
        let id = UUID()
        let text: String
        let isCritical: Bool

        enum CodingKeys: String, CodingKey {
            case text, isCritical
        }
    }

    struct Action: Codable, Identifiable {
        let id = UUID()
        let text: String

        enum CodingKeys: String, CodingKey {
            case text
        }
    }
}

/// Demo paragraph bank - domain-specific examples
let demoParagraphs: [UserDomain: String] = [
    .sales: "Sarah mentioned she's struggling with Q1 budgets. She loved our Enterprise plan last year but needs approval from Mike, her CFO. Follow up next Tuesday after their board meeting.",
    .projectManager: "Alex committed to finishing the API integration by Friday. The design team needs staging access by Wednesday for QA. Database migration is blocked until DevOps approves the new schema.",
    .healthcare: "Mrs. Johnson prefers her medication at 8am with orange juice, not water. She's allergic to penicillin. Her daughter visits Thursdays and wants updates on physical therapy progress.",
    .student: "Professor Chen assigned the machine learning paper due March 15th. Study group meets Tuesdays in the library. The midterm covers chapters 4 through 9, focus on neural networks.",
    .entrepreneur: "The investor call went well. They're interested but want to see 20% MRR growth before Series A. Our biggest competitor just raised 10M. Users keep requesting API access.",
    .customerSuccess: "David from Acme Corp is frustrated with onboarding delays. He mentioned they're evaluating competitors. His renewal is in 60 days. Offered to be a case study if we fix the issue.",
    .creator: "The guest said her viral tweet strategy is posting at 6am EST on Wednesdays. She uses a 3-part hook formula: question, stat, call-to-action. Her podcast launched after hitting 10K followers."
]

/// Demo results - domain-specific insights and actions
let demoResults: [UserDomain: DemoResult] = [
    .sales: DemoResult(
        paragraph: demoParagraphs[.sales]!,
        insights: [
            DemoResult.Insight(text: "Client: Sarah (Budget concerns, Enterprise interest)", isCritical: false),
            DemoResult.Insight(text: "Stakeholder: Mike (CFO, decision maker)", isCritical: false),
            DemoResult.Insight(text: "Timing: Board meeting Tuesday", isCritical: true)
        ],
        actions: [
            DemoResult.Action(text: "Schedule follow-up call for Tuesday 2pm"),
            DemoResult.Action(text: "Prepare budget ROI deck for CFO review")
        ],
        summaryText: "2 insights + 2 actions"
    ),
    .projectManager: DemoResult(
        paragraph: demoParagraphs[.projectManager]!,
        insights: [
            DemoResult.Insight(text: "Alex: API integration (Due Friday)", isCritical: true),
            DemoResult.Insight(text: "Design team: Staging access needed (Wednesday)", isCritical: true)
        ],
        actions: [
            DemoResult.Action(text: "Request DevOps schema approval (High priority)"),
            DemoResult.Action(text: "Set up staging environment by Tuesday")
        ],
        summaryText: "2 commitments + 2 actions"
    ),
    .healthcare: DemoResult(
        paragraph: demoParagraphs[.healthcare]!,
        insights: [
            DemoResult.Insight(text: "Preference: 8am medication with orange juice", isCritical: false),
            DemoResult.Insight(text: "⚠️ CRITICAL: Penicillin allergy", isCritical: true),
            DemoResult.Insight(text: "Family: Daughter visits Thursdays", isCritical: false)
        ],
        actions: [
            DemoResult.Action(text: "Update medication schedule to 8am + OJ"),
            DemoResult.Action(text: "Prepare PT progress report for Thursday visit")
        ],
        summaryText: "3 insights (1 critical) + 2 actions"
    ),
    .student: DemoResult(
        paragraph: demoParagraphs[.student]!,
        insights: [
            DemoResult.Insight(text: "ML paper due March 15th", isCritical: true),
            DemoResult.Insight(text: "Midterm: Chapters 4-9 (Neural networks focus)", isCritical: true)
        ],
        actions: [
            DemoResult.Action(text: "Add study group to calendar (Tuesdays, library)"),
            DemoResult.Action(text: "Start ML paper outline this weekend")
        ],
        summaryText: "2 commitments + 2 actions"
    ),
    .entrepreneur: DemoResult(
        paragraph: demoParagraphs[.entrepreneur]!,
        insights: [
            DemoResult.Insight(text: "Investor requirement: 20% MRR growth for Series A", isCritical: true),
            DemoResult.Insight(text: "Market: Competitor raised $10M", isCritical: false),
            DemoResult.Insight(text: "User demand: API access feature requests", isCritical: false)
        ],
        actions: [
            DemoResult.Action(text: "Review growth strategy to hit 20% MRR"),
            DemoResult.Action(text: "Evaluate API roadmap priority (high demand)")
        ],
        summaryText: "3 insights + 2 actions"
    ),
    .customerSuccess: DemoResult(
        paragraph: demoParagraphs[.customerSuccess]!,
        insights: [
            DemoResult.Insight(text: "⚠️ At-risk: David/Acme Corp (evaluating competitors)", isCritical: true),
            DemoResult.Insight(text: "Renewal: 60 days remaining", isCritical: true),
            DemoResult.Insight(text: "Opportunity: Case study offer", isCritical: false)
        ],
        actions: [
            DemoResult.Action(text: "Escalate onboarding issue (Highest priority)"),
            DemoResult.Action(text: "Schedule renewal discussion within 2 weeks")
        ],
        summaryText: "3 insights (2 critical) + 2 actions"
    ),
    .creator: DemoResult(
        paragraph: demoParagraphs[.creator]!,
        insights: [
            DemoResult.Insight(text: "Timing: Wednesdays, 6am EST optimal", isCritical: false),
            DemoResult.Insight(text: "Hook formula: Question → Stat → CTA (3-part)", isCritical: false),
            DemoResult.Insight(text: "Milestone: 10K followers before podcast launch", isCritical: false)
        ],
        actions: [
            DemoResult.Action(text: "Try 3-part hook formula in next post"),
            DemoResult.Action(text: "Schedule Wednesday 6am content calendar block")
        ],
        summaryText: "3 insights + 2 actions"
    )
]

// MARK: - Executable Demo Actions

/// An action that can be executed via EventKit during onboarding demo
struct DemoExecutableAction: Identifiable {
    let id = UUID()
    let text: String
    let icon: String
    let skill: String
    let tool: String
    let params: [String: AnyCodable]

    func toPendingAction() -> PendingAction {
        PendingAction(
            id: id.uuidString,
            skill: skill,
            tool: tool,
            type: nil,
            params: params,
            status: "pending",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

// MARK: - Date Helpers

private func nextWeekday(_ weekday: Int, hour: Int, minute: Int = 0) -> String {
    let cal = Calendar.current
    var components = DateComponents()
    components.weekday = weekday
    components.hour = hour
    components.minute = minute
    if let date = cal.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) {
        return ISO8601DateFormatter().string(from: date)
    }
    return ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400))
}

private func tomorrow(hour: Int, minute: Int = 0) -> String {
    let cal = Calendar.current
    let tom = cal.date(byAdding: .day, value: 1, to: Date())!
    let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: tom)!
    return ISO8601DateFormatter().string(from: date)
}

private func daysFromNow(_ days: Int, hour: Int = 9) -> String {
    let cal = Calendar.current
    let future = cal.date(byAdding: .day, value: days, to: Date())!
    let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: future)!
    return ISO8601DateFormatter().string(from: date)
}

/// Domain-specific executable actions (2 per domain)
let demoExecutableActions: [UserDomain: [DemoExecutableAction]] = [
    .sales: [
        DemoExecutableAction(
            text: "Follow-up with Sarah",
            icon: "calendar",
            skill: "apple-calendar",
            tool: "create_event",
            params: [
                "title": AnyCodable("Follow-up call with Sarah"),
                "startDate": AnyCodable(nextWeekday(3, hour: 14)), // Tuesday 2pm
                "endDate": AnyCodable(nextWeekday(3, hour: 15)),
                "notes": AnyCodable("Discuss Q1 budget concerns and Enterprise plan renewal. Get Mike (CFO) buy-in.")
            ]
        ),
        DemoExecutableAction(
            text: "Prepare ROI deck",
            icon: "bell.fill",
            skill: "apple-reminders",
            tool: "create_reminder",
            params: [
                "title": AnyCodable("Prepare budget ROI deck for CFO review"),
                "dueDate": AnyCodable(nextWeekday(2, hour: 9)), // Monday morning
                "priority": AnyCodable(1) // high
            ]
        )
    ],
    .projectManager: [
        DemoExecutableAction(
            text: "Request schema approval",
            icon: "bell.fill",
            skill: "apple-reminders",
            tool: "create_reminder",
            params: [
                "title": AnyCodable("Request DevOps schema approval — blocks DB migration"),
                "dueDate": AnyCodable(tomorrow(hour: 9)),
                "priority": AnyCodable(1)
            ]
        ),
        DemoExecutableAction(
            text: "Staging env setup",
            icon: "calendar",
            skill: "apple-calendar",
            tool: "create_event",
            params: [
                "title": AnyCodable("Set up staging environment for QA"),
                "startDate": AnyCodable(nextWeekday(4, hour: 10)), // Wednesday
                "endDate": AnyCodable(nextWeekday(4, hour: 11)),
                "notes": AnyCodable("Design team needs staging access for QA review")
            ]
        )
    ],
    .healthcare: [
        DemoExecutableAction(
            text: "Medication schedule",
            icon: "bell.fill",
            skill: "apple-reminders",
            tool: "create_reminder",
            params: [
                "title": AnyCodable("Mrs. Johnson medication — 8am with orange juice"),
                "dueDate": AnyCodable(tomorrow(hour: 8)),
                "priority": AnyCodable(1)
            ]
        ),
        DemoExecutableAction(
            text: "PT progress report",
            icon: "bell.fill",
            skill: "apple-reminders",
            tool: "create_reminder",
            params: [
                "title": AnyCodable("Prepare PT progress report for daughter's visit"),
                "dueDate": AnyCodable(nextWeekday(5, hour: 9)), // Thursday
                "priority": AnyCodable(5)
            ]
        )
    ],
    .student: [
        DemoExecutableAction(
            text: "Study group",
            icon: "calendar",
            skill: "apple-calendar",
            tool: "create_event",
            params: [
                "title": AnyCodable("Study Group"),
                "startDate": AnyCodable(nextWeekday(3, hour: 16)), // Tuesday 4pm
                "endDate": AnyCodable(nextWeekday(3, hour: 18)),
                "location": AnyCodable("Library"),
                "notes": AnyCodable("Midterm prep — chapters 4-9, focus on neural networks")
            ]
        ),
        DemoExecutableAction(
            text: "Start ML paper outline",
            icon: "bell.fill",
            skill: "apple-reminders",
            tool: "create_reminder",
            params: [
                "title": AnyCodable("Start ML paper outline — due March 15th"),
                "dueDate": AnyCodable(daysFromNow(2, hour: 10)), // this weekend-ish
                "priority": AnyCodable(1)
            ]
        )
    ],
    .entrepreneur: [
        DemoExecutableAction(
            text: "Review growth strategy",
            icon: "bell.fill",
            skill: "apple-reminders",
            tool: "create_reminder",
            params: [
                "title": AnyCodable("Review growth strategy — need 20% MRR for Series A"),
                "dueDate": AnyCodable(tomorrow(hour: 9)),
                "priority": AnyCodable(1)
            ]
        ),
        DemoExecutableAction(
            text: "Evaluate API roadmap",
            icon: "bell.fill",
            skill: "apple-reminders",
            tool: "create_reminder",
            params: [
                "title": AnyCodable("Evaluate API access roadmap — high user demand"),
                "dueDate": AnyCodable(daysFromNow(3, hour: 10)),
                "priority": AnyCodable(5)
            ]
        )
    ],
    .customerSuccess: [
        DemoExecutableAction(
            text: "Escalate Acme onboarding",
            icon: "bell.fill",
            skill: "apple-reminders",
            tool: "create_reminder",
            params: [
                "title": AnyCodable("URGENT: Escalate Acme Corp onboarding issue — David evaluating competitors"),
                "dueDate": AnyCodable(tomorrow(hour: 9)),
                "priority": AnyCodable(1)
            ]
        ),
        DemoExecutableAction(
            text: "Renewal discussion",
            icon: "calendar",
            skill: "apple-calendar",
            tool: "create_event",
            params: [
                "title": AnyCodable("Acme Corp renewal discussion"),
                "startDate": AnyCodable(daysFromNow(14, hour: 14)),
                "endDate": AnyCodable(daysFromNow(14, hour: 15)),
                "notes": AnyCodable("Renewal in 60 days. David offered case study if onboarding fixed.")
            ]
        )
    ],
    .creator: [
        DemoExecutableAction(
            text: "Try 3-part hook formula",
            icon: "bell.fill",
            skill: "apple-reminders",
            tool: "create_reminder",
            params: [
                "title": AnyCodable("Try 3-part hook formula: question → stat → CTA"),
                "dueDate": AnyCodable(tomorrow(hour: 10)),
                "priority": AnyCodable(5)
            ]
        ),
        DemoExecutableAction(
            text: "Content block",
            icon: "calendar",
            skill: "apple-calendar",
            tool: "create_event",
            params: [
                "title": AnyCodable("Content Creation Block"),
                "startDate": AnyCodable(nextWeekday(4, hour: 6)), // Wednesday 6am
                "endDate": AnyCodable(nextWeekday(4, hour: 8)),
                "notes": AnyCodable("Post at 6am EST Wednesdays for optimal reach")
            ]
        )
    ]
]
