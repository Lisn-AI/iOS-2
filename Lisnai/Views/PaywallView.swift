import SwiftUI
import SafariServices
// import RevenueCat  // TODO: Uncomment when Apple IAP is ready

struct PaywallView: View {
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTier: PaywallTier = .pro
    @State private var selectedBilling: BillingPeriod = .monthly
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showCheckoutWebView = false
    @State private var checkoutURL: URL?
    @State private var isVerifyingPayment = false
    @State private var verificationTimedOut = false

    enum PaywallTier: String, CaseIterable {
        case pro, max

        var displayName: String {
            switch self {
            case .pro: return "Pro"
            case .max: return "Max"
            }
        }
    }

    enum BillingPeriod {
        case monthly, yearly

        var savingsText: String? {
            switch self {
            case .monthly: return nil
            case .yearly: return "Save 17%"
            }
        }
    }

    // Feature list for the paywall
    private let features: [(icon: String, text: String)] = [
        ("waveform.circle.fill", "600+ transcription minutes/month"),
        ("bubble.left.and.text.bubble.right.fill", "200+ chat messages/month"),
        ("magnifyingglass.circle.fill", "50+ memory searches/month"),
        ("bolt.circle.fill", "30+ actions/month"),
        ("icloud.fill", "Cloud backup & sync"),
        ("clock.arrow.circlepath", "Unlimited history retention"),
    ]

    private let maxExtras: [(icon: String, text: String)] = [
        ("sparkles", "Unlimited chat, search & actions"),
        ("crown.fill", "900 transcription minutes/month"),
    ]

