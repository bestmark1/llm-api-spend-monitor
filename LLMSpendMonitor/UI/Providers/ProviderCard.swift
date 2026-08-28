import SwiftUI

struct ProviderCard: View {
    let metadata: ProviderMetadata
    let snapshot: ProviderSnapshot?
    let freshness: ProviderFreshness?
    let platformBalance: PlatformBalanceStatus?
    let synchronizeBalance: ((Money) async -> Bool)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage private var isExpanded: Bool
    @State private var isBalanceEditorPresented = false

    init(
        metadata: ProviderMetadata,
        snapshot: ProviderSnapshot?,
        freshness: ProviderFreshness? = nil,
        platformBalance: PlatformBalanceStatus? = nil,
        synchronizeBalance: ((Money) async -> Bool)? = nil
    ) {
        self.metadata = metadata
        self.snapshot = snapshot
        self.freshness = freshness
        self.platformBalance = platformBalance
        self.synchronizeBalance = synchronizeBalance
        _isExpanded = AppStorage(
            wrappedValue: false,
            "provider.card.\(metadata.id.rawValue).expanded"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header

            if isExpanded {
                if snapshot != nil || platformBalance != nil {
                    metricContent(snapshot)
                } else {
                    emptyState
                }

                footer
                    .transition(.opacity)
            } else {
                compactOverview
                    .transition(.opacity)
            }
        }
        .padding(15)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("provider.\(metadata.id.rawValue).card")
        .sheet(isPresented: $isBalanceEditorPresented) {
            if let synchronizeBalance {
                PlatformBalanceEditor(
                    metadata: metadata,
                    currentBalance: platformBalance,
                    save: synchronizeBalance
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: metadata.systemImageName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ProviderVisualStyle.color(for: metadata.id))
                .frame(width: 30, height: 30)
                .background(
                    ProviderVisualStyle.color(for: metadata.id).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(metadata.displayName)
                    .font(.headline)
                Text(capabilityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            statusBadge

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(isExpanded ? "Collapse \(metadata.displayName)" : "Expand \(metadata.displayName)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("provider.\(metadata.id.rawValue).disclosure")
        }
    }

    @ViewBuilder
    private var compactOverview: some View {
        if metadata.capabilities.contains(.balance), let balance = snapshot?.balances.first {
            compactMoneyRow(
                label: officialBalanceLabel,
                money: balance.total.value,
                detail: officialBalanceDetail(balance, snapshot: snapshot)
            )
        } else if let platformBalance {
            compactMoneyRow(
                label: "Remaining balance",
                money: platformBalance.remaining,
                detail: compactTrackedDetail(snapshot)
            )
        } else if let snapshot,
                  let issue = snapshot.issue,
                  snapshot.buckets.isEmpty,
                  snapshot.balances.isEmpty {
            Label(issueEmptyStateText(issue), systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if synchronizeBalance != nil {
            compactBalanceSetup(snapshot)
        } else if let snapshot, let cost = costTotals(snapshot).first {
            compactMoneyRow(
                label: "Period spend",
                money: cost,
                detail: tokenSummary(snapshot)
            )
        } else if let snapshot, let tokens = tokenSummary(snapshot) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Period usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(tokens)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("provider.\(metadata.id.rawValue).summary")
        } else if geminiUsageNeedsConnection {
            Label(
                "API key connected · connect Google usage in Connections",
                systemImage: "link.badge.plus"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else if metadata.capabilities == [.credentialValidation], snapshot?.issue == nil, snapshot != nil {
            Label("API key verified", systemImage: "checkmark.seal.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        } else if snapshot != nil {
            Text("Connected · financial metrics unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            emptyState
        }
    }

    private func compactMoneyRow(label: String, money: Money, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(MetricFormatting.money(money))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("provider.\(metadata.id.rawValue).summary")
    }

    private func compactBalanceSetup(_ snapshot: ProviderSnapshot?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Remaining balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Not set")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                if let detail = compactTrackedDetail(snapshot) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            balanceButton(title: "Add Balance")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("provider.\(metadata.id.rawValue).summary")
    }

    private func compactTrackedDetail(_ snapshot: ProviderSnapshot?) -> String? {
        guard let snapshot else { return nil }
        var parts: [String] = []
        if let cost = costTotals(snapshot).first {
            parts.append("\(MetricFormatting.money(cost)) spent")
        }
        if let tokens = tokenSummary(snapshot) {
            parts.append(tokens)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func officialBalanceDetail(
        _ balance: ProviderBalance,
        snapshot: ProviderSnapshot?
    ) -> String? {
        var parts: [String] = []
        if let snapshot, let cost = costTotals(snapshot).first {
            let qualifier = hasEstimatedCost(snapshot) ? "estimated spent" : "spent"
            parts.append("\(MetricFormatting.money(cost)) \(qualifier)")
        }
        if metadata.id != .deepSeek {
            if let granted = balance.granted {
                parts.append("\(MetricFormatting.money(granted.value)) granted")
            }
            if let toppedUp = balance.toppedUp {
                parts.append("\(MetricFormatting.money(toppedUp.value)) topped up")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func metricContent(_ snapshot: ProviderSnapshot?) -> some View {
        if metadata.capabilities.contains(.balance), let balance = snapshot?.balances.first {
            officialBalanceContent(balance)
            if let snapshot, let cost = costTotals(snapshot).first {
                Divider()
                periodSpendContent(snapshot, cost: cost)
            }
        } else {
            trackedProviderContent(snapshot)
        }

        if let snapshot {
            Text(updateText(snapshot))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("provider.\(metadata.id.rawValue).updated")
        }
    }

    @ViewBuilder
    private func officialBalanceContent(_ balance: ProviderBalance) -> some View {
        primaryMetric(label: officialBalanceLabel, money: balance.total.value)

        if metadata.id != .deepSeek, (balance.granted != nil || balance.toppedUp != nil) {
            VStack(spacing: 7) {
                if let granted = balance.granted {
                    MetricRow(label: "Granted", value: MetricFormatting.money(granted.value))
                }
                if let toppedUp = balance.toppedUp {
                    MetricRow(label: "Topped up", value: MetricFormatting.money(toppedUp.value))
                }
            }
        }
    }

    @ViewBuilder
    private func trackedProviderContent(_ snapshot: ProviderSnapshot?) -> some View {
        if let platformBalance {
            platformBalanceContent(platformBalance)
        } else if synchronizeBalance != nil {
            balanceSetupContent
        }

        if let snapshot,
           let issue = snapshot.issue,
           snapshot.buckets.isEmpty,
           snapshot.balances.isEmpty {
            Label(issueEmptyStateText(issue), systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let snapshot, let cost = costTotals(snapshot).first {
            if platformBalance != nil || synchronizeBalance != nil {
                Divider()
            }
            periodSpendContent(snapshot, cost: cost)
        } else if let snapshot, tokenTotal(snapshot) != nil {
            if platformBalance != nil || synchronizeBalance != nil {
                Divider()
            }
            tokenRows(snapshot)
            modelRows(snapshot)
        } else if geminiUsageNeedsConnection {
            VStack(alignment: .leading, spacing: 5) {
                Label("API key connected", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.medium))
                Text("Connect Google usage in Connections to load official token and model metrics.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if metadata.capabilities == [.credentialValidation], snapshot?.issue == nil {
            if platformBalance != nil {
                Divider()
            }
            Label("API key verified", systemImage: "checkmark.seal.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        } else if platformBalance == nil, synchronizeBalance == nil {
            Text("Connected · financial metrics unavailable")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func periodSpendContent(_ snapshot: ProviderSnapshot, cost: Money) -> some View {
        primaryMetric(
            label: hasEstimatedCost(snapshot) ? "Estimated period spend" : "Period spend",
            money: cost
        )
        if hasEstimatedCost(snapshot) {
            Text("Calculated from saved balance decreases. Top-ups are not counted as spend.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        tokenRows(snapshot)
        modelRows(snapshot)
    }

    private var balanceSetupContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remaining balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Not set")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                }
                Spacer()
                balanceButton(title: "Add Balance")
            }

            Text("Enter the current amount from Billing to track what remains automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("provider.\(metadata.id.rawValue).balanceSetup")
    }

    private func platformBalanceContent(_ balance: PlatformBalanceStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Remaining balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                balanceButton(title: "Recalibrate")
            }

            Text(MetricFormatting.money(balance.remaining))
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit()

            if balance.automaticallyDeductsSpend {
                MetricRow(
                    label: "Spent since calibration",
                    value: MetricFormatting.money(balance.deductedSpend)
                )
            }

            Text("Calibrated \(balance.synchronizedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("provider.\(metadata.id.rawValue).platformBalance")
    }

    private func balanceButton(title: String) -> some View {
        Button(title) { isBalanceEditorPresented = true }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("provider.\(metadata.id.rawValue).balance")
    }

    private func primaryMetric(label: String, money: Money) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MetricFormatting.money(money))
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func tokenRows(_ snapshot: ProviderSnapshot) -> some View {
        if let tokens = tokenTotal(snapshot) {
            HStack(spacing: 18) {
                compactMetric("Input", value: MetricFormatting.tokens(tokens.input))
                    .help("Input includes cached tokens where the provider reports them.")
                    .accessibilityHint("Includes cached tokens where reported")
                if tokens.cachedInput > 0 {
                    compactMetric("Cached", value: MetricFormatting.tokens(tokens.cachedInput))
                        .help("Cached input is included in the Input total.")
                        .accessibilityHint("Included in the Input total")
                }
                compactMetric("Output", value: MetricFormatting.tokens(tokens.output))
                Spacer(minLength: 0)
            }
        }
    }

    private func compactMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func modelRows(_ snapshot: ProviderSnapshot) -> some View {
        let models = modelSummaries(snapshot)
        if !models.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("Top models")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                ForEach(models.prefix(3)) { model in
                    HStack(spacing: 8) {
                        Text(model.modelID)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(MetricFormatting.tokens(model.tokens))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .help(model.modelID)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "link.badge.plus")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(emptyStateText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            ForEach(
                metadata.externalLinks.filter {
                    $0.kind == .billing || $0.kind == .dashboard || $0.kind == .status
                },
                id: \.kind
            ) { link in
                Link(destination: link.url) {
                    HStack(spacing: 4) {
                        Text(linkTitle(link.kind))
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier(
                    "provider.\(metadata.id.rawValue).\(link.kind.rawValue)"
                )
            }
        }
    }

    private func linkTitle(_ kind: ExternalLink.Kind) -> String {
        switch kind {
        case .billing: "Billing"
        case .status: "Status"
        case .dashboard: "Dashboard"
        case .usage: "Usage"
        }
    }

    private var statusBadge: some View {
        Label(status.title, systemImage: status.icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.1), in: Capsule())
            .accessibilityIdentifier("provider.\(metadata.id.rawValue).status")
    }

    private var status: (title: String, icon: String, color: Color) {
        if metadata.integrationAvailability == .planned {
            return ("Planned", "clock", .secondary)
        }
        if metadata.integrationAvailability == .unavailable {
            return ("Unavailable", "xmark.circle", .secondary)
        }
        guard let snapshot else {
            return ("Not connected", "circle", .secondary)
        }
        if geminiUsageNeedsConnection {
            return ("Setup needed", "link.badge.plus", .orange)
        }
        guard let issue = snapshot.issue else {
            switch freshness ?? .current {
            case .current:
                return ("Current", "checkmark.circle.fill", .green)
            case .processing:
                return ("Current", "checkmark.circle.fill", .green)
            case .stale:
                return ("Stale", "clock.badge.exclamationmark", .orange)
            }
        }
        switch issue {
        case .authentication, .insufficientPermissions, .keychainLocked:
            return ("Action needed", "exclamationmark.circle.fill", .red)
        case .balanceUnavailable:
            return ("Balance unavailable", "exclamationmark.triangle.fill", .orange)
        case .noSpendingLimit:
            return ("No limit", "checkmark.circle.fill", .green)
        case .partialData:
            return ("Partial", "circle.lefthalf.filled", .orange)
        case .rateLimited, .offline, .malformedResponse, .providerUnavailable:
            return ("Cached", "clock.badge.exclamationmark", .orange)
        case .spendingLimitReached:
            return ("Limit reached", "exclamationmark.circle.fill", .red)
        }
    }

    private var capabilityText: String {
        if metadata.integrationAvailability == .planned {
            return "Integration planned"
        }
        if metadata.integrationAvailability == .unavailable {
            return "No account-wide billing API"
        }
        if metadata.capabilities.contains(.officialCostHistory) {
            var parts = ["Cost"]
            if metadata.capabilities.contains(.balance) {
                parts.append("balance")
            }
            if metadata.capabilities.contains(.tokenUsage) {
                parts.append("tokens")
            }
            if metadata.capabilities.contains(.modelBreakdown) {
                parts.append("models")
            }
            return parts.joined(separator: " · ")
        }
        if metadata.capabilities.contains(.estimatedCostHistory) {
            return metadata.capabilities.contains(.balance)
                ? "Balance · estimated spend"
                : "Estimated spend"
        }
        if metadata.capabilities.contains(.balance) {
            return "Official balance"
        }
        if metadata.capabilities.contains(.tokenUsage) {
            return metadata.capabilities.contains(.modelBreakdown)
                ? "Tokens · models"
                : "Tokens"
        }
        return "Key validation"
    }

    private var officialBalanceLabel: String {
        switch metadata.id {
        case .qwen:
            "Alibaba Cloud account balance"
        case .mistral:
            "Remaining monthly limit"
        default:
            "Remaining balance"
        }
    }

    private var emptyStateText: String {
        if metadata.integrationAvailability == .planned {
            return "Spending integration is not available yet."
        }
        if metadata.integrationAvailability == .unavailable {
            return metadata.credentialHelp
        }
        return metadata.capabilities == [.credentialValidation]
            ? "Connect a key to verify access. Spend stays in Google AI Studio."
            : "Connect this provider to load official data."
    }

    private func updateText(_ snapshot: ProviderSnapshot) -> String {
        let timestamp = snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)
        if geminiUsageNeedsConnection {
            return "API key checked \(timestamp) · usage not connected"
        }
        guard let issue = snapshot.issue else {
            switch freshness ?? .current {
            case .current: return "Updated \(timestamp)"
            case .processing: return "Updated \(timestamp) · cost report processing"
            case .stale: return "Last update \(timestamp) · refresh pending"
            }
        }
        return "Last update \(timestamp) · \(issueText(issue))"
    }

    private func issueText(_ issue: ProviderIssue) -> String {
        switch issue {
        case .authentication: "Check credential"
        case .balanceUnavailable: "Balance unavailable"
        case .insufficientPermissions: "Insufficient permissions"
        case .rateLimited: "Rate limited"
        case .offline: "Offline"
        case .keychainLocked: "Keychain locked"
        case .malformedResponse: "Unexpected response"
        case .noSpendingLimit: "No spending limit"
        case .providerUnavailable: "Provider unavailable"
        case .partialData: "Partial report"
        case .spendingLimitReached: "Spending limit reached"
        }
    }

    private func issueEmptyStateText(_ issue: ProviderIssue) -> String {
        switch issue {
        case .authentication: "The saved credential was rejected. Replace it in Connections."
        case .balanceUnavailable: "The provider account balance is temporarily unavailable."
        case .insufficientPermissions: "The saved credential needs additional permissions."
        case .rateLimited: "The provider is rate limiting requests. Try again later."
        case .offline: "The provider could not be reached. Check your connection."
        case .keychainLocked: "Unlock your Mac to read the saved credential."
        case .malformedResponse: "The provider returned an unexpected response."
        case .noSpendingLimit: "This organization has no monthly spending limit."
        case .providerUnavailable: "The provider is temporarily unavailable."
        case .partialData: "The provider returned an incomplete report."
        case .spendingLimitReached: "This organization has reached its monthly spending limit."
        }
    }

    private func costTotals(_ snapshot: ProviderSnapshot) -> [Money] {
        let totals = snapshot.buckets.reduce(into: [String: Decimal]()) { result, bucket in
            guard
                let cost = bucket.cost,
                cost.provenance == .official || cost.provenance == .estimated
            else { return }
            result[cost.value.currencyCode, default: 0] += cost.value.amount
        }
        return totals.keys.sorted().compactMap { currencyCode in
            try? Money(amount: totals[currencyCode, default: 0], currencyCode: currencyCode)
        }
    }

    private func hasEstimatedCost(_ snapshot: ProviderSnapshot) -> Bool {
        snapshot.buckets.contains { $0.cost?.provenance == .estimated }
    }

    private func tokenTotal(
        _ snapshot: ProviderSnapshot
    ) -> (input: Int64, cachedInput: Int64, output: Int64)? {
        let values = snapshot.buckets.compactMap(\.tokenUsage)
        guard !values.isEmpty else { return nil }
        return (
            values.reduce(0) { $0 + $1.inputTokens },
            values.reduce(0) { $0 + $1.cachedInputTokens },
            values.reduce(0) { $0 + $1.outputTokens }
        )
    }

    private var geminiUsageNeedsConnection: Bool {
        metadata.id == .gemini
            && snapshot?.issue == nil
            && snapshot?.coverage == nil
            && snapshot?.buckets.isEmpty == true
            && snapshot?.balances.isEmpty == true
    }

    private func tokenSummary(_ snapshot: ProviderSnapshot) -> String? {
        guard let tokens = tokenTotal(snapshot) else { return nil }
        return "\(MetricFormatting.tokens(tokens.input)) in · \(MetricFormatting.tokens(tokens.output)) out"
    }

    private func modelSummaries(_ snapshot: ProviderSnapshot) -> [ModelSummary] {
        var totals: [String: Int64] = [:]
        for model in snapshot.buckets.flatMap(\.modelBreakdown) {
            guard let usage = model.tokenUsage else { continue }
            totals[model.modelID, default: 0] += usage.inputTokens + usage.outputTokens
        }
        return totals.map { ModelSummary(modelID: $0.key, tokens: $0.value) }
            .sorted { lhs, rhs in
                lhs.tokens == rhs.tokens ? lhs.modelID < rhs.modelID : lhs.tokens > rhs.tokens
            }
    }
}

private struct ModelSummary: Identifiable {
    let modelID: String
    let tokens: Int64

    var id: String { modelID }
}
