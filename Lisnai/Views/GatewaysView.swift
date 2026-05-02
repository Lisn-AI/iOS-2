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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero section
                    heroSection
                        .padding(.bottom, LisnSpacing.xl)

                    // API Key
                    apiKeySection
                        .padding(.horizontal, LisnSpacing.md)
                        .padding(.bottom, LisnSpacing.lg)

                    // Integrations
                    VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                        Text("INTEGRATIONS")
                            .lisnSectionHeader()
                            .padding(.horizontal, LisnSpacing.md + LisnSpacing.xxs)

                        gatewayRow(
                            id: "claude",
                            name: "Claude Desktop & Code",
                            subtitle: "Search memories, chat with recordings, create actions",
                            iconName: "wand.and.stars",
                            tint: Color(red: 0.55, green: 0.36, blue: 0.82),
                            steps: claudeSteps
                        )

                        gatewayRow(
                            id: "cursor",
                            name: "Cursor IDE",
                            subtitle: "Access your memory corpus while coding",
                            iconName: "cursorarrow.rays",
                            tint: Color(red: 0.22, green: 0.46, blue: 0.82),
                            steps: cursorSteps
                        )

                        gatewayRow(
                            id: "whatsapp",
                            name: "WhatsApp",
                            subtitle: "Chat with your memories on WhatsApp",
                            iconName: "ellipsis.message.fill",
                            tint: Color(red: 0.15, green: 0.68, blue: 0.38),
                            badge: "Coming Soon",
                            steps: nil
                        )
                    }
                    .padding(.bottom, LisnSpacing.xxxl)
                }
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
        VStack(spacing: LisnSpacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [LisnColors.accent.opacity(0.15), LisnColors.accent.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "network")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(LisnColors.accent)
            }

            Text("Gateways")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(LisnColors.textPrimary)

            Text("Connect your Lisn memory to\nexternal AI tools")
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, LisnSpacing.xl)
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
                // Existing key card
                HStack(spacing: LisnSpacing.sm) {
                    // Key icon
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

                        Text(key.keyPrefix + "..." )
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(LisnColors.textTertiary)
                    }

                    Spacer()

                    // Copy
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
                            .background(
                                (justCopied ? LisnColors.success : LisnColors.accent).opacity(0.1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // Revoke
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
                .lisnCardStyle()
            } else {
                // Generate key prompt
                VStack(spacing: LisnSpacing.sm) {
                    Text("You need an API key to connect external tools.")
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
                .lisnCardStyle()
            }
        }
    }

    // MARK: - Gateway Row

    private func gatewayRow(
        id: String,
        name: String,
        subtitle: String,
        iconName: String,
        tint: Color,
        badge: String? = nil,
        steps: [SetupStep]?
    ) -> some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                guard steps != nil else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expandedId = expandedId == id ? nil : id
                }
            } label: {
                HStack(spacing: LisnSpacing.sm) {
                    // Icon
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm + 2, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: LisnSpacing.xs) {
                            Text(name)
                                .font(LisnFont.labelLarge())
                                .foregroundColor(LisnColors.textPrimary)

                            if let badge {
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(LisnColors.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(LisnColors.accent.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.xs, style: .continuous))
                            }
                        }

                        Text(subtitle)
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if steps != nil {
                        Image(systemName: expandedId == id ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(LisnColors.textTertiary)
                    }
                }
                .padding(LisnSpacing.md)
            }
            .buttonStyle(.plain)

            // Expanded steps
            if expandedId == id, let steps {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .padding(.horizontal, LisnSpacing.md)

                    VStack(alignment: .leading, spacing: LisnSpacing.md) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                            stepRow(index: idx + 1, step: step)
                        }
                    }
                    .padding(LisnSpacing.md)
                    .padding(.top, LisnSpacing.xxs)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .lisnCardStyle()
        .padding(.horizontal, LisnSpacing.md)
    }

    // MARK: - Step Row

    private func stepRow(index: Int, step: SetupStep) -> some View {
        HStack(alignment: .top, spacing: LisnSpacing.sm) {
            // Step number
            Text("\(index)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(LisnColors.accent)
                .frame(width: 20, height: 20)
                .background(LisnColors.accent.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: LisnSpacing.xxs) {
                Text(step.title)
                    .font(LisnFont.labelLarge())
                    .foregroundColor(LisnColors.textPrimary)

                Text(step.detail)
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let code = step.code {
                    codeSnippet(code)
                        .padding(.top, LisnSpacing.xxs)
                }
            }
        }
    }

    // MARK: - Code Snippet

    private func codeSnippet(_ code: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Copy button
            Button {
                UIPasteboard.general.string = code
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .medium))
                    Text("Copy")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(LisnColors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(red: 0.25, green: 0.27, blue: 0.29))
                    .padding(.horizontal, LisnSpacing.sm)
                    .padding(.bottom, LisnSpacing.sm)
            }
        }
        .background(LisnColors.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
    }

    // MARK: - Setup Data

    struct SetupStep {
        let title: String
        let detail: String
        let code: String?
    }

    private var claudeSteps: [SetupStep] {
        let base = "https://backend-test-8pbt.onrender.com"
        return [
            SetupStep(title: "Copy your API key", detail: "Tap Copy above. You'll paste it in the config.", code: nil),
            SetupStep(title: "Open config file", detail: "Claude Desktop: Settings > Developer > Edit Config\nClaude Code: edit ~/.claude.json", code: nil),
            SetupStep(title: "Add the LisnAI server", detail: "Paste this into the mcpServers section:", code: """
            "lisnai": {
              "type": "http",
              "url": "\(base)/mcp",
              "headers": {
                "Authorization": "Bearer YOUR_KEY"
              }
            }
            """),
            SetupStep(title: "Restart & use", detail: "Restart the app. You'll have 4 tools: search_memories, ask_agent, get_recordings, create_action.", code: nil),
        ]
    }

    private var cursorSteps: [SetupStep] {
        let base = "https://backend-test-8pbt.onrender.com"
        return [
            SetupStep(title: "Copy your API key", detail: "Tap Copy above.", code: nil),
            SetupStep(title: "Open MCP settings", detail: "Cursor > Settings > MCP Servers > Add New.", code: nil),
            SetupStep(title: "Configure LisnAI", detail: "Add with these settings:", code: """
            "lisnai": {
              "type": "http",
              "url": "\(base)/mcp",
              "headers": {
                "Authorization": "Bearer YOUR_KEY"
              }
            }
            """),
            SetupStep(title: "Use in Cursor", detail: "Ask: \"Search my Lisn recordings about the API design\" or \"What did I discuss in my last meeting?\"", code: nil),
        ]
    }

    // MARK: - Helpers

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let rel = RelativeDateTimeFormatter()
        return rel.localizedString(for: date, relativeTo: Date())
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
