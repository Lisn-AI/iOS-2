import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @StateObject private var purchaseService = PurchaseService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTier: PaywallTier = .pro
    @State private var selectedBilling: BillingPeriod = .monthly
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var celebrate = false

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

    /// App Store IAP product identifier for selected tier + billing.
    /// Must match the product IDs configured in App Store Connect → Monetization → Subscriptions.
    private var selectedProductId: String {
        switch (selectedTier, selectedBilling) {
        case (.pro, .monthly): return "com.lisnai.app.pro.monthly"
        case (.pro, .yearly): return "com.lisnai.app.pro.annual"
        case (.max, .monthly): return "com.lisnai.app.max.monthly"
        case (.max, .yearly): return "com.lisnai.app.max.yearly"
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
        .lisnCelebration(isActive: $celebrate)
        .task {
            await purchaseService.loadProducts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .subscriptionPurchased)) { _ in
            celebrate = true
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                dismiss()
            }
        }
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
            billingOption(.monthly, price: selectedTier == .pro ? "$9.99/mo" : "$19.99/mo")
            billingOption(.yearly, price: selectedTier == .pro ? "$79.99/yr" : "$179.99/yr")
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
                HStack(spacing: LisnSpacing.xs) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "applelogo")
                            .font(.system(size: 16, weight: .medium))
                        Text(subscribeButtonLabel)
                            .font(LisnFont.titleSmall())
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LisnSpacing.md)
                .background(LisnColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
            }
            .disabled(isPurchasing || purchaseService.products.isEmpty)

            Text(subscribeFootnote)
                .font(LisnFont.caption())
                .foregroundStyle(LisnColors.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    /// CTA label adapts based on whether products have loaded yet.
    private var subscribeButtonLabel: String {
        if purchaseService.isLoadingProducts {
            return "Loading…"
        }
        if purchaseService.products.isEmpty {
            return "Subscriptions launching soon"
        }
        return "Subscribe via App Store"
    }

    private var subscribeFootnote: String {
        if purchaseService.products.isEmpty {
            return "We're finishing the App Store handshake — check back in a moment."
        }
        return "Billing handled securely by Apple. Cancel anytime in Settings."
    }

    private func handleSubscribe() async {
        guard !purchaseService.products.isEmpty else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await purchaseService.purchase(productId: selectedProductId)
            // Success path is driven by NotificationCenter.subscriptionPurchased
        } catch PurchaseService.PurchaseError.userCancelled {
            // Silent — user dismissed the Apple sheet
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            AnalyticsService.shared.track(.purchaseFailed, properties: [
                "product_id": selectedProductId,
                "reason": error.localizedDescription
            ])
        }
    }

    private func handleRestore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await purchaseService.restorePurchases()
            await subscriptionService.syncUsageFromBackend()
            if purchaseService.hasActiveEntitlement {
                celebrate = true
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                dismiss()
            } else {
                errorMessage = "No active subscriptions to restore."
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private var footerLinks: some View {
        HStack(spacing: LisnSpacing.lg) {
            Button {
                Task { await handleRestore() }
            } label: {
                Text("Restore")
                    .font(LisnFont.caption())
                    .foregroundStyle(LisnColors.textSecondary)
            }
            .disabled(isPurchasing)

            Text("|")
                .foregroundStyle(LisnColors.borderSubtle)

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
        case (.pro, .yearly): packageId = "lisn_pro_annual"
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

