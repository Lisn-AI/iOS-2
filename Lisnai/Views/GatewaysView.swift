import SwiftUI
import Security

/// Gateways page — connect LisnAI memory to external AI tools
struct GatewaysView: View {
    @StateObject private var viewModel = GatewaysViewModel()
    @State private var expandedIntegration: String?
    @State private var showKeyAlert = false
    @State private var generatedKey = ""
    @State private var copiedKey = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LisnSpacing.lg) {
                    // Header
                    VStack(spacing: LisnSpacing.xs) {
                        Text("Connect your Lisn memory to external AI tools")
                            .font(LisnFont.bodyMedium())
                            .foregroundColor(LisnColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, LisnSpacing.sm)

                    // API Key Section
                    apiKeySection

                    // Integration Cards
                    integrationCard(
                        id: "claude",
                        icon: "sparkles",
                        iconColor: Color.purple,
                        name: "Claude Desktop",
                        description: "Search your memories and chat with your recordings from Claude Desktop or Claude Code",
                        status: .available,
                        steps: claudeSteps
                    )

                    integrationCard(
                        id: "cursor",
                        icon: "chevron.left.forwardslash.chevron.right",
                        iconColor: Color.blue,
                        name: "Cursor IDE",
                        description: "Access your recordings and memory while coding — context from your conversations",
                        status: .available,
                        steps: cursorSteps
                    )

                    integrationCard(
                        id: "whatsapp",
                        icon: "message.fill",
                        iconColor: Color.green,
                        name: "WhatsApp",
                        description: "Chat with your memories directly on WhatsApp",
                        status: .comingSoon,
                        steps: []
                    )
                }
                .padding(.horizontal, LisnSpacing.md)
                .padding(.bottom, 40)
            }
            .background(LisnColors.bgPrimary)
            .navigationTitle("Gateways")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await viewModel.loadKeys()
            }
            .alert("API Key Generated", isPresented: $showKeyAlert) {
                Button("Copy Key") {
                    UIPasteboard.general.string = generatedKey
                    copiedKey = true
                }
                Button("Done", role: .cancel) { }
            } message: {
                Text("Your API key:\n\n\(generatedKey)\n\nCopy it now — it won't be shown again.")
            }
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            Label("API Key", systemImage: "key.fill")
                .font(LisnFont.titleSmall())
                .foregroundColor(LisnColors.textPrimary)

            if viewModel.keys.isEmpty {
                // No keys yet
                VStack(spacing: LisnSpacing.sm) {
                    Text("Generate an API key to connect external tools to your Lisn memory.")
                        .font(LisnFont.bodyMedium())
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
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Generate API Key")
                        }
                        .font(LisnFont.labelLarge())
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
            } else {
                // Show existing keys
                ForEach(viewModel.keys) { key in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.name)
                                .font(LisnFont.labelLarge())
                                .foregroundColor(LisnColors.textPrimary)
                            Text(key.keyPrefix + "...")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(LisnColors.textSecondary)
                            if let lastUsed = key.lastUsedAt {
                                Text("Last used: \(formatDate(lastUsed))")
                                    .font(LisnFont.caption())
                                    .foregroundColor(LisnColors.textTertiary)
                            }
                        }

                        Spacer()

                        // Copy from Keychain
                        Button {
                            if let saved = KeychainHelper.load(key: "lisnai_api_key") {
                                UIPasteboard.general.string = saved
                                copiedKey = true
                            }
                        } label: {
                            Image(systemName: copiedKey ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(copiedKey ? LisnColors.success : LisnColors.accent)
                        }
                        .buttonStyle(.plain)

                        // Revoke
                        Button {
                            Task { await viewModel.revokeKey(id: key.id) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(LisnColors.error)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(LisnSpacing.md)
                    .lisnCardStyle()
                }
            }
        }
    }

    // MARK: - Integration Card

    enum IntegrationStatus {
        case available
        case comingSoon
    }

    private func integrationCard(
        id: String,
        icon: String,
        iconColor: Color,
        name: String,
        description: String,
        status: IntegrationStatus,
        steps: [SetupStep]
    ) -> some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            // Card header
            HStack(spacing: LisnSpacing.sm) {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(iconColor)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(name)
                            .font(LisnFont.titleSmall())
                            .foregroundColor(LisnColors.textPrimary)

                        if status == .comingSoon {
                            Text("Coming Soon")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(LisnColors.warning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(LisnColors.warning.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text(description)
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if status == .available {
                    Image(systemName: expandedIntegration == id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(LisnColors.textTertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard status == .available else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expandedIntegration = expandedIntegration == id ? nil : id
                }
            }

            // Expanded setup guide
            if expandedIntegration == id && status == .available {
                Divider()
                    .padding(.vertical, LisnSpacing.xs)

                VStack(alignment: .leading, spacing: LisnSpacing.md) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: LisnSpacing.sm) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(LisnColors.accent)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: LisnSpacing.xs) {
                                Text(step.title)
                                    .font(LisnFont.labelLarge())
                                    .foregroundColor(LisnColors.textPrimary)

                                Text(step.detail)
                                    .font(LisnFont.caption())
                                    .foregroundColor(LisnColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let code = step.code {
                                    codeBlock(code)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(LisnSpacing.md)
        .lisnCardStyle()
    }

    // MARK: - Code Block

    private func codeBlock(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(red: 0.18, green: 0.20, blue: 0.21))
                .padding(LisnSpacing.sm)
        }
        .background(Color(red: 0.96, green: 0.94, blue: 0.91))
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                UIPasteboard.general.string = code
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(LisnColors.textTertiary)
                    .padding(6)
            }
        }
    }

    // MARK: - Setup Steps Data

    struct SetupStep {
        let title: String
        let detail: String
        let code: String?
    }

    private var claudeSteps: [SetupStep] {
        let baseURL = "https://backend-test-8pbt.onrender.com"
        return [
            SetupStep(
                title: "Generate an API Key",
                detail: "Tap 'Generate API Key' above if you haven't already. Copy the key.",
                code: nil
            ),
            SetupStep(
                title: "Open Claude Desktop Settings",
                detail: "Go to Settings > Developer > Edit Config, or open the file directly:",
                code: "~/Library/Application Support/Claude/claude_desktop_config.json"
            ),
            SetupStep(
                title: "Add LisnAI as an MCP Server",
                detail: "Paste this JSON into the config file. Replace YOUR_API_KEY with your key:",
                code: """
                {
                  "mcpServers": {
                    "lisnai": {
                      "type": "http",
                      "url": "\(baseURL)/mcp",
                      "headers": {
                        "Authorization": "Bearer YOUR_API_KEY"
                      }
                    }
                  }
                }
                """
            ),
            SetupStep(
                title: "Restart Claude Desktop",
                detail: "Quit and reopen Claude Desktop. You should see LisnAI tools available: search_memories, chat, get_recordings, create_action.",
                code: nil
            ),
        ]
    }

    private var cursorSteps: [SetupStep] {
        let baseURL = "https://backend-test-8pbt.onrender.com"
        return [
            SetupStep(
                title: "Generate an API Key",
                detail: "Tap 'Generate API Key' above if you haven't already. Copy the key.",
                code: nil
            ),
            SetupStep(
                title: "Open Cursor Settings",
                detail: "In Cursor, go to Settings > MCP Servers > Add Server.",
                code: nil
            ),
            SetupStep(
                title: "Configure the MCP Server",
                detail: "Add LisnAI with these settings. Replace YOUR_API_KEY:",
                code: """
                {
                  "mcpServers": {
                    "lisnai": {
                      "url": "\(baseURL)/mcp",
                      "headers": {
                        "Authorization": "Bearer YOUR_API_KEY"
                      }
                    }
                  }
                }
                """
            ),
            SetupStep(
                title: "Use in Cursor",
                detail: "Ask Cursor things like: 'Search my Lisn recordings about the API design discussion' or 'What did I talk about in my last meeting?'",
                code: nil
            ),
        ]
    }

    // MARK: - Helpers

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) {
            let relative = RelativeDateTimeFormatter()
            return relative.localizedString(for: date, relativeTo: Date())
        }
        return iso
    }
}

// MARK: - View Model

@MainActor
class GatewaysViewModel: ObservableObject {
    @Published var keys: [ApiKeyListItem] = []
    @Published var isGenerating = false
    @Published var error: String?

    private let api = APIService.shared

    func loadKeys() async {
        do {
            let response = try await api.getApiKeys()
            keys = response.keys
        } catch {
            print("[Gateways] Failed to load keys: \(error)")
        }
    }

    func generateKey(name: String) async -> String? {
        isGenerating = true
        defer { isGenerating = false }

        do {
            let response = try await api.generateApiKey(name: name)
            await loadKeys()
            return response.key
        } catch {
            self.error = error.localizedDescription
            print("[Gateways] Failed to generate key: \(error)")
            return nil
        }
    }

    func revokeKey(id: String) async {
        do {
            _ = try await api.revokeApiKey(keyId: id)
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

#Preview {
    GatewaysView()
}
