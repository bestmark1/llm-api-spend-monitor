import SwiftUI

struct ProviderCard: View {
    let metadata: ProviderMetadata
    let snapshot: ProviderSnapshot?
    let platformBalance: PlatformBalanceStatus?
    let synchronizeBalance: ((Money) async -> Bool)?

    @State private var isBalanceEditorPresented = false

    init(
        metadata: ProviderMetadata,
        snapshot: ProviderSnapshot?,
        platformBalance: PlatformBalanceStatus? = nil,
        synchronizeBalance: ((Money) async -> Bool)? = nil
    ) {
        self.metadata = metadata
        self.snapshot = snapshot
        self.platformBalance = platformBalance
        self.synchronizeBalance = synchronizeBalance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header

            if snapshot != nil || platformBalance != nil {
                metricContent(snapshot)
            } else {
                emptyState
            }

            footer
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
        }
    }

    @ViewBuilder
    private func metricContent(_ snapshot: ProviderSnapshot?) -> some View {
        if metadata.capabilities.contains(.balance), let balance = snapshot?.balances.first {
            officialBalanceContent(balance)
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
        primaryMetric(label: "Available balance", money: balance.total.value)

        if balance.granted != nil || balance.toppedUp != nil {
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
        }

        if let snapshot, let cost = costTotals(snapshot).first {
            if platformBalance != nil {
                Divider()
            }
            primaryMetric(label: "Period spend", money: cost)
            tokenRows(snapshot)
            modelRows(snapshot)
        } else if metadata.capabilities == [.credentialValidation], snapshot?.issue == nil {
            if platformBalance != nil {
                Divider()
            }
            Label("API key verified", systemImage: "checkmark.seal.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        } else if platformBalance == nil {
            Text("Connected · financial metrics unavailable")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        if synchronizeBalance != nil, platformBalance == nil {
            balanceButton(title: "Add Balance")
        }
    }

    private func platformBalanceContent(_ balance: PlatformBalanceStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Remaining balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                balanceButton(title: "Update")
            }

            Text(MetricFormatting.money(balance.remaining))
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit()

            if balance.automaticallyDeductsSpend {
                MetricRow(
                    label: "Spent since sync",
                    value: MetricFormatting.money(balance.deductedSpend)
                )
            }

            Text("Synced \(balance.synchronizedAt.formatted(date: .abbreviated, time: .shortened))")
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
            HStack(spacing: 20) {
                compactMetric("Input", value: MetricFormatting.tokens(tokens.input))
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
        guard let snapshot else {
            return ("Not connected", "circle", .secondary)
        }
        guard let issue = snapshot.issue else {
            return ("Current", "checkmark.circle.fill", .green)
        }
        switch issue {
        case .authentication, .insufficientPermissions, .keychainLocked:
            return ("Action needed", "exclamationmark.circle.fill", .red)
        case .partialData:
            return ("Partial", "circle.lefthalf.filled", .orange)
        case .rateLimited, .offline, .malformedResponse, .providerUnavailable:
            return ("Cached", "clock.badge.exclamationmark", .orange)
        }
    }

    private var capabilityText: String {
        if metadata.capabilities.contains(.officialCostHistory) {
            return "Cost · tokens · models"
        }
        if metadata.capabilities.contains(.balance) {
            return "Official balance"
        }
        return "Key validation"
    }

    private var emptyStateText: String {
        metadata.capabilities == [.credentialValidation]
            ? "Connect a key to verify access. Spend stays in Google AI Studio."
            : "Connect this provider to load official data."
    }

    private func updateText(_ snapshot: ProviderSnapshot) -> String {
        let timestamp = snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)
        guard let issue = snapshot.issue else { return "Updated \(timestamp)" }
        return "Last update \(timestamp) · \(issueText(issue))"
    }

    private func issueText(_ issue: ProviderIssue) -> String {
        switch issue {
        case .authentication: "Check credential"
        case .insufficientPermissions: "Insufficient permissions"
        case .rateLimited: "Rate limited"
        case .offline: "Offline"
        case .keychainLocked: "Keychain locked"
        case .malformedResponse: "Unexpected response"
        case .providerUnavailable: "Provider unavailable"
        case .partialData: "Partial report"
        }
    }

    private func costTotals(_ snapshot: ProviderSnapshot) -> [Money] {
        let totals = snapshot.buckets.reduce(into: [String: Decimal]()) { result, bucket in
            guard let cost = bucket.cost, cost.provenance == .official else { return }
            result[cost.value.currencyCode, default: 0] += cost.value.amount
        }
        return totals.keys.sorted().compactMap { currencyCode in
            try? Money(amount: totals[currencyCode, default: 0], currencyCode: currencyCode)
        }
    }

    private func tokenTotal(_ snapshot: ProviderSnapshot) -> (input: Int64, output: Int64)? {
        let values = snapshot.buckets.compactMap(\.tokenUsage)
        guard !values.isEmpty else { return nil }
        return (
            values.reduce(0) { $0 + $1.inputTokens },
            values.reduce(0) { $0 + $1.outputTokens }
        )
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
