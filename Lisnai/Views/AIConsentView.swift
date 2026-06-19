import SwiftUI

/// One-time AI data consent screen required by App Store Guideline 5.1.2(i).
///
/// Must be shown before the first voice recording. Apple requires apps that
/// share personal data with third-party AI services to:
/// 1. Name the specific AI provider
/// 2. Explain what data is transmitted
/// 3. Get explicit user permission before sending
///
/// Consent is stored in UserDefaults. Once granted, never shown again.
struct AIConsentView: View {
    @Environment(\.dismiss) private var dismiss
    var onConsent: () -> Void

    @State private var scrolledToBottom = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: LisnSpacing.lg) {
                    // Header
                    VStack(spacing: LisnSpacing.sm) {
                        Image(systemName: "brain.head.profile.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(LisnColors.accent)
                            .padding(.top, LisnSpacing.xl)

                        Text("How Lisn Uses AI")
                            .font(LisnFont.displayMedium())
                            .foregroundStyle(LisnColors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("Before you start recording, here's what you should know about how your data is processed.")
                            .font(LisnFont.bodyMedium())
                            .foregroundStyle(LisnColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, LisnSpacing.md)

                    // What we send
                    consentSection(
                        icon: "waveform",
                        title: "Voice & transcription data",
                        body: "Your voice recordings are sent to our secure backend server, which uses **Google's Gemini AI** to transcribe, summarize, and analyze your recordings. This powers features like memory search, daily summaries, and smart actions."
                    )

                    consentSection(
                        icon: "brain",
                        title: "AI provider",
                        body: "We use **Google (Gemini AI)** via Google Cloud Vertex AI to process your voice data. Google processes the data according to their Cloud terms of service. Your recordings are not used to train AI models."
                    )

                    consentSection(
                        icon: "lock.shield",
                        title: "Your data stays yours",
                        body: "All data is encrypted in transit (TLS) and at rest. You can delete your account and all associated data at any time by contacting team@lisnai.com. We never sell your data or share it with advertisers."
                    )

                    consentSection(
                        icon: "location",
                        title: "Optional location",
                        body: "If you enable the home zone feature, your approximate location is used locally on your device to trigger recording reminders. Location data is never sent to our servers or any AI provider."
                    )

                    // Privacy policy link
                    HStack {
                        Spacer()
                        Link("Read our full Privacy Policy", destination: URL(string: "https://lisnai-website.onrender.com/privacy")!)
                            .font(LisnFont.bodySmall())
                            .foregroundStyle(LisnColors.accent)
                        Spacer()
                    }
                    .padding(.top, LisnSpacing.sm)

                    // Spacer to detect scroll-to-bottom
                    Color.clear.frame(height: 1)
                        .onAppear { scrolledToBottom = true }
                }
                .padding(.horizontal, LisnSpacing.lg)
                .padding(.bottom, LisnSpacing.xl)
            }

            // Bottom CTA
            VStack(spacing: LisnSpacing.sm) {
                Divider()

                Button {
                    AIConsentManager.grantConsent()
                    onConsent()
                    dismiss()
                } label: {
                    Text("I Understand & Agree")
                        .font(LisnFont.titleSmall())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LisnSpacing.md)
                        .background(LisnColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
                }

                Text("You can revoke consent anytime by deleting your account.")
                    .font(LisnFont.caption())
                    .foregroundStyle(LisnColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, LisnSpacing.lg)
            .padding(.bottom, LisnSpacing.lg)
            .padding(.top, LisnSpacing.xs)
            .background(LisnColors.bgPrimary)
        }
        .background(LisnColors.bgPrimary)
    }

    private func consentSection(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: LisnSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(LisnColors.accent)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(LisnFont.labelLarge())
                    .foregroundStyle(LisnColors.textPrimary)

                Text(.init(body))
                    .font(LisnFont.bodySmall())
                    .foregroundStyle(LisnColors.textSecondary)
            }
        }
        .padding(LisnSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LisnColors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
    }
}

/// Manages AI consent state. Consent is required once before first recording.
enum AIConsentManager {
    private static let key = "ai_data_consent_granted"
    private static let dateKey = "ai_data_consent_date"

    static var hasConsented: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    @MainActor
    static func grantConsent() {
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: dateKey)
        AnalyticsService.shared.track(.aiConsentGranted)
        AnalyticsService.shared.setUserProperty("ai_consent_granted", value: true)
    }

    static func revokeConsent() {
        UserDefaults.standard.set(false, forKey: key)
        UserDefaults.standard.removeObject(forKey: dateKey)
    }
}
