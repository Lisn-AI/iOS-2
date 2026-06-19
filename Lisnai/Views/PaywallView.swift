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

    // MARK: - Tier-aware state

    /// What the user currently has (from backend, authoritative)
    private var currentTier: SubscriptionTier { subscriptionService.tier }

    /// Is this user already on the highest plan?
    private var isOnMax: Bool { subscriptionService.isMax }

    /// Is this user on Pro (but not Max)?
    private var isOnPro: Bool { currentTier == .pro }

    /// The exact product ID the user currently has (from StoreKit entitlements).
    /// nil = free / no subscription.
    private var currentProductId: String? { PurchaseService.shared.activeProductId }

    /// Can the selected combo be purchased?
    /// Blocked only when: (a) exact same product already owned, or (b) downgrading tier in-app (Max→Pro)
    private var canPurchaseSelected: Bool {
        if selectedProductId == currentProductId { return false }
        if currentTier == .max && selectedTier == .pro { return false }
        return true
    }

    /// Is the selected combo the user's current active product?
    private var isSelectedCurrentProduct: Bool {
        selectedProductId == currentProductId
    }

    /// What kind of action is the user taking?
    private var purchaseAction: PurchaseAction {
        if currentTier == .free { return .newPurchase }
        if currentTier == .max && selectedTier == .pro { return .blocked }
        if selectedProductId == currentProductId { return .alreadyOwned }
        if selectedTier == .max && currentTier == .pro { return .tierUpgrade }
        // Same tier, different billing cycle
        return .billingChange
    }

    private enum PurchaseAction {
        case newPurchase
        case tierUpgrade
        case billingChange
        case alreadyOwned
        case blocked
    }

    /// App Store IAP product identifier for selected tier + billing
    private var selectedProductId: String {
        switch (selectedTier, selectedBilling) {
        case (.pro, .monthly): return "com.lisnai.app.pro.monthly"
        case (.pro, .yearly): return "com.lisnai.app.pro.annual"
        case (.max, .monthly): return "com.lisnai.app.max.monthly"
        case (.max, .yearly): return "com.lisnai.app.max.yearly"
        }
    }

    // MARK: - Feature lists per tier

    private var proFeatures: [(icon: String, text: String)] {
        [
            ("waveform.circle.fill", "30 hours recording / month"),
            ("bubble.left.and.text.bubble.right.fill", "200 chat messages / month"),
            ("magnifyingglass.circle.fill", "100 memory searches / month"),
            ("bolt.circle.fill", "50 actions / month"),
            ("icloud.fill", "Cloud backup & sync"),
            ("clock.arrow.circlepath", "Unlimited history retention"),
        ]
    }

    private var maxFeatures: [(icon: String, text: String)] {
        [
            ("waveform.circle.fill", "50 hours recording / month"),
            ("bubble.left.and.text.bubble.right.fill", "Unlimited chat messages"),
            ("magnifyingglass.circle.fill", "Unlimited memory searches"),
            ("bolt.circle.fill", "Unlimited actions"),
            ("icloud.fill", "Cloud backup & sync"),
            ("clock.arrow.circlepath", "Unlimited history retention"),
            ("person.crop.circle.badge.checkmark", "Priority support"),
        ]
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: LisnSpacing.xl) {
                headerSection
                statusBanner
                featureList
                tierToggle
                billingSelector
                purchaseButton
                manageSubscriptionLink
                footerLinks
            }
            .padding(.horizontal, LisnSpacing.lg)
            .padding(.top, LisnSpacing.xl)
            .padding(.bottom, LisnSpacing.xxxxl)
        }
        .background(LisnColors.bgPrimary)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
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
            // Auto-select the right default based on current tier
            if isOnPro {
                selectedTier = .max
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .subscriptionPurchased)) { _ in
            celebrate = true
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: LisnSpacing.sm) {
            Image(systemName: isOnMax ? "crown.fill" : (isOnPro ? "arrow.up.circle.fill" : "crown.fill"))
                .font(.system(size: 44))
                .foregroundStyle(LisnColors.accent)

            Text(headerTitle)
                .font(LisnFont.displayMedium())
                .foregroundStyle(LisnColors.textPrimary)
                .multilineTextAlignment(.center)

            if let subtitle = headerSubtitle {
                Text(subtitle)
                    .font(LisnFont.bodyMedium())
                    .foregroundStyle(LisnColors.accent)
            }
        }
    }

    private var headerTitle: String {
        if isOnMax {
            return "You're on\nLisn Max"
        }
        if isOnPro {
            return "You're on Pro.\nGo further?"
        }
        return "Unlock Your Full\nMemory Assistant"
    }

    private var headerSubtitle: String? {
        if isOnMax, subscriptionService.isCancelledButActive,
           let date = subscriptionService.cancellationExpiryDisplay {
            return "Your plan expires on \(date)"
        }
        if isOnPro, subscriptionService.isCancelledButActive,
           let date = subscriptionService.cancellationExpiryDisplay {
            return "Pro expires on \(date). Upgrade or renew below."
        }
        if let window = subscriptionService.freeWindow, window.isWithinWindow {
            return "\(window.daysRemaining) days left in your free window"
        }
        if let window = subscriptionService.freeWindow, !window.isWithinWindow {
            return "Your free window has ended. Subscribe to keep using Lisn."
        }
        return nil
    }

    // MARK: - Status banner (current plan badge OR cancellation warning)

    @ViewBuilder
    private var statusBanner: some View {
        if subscriptionService.isCancelledButActive {
            HStack(spacing: LisnSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(currentTier.displayName) plan cancelled")
                        .font(LisnFont.labelLarge())
                        .foregroundStyle(.white)
                    if let date = subscriptionService.cancellationExpiryDisplay {
                        Text("Access until \(date)")
                            .font(LisnFont.caption())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                Spacer()
            }
            .padding(LisnSpacing.md)
            .background(LisnColors.warning)
            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))

        } else if subscriptionService.status == .graceperiod {
            HStack(spacing: LisnSpacing.sm) {
                Image(systemName: "creditcard.trianglebadge.exclamationmark")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Payment issue")
                        .font(LisnFont.labelLarge())
                        .foregroundStyle(.white)
                    Text("Update your payment method in Settings to keep your plan.")
                        .font(LisnFont.caption())
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()
            }
            .padding(LisnSpacing.md)
            .background(Color.red.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))

        } else if currentTier != .free {
            HStack(spacing: LisnSpacing.sm) {
                Image(systemName: isOnMax ? "crown.fill" : "star.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)

                Text("Current Plan: \(currentTier.displayName)")
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
    }

    // MARK: - Feature list (adapts to selected tier)

    private var featureList: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            Text(isOnMax ? "Your plan includes" : "What you unlock")
                .font(LisnFont.labelLarge())
                .foregroundStyle(LisnColors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            let items = (isOnMax || selectedTier == .max) ? maxFeatures : proFeatures

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

    // MARK: - Tier toggle (hidden for Max subscribers)

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

    // MARK: - Billing selector (hidden for Max subscribers)

    private var billingSelector: some View {
        VStack(spacing: LisnSpacing.sm) {
            billingOption(.monthly, price: selectedTier == .pro ? "$9.99/mo" : "$19.99/mo")
            billingOption(.yearly, price: selectedTier == .pro ? "$79.99/yr" : "$179.99/yr")
        }
    }

    /// The product ID this billing row represents (for the currently selected tier)
    private func productIdFor(_ tier: PaywallTier, _ period: BillingPeriod) -> String {
        switch (tier, period) {
        case (.pro, .monthly): return "com.lisnai.app.pro.monthly"
        case (.pro, .yearly): return "com.lisnai.app.pro.annual"
        case (.max, .monthly): return "com.lisnai.app.max.monthly"
        case (.max, .yearly): return "com.lisnai.app.max.yearly"
        }
    }

    private func billingOption(_ period: BillingPeriod, price: String) -> some View {
        let isThisCurrentProduct = productIdFor(selectedTier, period) == currentProductId

        return Button {
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
                            .foregroundStyle(isThisCurrentProduct ? LisnColors.textTertiary : LisnColors.textPrimary)

                        if isThisCurrentProduct {
                            Text("Current")
                                .font(LisnFont.captionBold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, LisnSpacing.xs)
                                .padding(.vertical, 2)
                                .background(LisnColors.accent.opacity(0.6))
                                .clipShape(Capsule())
                        } else if let savings = period.savingsText {
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
                    .foregroundStyle(isThisCurrentProduct ? LisnColors.textTertiary : LisnColors.textPrimary)
            }
            .padding(LisnSpacing.md)
            .background(LisnColors.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous)
                    .stroke(
                        isThisCurrentProduct ? LisnColors.accent.opacity(0.4) :
                        (selectedBilling == period ? LisnColors.accent : Color.clear),
                        lineWidth: 2
                    )
            }
        }
    }

    // MARK: - Purchase button (hidden for Max subscribers)

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
                .background(canPurchaseSelected ? LisnColors.accent : LisnColors.textTertiary)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
            }
            .disabled(isPurchasing || purchaseService.products.isEmpty || !canPurchaseSelected)

            Text(subscribeFootnote)
                .font(LisnFont.caption())
                .foregroundStyle(LisnColors.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var subscribeButtonLabel: String {
        if purchaseService.isLoadingProducts { return "Loading..." }
        if purchaseService.products.isEmpty { return "Subscriptions launching soon" }

        switch purchaseAction {
        case .alreadyOwned: return "Current plan"
        case .blocked: return "Manage in Settings"
        case .tierUpgrade: return "Upgrade to \(selectedTier.displayName)"
        case .billingChange:
            let cycle = selectedBilling == .yearly ? "Yearly" : "Monthly"
            return "Switch to \(cycle)"
        case .newPurchase: return "Subscribe via App Store"
        }
    }

    private var subscribeFootnote: String {
        if purchaseService.products.isEmpty {
            return "We're finishing the App Store handshake — check back in a moment."
        }
        switch purchaseAction {
        case .alreadyOwned: return "You're on this plan. Switch billing or upgrade above."
        case .blocked: return "To change to a lower tier, manage your subscription in Apple Settings."
        case .tierUpgrade: return "Apple prorates the upgrade. You only pay the difference."
        case .billingChange: return "Your new billing cycle starts at the next renewal."
        case .newPurchase: return "Billing handled securely by Apple. Cancel anytime in Settings."
        }
    }

    // MARK: - Manage subscription link (for active subscribers)

    @ViewBuilder
    private var manageSubscriptionLink: some View {
        if currentTier != .free {
            Button {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: LisnSpacing.xs) {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                    Text("Manage Subscription in Settings")
                        .font(LisnFont.bodySmall())
                }
                .foregroundStyle(LisnColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LisnSpacing.sm)
                .background(LisnColors.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            }
        }
    }

    // MARK: - Actions

    private func handleSubscribe() async {
        guard !purchaseService.products.isEmpty, canPurchaseSelected else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await purchaseService.purchase(productId: selectedProductId)
        } catch PurchaseService.PurchaseError.userCancelled {
            // Silent
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

    // MARK: - Footer

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

            Link("Terms", destination: URL(string: "https://lisnai-website.onrender.com/terms")!)
                .font(LisnFont.caption())
                .foregroundStyle(LisnColors.textSecondary)

            Text("|")
                .foregroundStyle(LisnColors.borderSubtle)

            Link("Privacy", destination: URL(string: "https://lisnai-website.onrender.com/privacy")!)
                .font(LisnFont.caption())
                .foregroundStyle(LisnColors.textSecondary)
        }
    }
}
