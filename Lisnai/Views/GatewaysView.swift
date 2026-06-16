import SwiftUI
import Security

/// Gateways — connect LisnAI memory to external AI tools
struct GatewaysView: View {
    @StateObject private var viewModel = GatewaysViewModel()
    @State private var expandedId: String?
    @State private var showKeyAlert = false
    @State private var generatedKey = ""
    @State private var justCopied = false
    @Environment(\.dismiss) private var dismiss

    private let mcpURL = "https://api.lisnai.com/mcp"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LisnSpacing.xl) {
                    // Hero
                    heroSection
                        .padding(.top, LisnSpacing.lg)

                    // API Key
                    apiKeySection

                    // Integrations
                    VStack(alignment: .leading, spacing: LisnSpacing.md) {
                        Text("INTEGRATIONS")
                            .lisnSectionHeader()
                            .padding(.horizontal, LisnSpacing.xxs)

                        gatewayCard(
                            id: "claude-code",
                            logo: "claude-logo",
                            name: "Claude Desktop & Code",
                            description: "Search memories, chat with recordings, create reminders — all from Claude.",
                            steps: claudeCodeSteps
                        )

                        gatewayCard(
                            id: "claude-web",
                            logo: "claude-web-logo",
                            name: "Claude Web (claude.ai)",
                            description: "Use your LisnAI memory directly in claude.ai conversations.",
                            steps: claudeWebSteps
                        )

                        gatewayCard(
                            id: "chatgpt",
                            logo: "chatgpt-logo",
                            name: "ChatGPT",
                            description: "Access your voice recordings and memory from ChatGPT.",
                            steps: chatGPTSteps
                        )

                        gatewayCard(
                            id: "cursor",
                            logo: "cursor-logo",
                            name: "Cursor IDE",
                            description: "Search your memory while coding — context from your conversations.",
                            steps: cursorSteps
                        )

                        gatewayCard(
                            id: "whatsapp",
                            logo: "whatsapp-logo",
                            name: "WhatsApp",
                            description: "Chat with your memories on WhatsApp.",
                            badge: "Coming Soon",
                            steps: nil
                        )
                    }
                }
                .padding(.horizontal, LisnSpacing.xs) // 8pt slim margins
                .padding(.bottom, LisnSpacing.xxxl)
            }
            .background(LisnColors.bgPrimary)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(LisnColors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(LisnColors.bgSecondary)
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, LisnSpacing.md)
                .padding(.top, LisnSpacing.xs)
                .padding(.bottom, LisnSpacing.xs)
            }
            .task { await viewModel.loadKeys() }
            .alert("API Key Created", isPresented: $showKeyAlert) {
                Button("Copy to Clipboard") {
                    UIPasteboard.general.string = generatedKey
                }
                Button("Done", role: .cancel) {}
            } message: {
                Text("Save this key — it won't be shown again.\n\n\(generatedKey)")
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: LisnSpacing.md) {
            // Floating overlapping brand icons (like Grok's connector banner)
            HStack(spacing: -8) {
                brandIcon("claude-logo", size: 36)
                brandIcon("chatgpt-logo", size: 36)
                brandIcon("cursor-logo", size: 36)
                brandIcon("whatsapp-logo", size: 36)
            }

            VStack(spacing: LisnSpacing.xs) {
                Text("Gateways")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(LisnColors.textPrimary)

                Text("Connect your LisnAI memory to\nexternal AI tools")
                    .font(LisnFont.bodyMedium())
                    .foregroundColor(LisnColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Brand icon with background circle and proper padding
    private func brandIcon(_ name: String, size: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .padding(size * 0.2)
            .frame(width: size, height: size)
            .background(LisnColors.bgElevated)
            .clipShape(Circle())
            .overlay(Circle().stroke(LisnColors.bgPrimary, lineWidth: 2.5))
            .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            HStack {
                Text("YOUR API KEY")
                    .lisnSectionHeader()
                Spacer()
            }
            .padding(.horizontal, LisnSpacing.xxs)

            if let key = viewModel.keys.first {
                HStack(spacing: LisnSpacing.sm) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(LisnColors.accent)
                        .frame(width: 32, height: 32)
                        .background(LisnColors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.name)
                            .font(LisnFont.labelLarge())
                            .foregroundColor(LisnColors.textPrimary)

                        Text(key.keyPrefix + "...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(LisnColors.textTertiary)
                    }

                    Spacer()

                    Button {
                        if let saved = KeychainHelper.load(key: "lisnai_api_key") {
                            UIPasteboard.general.string = saved
                            withAnimation { justCopied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { justCopied = false }
                            }
                        }
                    } label: {
                        Text(justCopied ? "Copied" : "Copy")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(justCopied ? LisnColors.success : LisnColors.accent)
                            .padding(.horizontal, LisnSpacing.sm)
                            .padding(.vertical, LisnSpacing.xxs + 2)
                            .background((justCopied ? LisnColors.success : LisnColors.accent).opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await viewModel.revokeKey(id: key.id) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(LisnColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(LisnSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lisnCardStyle()
            } else {
                VStack(spacing: LisnSpacing.sm) {
                    Text("Generate an API key to connect external tools.")
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textSecondary)

                    Button {
                        Task {
                            if let key = await viewModel.generateKey(name: "Gateway Key") {
                                generatedKey = key
                                KeychainHelper.save(key: "lisnai_api_key", value: key)
                                showKeyAlert = true
                            }
                        }
                    } label: {
                        HStack(spacing: LisnSpacing.xs) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Generate API Key")
                                .font(LisnFont.labelLarge())
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LisnSpacing.sm)
                        .background(LisnColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                    }
                    .disabled(viewModel.isGenerating)
                }
                .padding(LisnSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lisnCardStyle()
            }
        }
    }

    // MARK: - Gateway Card

    private func gatewayCard(
        id: String,
        logo: String,
        name: String,
        description: String,
        badge: String? = nil,
        steps: [SetupStep]?
    ) -> some View {
        let isExpanded = expandedId == id

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                guard steps != nil else { return }
                LisnHaptics.light()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expandedId = isExpanded ? nil : id
                }
            } label: {
                HStack(alignment: .center, spacing: LisnSpacing.md) {
                    // Logo in brand-tinted gradient container
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        LisnColors.accent.opacity(0.14),
                                        LisnColors.accent.opacity(0.04),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(LisnColors.accent.opacity(0.12), lineWidth: 0.5)
                            )

                        Image(logo)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: LisnSpacing.xs) {
                            Text(name)
                                .font(LisnFont.titleSmall())
                                .foregroundColor(LisnColors.textPrimary)

                            if let badge {
                                Text(badge.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.6)
                                    .foregroundColor(LisnColors.warning)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(LisnColors.warning.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        Text(description)
                            .font(LisnFont.bodySmall())
                            .foregroundColor(LisnColors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: LisnSpacing.xs)

                    if steps != nil {
                        ZStack {
                            Circle()
                                .fill(LisnColors.bgSecondary)
                                .frame(width: 28, height: 28)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(LisnColors.textSecondary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                    }
                }
                .padding(.horizontal, LisnSpacing.lg)
                .padding(.vertical, LisnSpacing.md + 2)
            }
            .buttonStyle(.plain)

            // Expanded steps
            if isExpanded, let steps {
                // Brand-tinted hairline divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                LisnColors.accent.opacity(0.18),
                                Color.clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .padding(.horizontal, LisnSpacing.lg)

                VStack(alignment: .leading, spacing: LisnSpacing.xl) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                        stepRow(index: idx + 1, step: step)
                    }
                }
                .padding(.horizontal, LisnSpacing.lg)
                .padding(.vertical, LisnSpacing.lg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: LisnRadius.xl, style: .continuous)
                    .fill(LisnColors.bgElevated)

                // Subtle warm wash — top-leading amber → transparent
                LinearGradient(
                    stops: [
                        .init(color: LisnColors.accent.opacity(0.04), location: 0),
                        .init(color: Color.clear, location: 0.65),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.xl, style: .continuous))

                // Hairline border
                RoundedRectangle(cornerRadius: LisnRadius.xl, style: .continuous)
                    .strokeBorder(LisnColors.border.opacity(0.6), lineWidth: 0.5)
            }
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
        .shadow(color: LisnColors.accent.opacity(isExpanded ? 0.08 : 0), radius: 16, x: 0, y: 6)
    }

    // MARK: - Step Row

    private func stepRow(index: Int, step: SetupStep) -> some View {
        HStack(alignment: .top, spacing: LisnSpacing.sm) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [LisnColors.orbLight, LisnColors.orbDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .shadow(color: LisnColors.accent.opacity(0.35), radius: 4, x: 0, y: 2)

                Text("\(index)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: LisnSpacing.xs) {
                Text(step.title)
                    .font(LisnFont.labelLarge())
                    .foregroundColor(LisnColors.textPrimary)

                Text(step.detail)
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)

                if let code = step.code {
                    codeSnippet(code)
                        .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Code Snippet

    private func codeSnippet(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: LisnSpacing.xs) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(LisnColors.textTertiary)

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                    LisnHaptics.light()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Copy")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(LisnColors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LisnColors.accent.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, LisnSpacing.sm)
            .padding(.top, LisnSpacing.xs)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(red: 0.18, green: 0.20, blue: 0.22))
                    .padding(.horizontal, LisnSpacing.sm)
                    .padding(.top, LisnSpacing.xxs)
                    .padding(.bottom, LisnSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LisnColors.bgPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(LisnColors.border.opacity(0.5), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Setup Data

    struct SetupStep {
        let title: String
        let detail: String
        let code: String?
    }

    private var claudeCodeSteps: [SetupStep] {
        [
            SetupStep(title: "Copy your API key", detail: "Tap Copy above. You'll paste it in the config.", code: nil),
            SetupStep(title: "Open config file", detail: "Claude Desktop: Settings > Developer > Edit Config\nClaude Code: edit ~/.claude.json", code: nil),
            SetupStep(title: "Add LisnAI server", detail: "Paste this into the mcpServers section:", code: """
            "lisnai": {
              "type": "http",
              "url": "\(mcpURL)",
              "headers": {
                "Authorization": "Bearer YOUR_KEY"
              }
            }
            """),
            SetupStep(title: "Restart & use", detail: "Restart the app. You'll get 4 tools: search_memories, ask_agent, get_recordings, create_action.", code: nil),
        ]
    }

    private var claudeWebSteps: [SetupStep] {
        [
            SetupStep(title: "Open Connectors", detail: "Go to claude.ai > click your profile > Settings > Connectors.", code: nil),
            SetupStep(title: "Add custom connector", detail: "Click 'Add custom connector' and enter this URL:", code: mcpURL),
            SetupStep(title: "Sign in with Google", detail: "Claude will open a sign-in page. Authenticate with your LisnAI Google account. No API key needed — OAuth handles it.", code: nil),
            SetupStep(title: "Use in conversations", detail: "Start a new chat. Claude can now search your memories, review recordings, and create actions on your iPhone.", code: nil),
        ]
    }

    private var chatGPTSteps: [SetupStep] {
        [
            SetupStep(title: "Enable Developer Mode", detail: "In ChatGPT, go to Settings > Apps > Advanced settings > turn on Developer mode.", code: nil),
            SetupStep(title: "Create an app", detail: "Click Create app. Enter this URL:", code: mcpURL),
            SetupStep(title: "Authenticate", detail: "Select OAuth authentication. ChatGPT will discover the OAuth settings automatically. Sign in with your Google account when prompted.", code: nil),
            SetupStep(title: "Use in ChatGPT", detail: "Open a new chat, click + > select LisnAI. Ask ChatGPT to search your memories or create actions.", code: nil),
        ]
    }

    private var cursorSteps: [SetupStep] {
        [
            SetupStep(title: "Copy your API key", detail: "Tap Copy above.", code: nil),
            SetupStep(title: "Open MCP settings", detail: "Cursor > Settings > MCP Servers > Add New.", code: nil),
            SetupStep(title: "Configure LisnAI", detail: "Add with these settings:", code: """
            "lisnai": {
              "type": "http",
              "url": "\(mcpURL)",
              "headers": {
                "Authorization": "Bearer YOUR_KEY"
              }
            }
            """),
            SetupStep(title: "Use in Cursor", detail: "Ask: \"Search my Lisn recordings about the API design\" or \"What did I discuss in my last meeting?\"", code: nil),
        ]
    }
}

// MARK: - View Model

@MainActor
class GatewaysViewModel: ObservableObject {
    @Published var keys: [ApiKeyListItem] = []
    @Published var isGenerating = false

    func loadKeys() async {
        do {
            let response = try await APIService.shared.getApiKeys()
            keys = response.keys
        } catch {
            print("[Gateways] Failed to load keys: \(error)")
        }
    }

    func generateKey(name: String) async -> String? {
        isGenerating = true
        defer { isGenerating = false }
        do {
            let response = try await APIService.shared.generateApiKey(name: name)
            await loadKeys()
            return response.key
        } catch {
            print("[Gateways] Failed to generate key: \(error)")
            return nil
        }
    }

    func revokeKey(id: String) async {
        do {
            _ = try await APIService.shared.revokeApiKey(keyId: id)
            keys.removeAll { $0.id == id }
            KeychainHelper.delete(key: "lisnai_api_key")
        } catch {
            print("[Gateways] Failed to revoke key: \(error)")
        }
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