    /// Razorpay plan alias for selected tier + billing
    private var selectedPlanId: String {
        switch (selectedTier, selectedBilling) {
        case (.pro, .monthly): return "pro_monthly"
        case (.pro, .yearly): return "pro_yearly"
        case (.max, .monthly): return "max_monthly"
        case (.max, .yearly): return "max_yearly"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LisnSpacing.xl) {
                // Header
                headerSection

                // Current plan badge (if subscribed)
                if subscriptionService.isPro {
                    currentPlanBadge
                }

                // Feature list
                featureList

                // Tier toggle
                tierToggle

                // Billing selector
                billingSelector

                // CTA
                purchaseButton

                // Footer links
                footerLinks
            }
            .padding(.horizontal, LisnSpacing.lg)
            .padding(.top, LisnSpacing.xl)
            .padding(.bottom, LisnSpacing.xxxxl)
        }
        .background(LisnColors.bgPrimary)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(LisnColors.textTertiary)
            }
            .padding(LisnSpacing.lg)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Something went wrong")
        }
        .sheet(isPresented: $showCheckoutWebView) {
            if let url = checkoutURL {
                RazorpayCheckoutView(url: url)
                    .onDisappear {
                        // Start polling for subscription activation
                        isVerifyingPayment = true
                        verificationTimedOut = false
                        Task {
                            let activated = await subscriptionService.pollForSubscriptionUpdate()
                            isVerifyingPayment = false
                            if activated {
                                // Success haptic + auto-dismiss
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                                dismiss()
                            } else {
                                verificationTimedOut = true
                            }
                        }
                    }
            }
        }
        .overlay {
            if isVerifyingPayment {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()

                    VStack(spacing: LisnSpacing.md) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(LisnColors.accent)

                        Text("Verifying your payment...")
                            .font(LisnFont.titleSmall())
                            .foregroundStyle(.white)

                        Text("This usually takes a few seconds")
                            .font(LisnFont.caption())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(LisnSpacing.xl)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
                }
                .transition(.opacity)
            }

            if verificationTimedOut {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()

                    VStack(spacing: LisnSpacing.md) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 36))
                            .foregroundStyle(LisnColors.warning)

                        Text("Payment processing")
                            .font(LisnFont.titleSmall())
                            .foregroundStyle(.white)

                        Text("Your payment is being processed.\nCheck back shortly — it may take a minute.")
                            .font(LisnFont.bodySmall())
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)

                        Button {
                            verificationTimedOut = false
                        } label: {
                            Text("OK")
                                .font(LisnFont.labelLarge())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, LisnSpacing.sm)
                                .background(LisnColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                        }
                    }
                    .padding(LisnSpacing.xl)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
                    .padding(.horizontal, LisnSpacing.xl)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isVerifyingPayment)
        .animation(.easeInOut(duration: 0.3), value: verificationTimedOut)
        // TODO: Uncomment when Apple IAP is ready
        // .task {
        //     await subscriptionService.loadOfferings()
        // }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: LisnSpacing.sm) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(LisnColors.accent)

            Text("Unlock Your Full\nMemory Assistant")
                .font(LisnFont.displayMedium())
                .foregroundStyle(LisnColors.textPrimary)
                .multilineTextAlignment(.center)

            if subscriptionService.isTrialActive {
                Text("\(subscriptionService.trialDaysRemaining) days left in your free trial")
                    .font(LisnFont.bodyMedium())
                    .foregroundStyle(LisnColors.accent)
            }
        }
    }

    /// Shows the user's current plan as a prominent badge
    private var currentPlanBadge: some View {
        HStack(spacing: LisnSpacing.sm) {
            Image(systemName: subscriptionService.isMax ? "crown.fill" : "star.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)

            Text("Current Plan: \(subscriptionService.tier.displayName)")
                .font(LisnFont.labelLarge())
                .foregroundStyle(.white)

            Spacer()

            Text("Active")
                .font(LisnFont.captionBold())
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, LisnSpacing.xs)
                .padding(.vertical, 3)
                .background(.white.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(LisnSpacing.md)
        .background(
            LinearGradient(
                colors: [LisnColors.accent, LisnColors.orbDark],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            Text("What you unlock")
                .font(LisnFont.labelLarge())
                .foregroundStyle(LisnColors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            let items = selectedTier == .max ? features + maxExtras : features

            ForEach(items, id: \.text) { feature in
                HStack(spacing: LisnSpacing.sm) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(LisnColors.success)
                        .frame(width: 24)

                    Text(feature.text)
                        .font(LisnFont.bodyMedium())
                        .foregroundStyle(LisnColors.textPrimary)
                }
            }
        }
        .padding(LisnSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LisnColors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
    }

    private var tierToggle: some View {
        HStack(spacing: 0) {
            ForEach(PaywallTier.allCases, id: \.self) { tier in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTier = tier
                    }
                } label: {
                    Text(tier.displayName)
                        .font(LisnFont.labelLarge())
                        .foregroundStyle(selectedTier == tier ? .white : LisnColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LisnSpacing.sm)
                        .background {
                            if selectedTier == tier {
                                Capsule()
                                    .fill(LisnColors.accent)
                            }
                        }
                }
            }
        }
        .padding(LisnSpacing.xxxs)
        .background(LisnColors.bgSecondary)
        .clipShape(Capsule())
    }

    private var billingSelector: some View {
        VStack(spacing: LisnSpacing.sm) {
            billingOption(.monthly, price: selectedTier == .pro ? "₹799/mo" : "₹1,999/mo")
            billingOption(.yearly, price: selectedTier == .pro ? "₹7,999/yr" : "₹19,999/yr")
        }
    }

    private func billingOption(_ period: BillingPeriod, price: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedBilling = period
            }
        } label: {
            HStack {
                Image(systemName: selectedBilling == period ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedBilling == period ? LisnColors.accent : LisnColors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(period == .monthly ? "Monthly" : "Yearly")
                            .font(LisnFont.labelLarge())
                            .foregroundStyle(LisnColors.textPrimary)

                        if let savings = period.savingsText {
                            Text(savings)
                                .font(LisnFont.captionBold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, LisnSpacing.xs)
                                .padding(.vertical, 2)
                                .background(LisnColors.success)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                Text(price)
                    .font(LisnFont.titleSmall())
                    .foregroundStyle(LisnColors.textPrimary)
            }
            .padding(LisnSpacing.md)
            .background(LisnColors.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            .overlay {
                if selectedBilling == period {
                    RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous)
                        .stroke(LisnColors.accent, lineWidth: 2)
                }
            }
        }
    }

    private var purchaseButton: some View {
        VStack(spacing: LisnSpacing.xs) {
            Button {
                Task { await handleSubscribe() }
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Subscribe Now")
                            .font(LisnFont.titleSmall())
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LisnSpacing.md)
                .background(LisnColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
            }
            .disabled(isPurchasing)

            Text("Secure payment via Razorpay")
                .font(LisnFont.caption())
                .foregroundStyle(LisnColors.textTertiary)
        }
    }

    private func handleSubscribe() async {
        isPurchasing = true
        do {
            let response = try await APIService.shared.createSubscription(planId: selectedPlanId)
            if let url = URL(string: response.shortUrl) {
                checkoutURL = url
                showCheckoutWebView = true
            } else {
                errorMessage = "Invalid checkout URL received"
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isPurchasing = false
    }

    private var footerLinks: some View {
        HStack(spacing: LisnSpacing.lg) {
            // TODO: Uncomment when Apple IAP is ready
            // Button("Restore Purchases") {
            //     Task { await handleRestore() }
            // }
            // .font(LisnFont.caption())
            // .foregroundStyle(LisnColors.textSecondary)
            //
            // Text("|")
            //     .foregroundStyle(LisnColors.borderSubtle)

            Link("Terms", destination: URL(string: "https://lisnai.com/terms")!)
                .font(LisnFont.caption())
                .foregroundStyle(LisnColors.textSecondary)

            Text("|")
                .foregroundStyle(LisnColors.borderSubtle)

            Link("Privacy", destination: URL(string: "https://lisnai.com/privacy")!)
                .font(LisnFont.caption())
                .foregroundStyle(LisnColors.textSecondary)
        }
    }

    // MARK: - Actions (RevenueCat — commented out for now)

    /*
    // TODO: Uncomment when Apple IAP is ready
    private func handlePurchase() async {
        guard let offerings = subscriptionService.offerings else { return }

        // Determine package identifier
        let packageId: String
        switch (selectedTier, selectedBilling) {
        case (.pro, .monthly): packageId = "lisn_pro_monthly"
        case (.pro, .yearly): packageId = "lisn_pro_yearly"
        case (.max, .monthly): packageId = "lisn_max_monthly"
        case (.max, .yearly): packageId = "lisn_max_yearly"
        }

        // Find matching package from offerings
        guard let offering = offerings.current,
              let package = offering.availablePackages.first(where: { $0.storeProduct.productIdentifier == packageId }) else {
            errorMessage = "Product not available. Please try again later."
            showError = true
            return
        }

        isPurchasing = true
        do {
            try await subscriptionService.purchase(package: package)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isPurchasing = false
    }

    private func handleRestore() async {
        isPurchasing = true
        do {
            try await subscriptionService.restorePurchases()
            if subscriptionService.isPro {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isPurchasing = false
    }
    */
}

// MARK: - Razorpay Checkout WebView

/// Opens the Razorpay-hosted checkout page in an in-app Safari view.
/// URL is obtained from the backend POST /payments/create-subscription endpoint.
struct RazorpayCheckoutView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false

        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredBarTintColor = UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0)
        safari.preferredControlTintColor = UIColor(red: 0.769, green: 0.506, blue: 0.239, alpha: 1.0)
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
