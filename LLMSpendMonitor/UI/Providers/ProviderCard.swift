import SwiftUI

struct ProviderCard: View {
    let metadata: ProviderMetadata
    let snapshot: ProviderSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(metadata.displayName, systemImage: metadata.systemImageName)
                    .font(.headline)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            if let snapshot {
                metricContent(snapshot)
            } else {
                Text(emptyStateText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(metadata.externalLinks.filter { $0.kind == .dashboard || $0.kind == .status }, id: \.kind) { link in
                    Link(destination: link.url) {
                        Text(link.kind == .status ? "Status" : "Dashboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("provider.\(metadata.id.rawValue).card")
    }

    @ViewBuilder
    private func metricContent(_ snapshot: ProviderSnapshot) -> some View {
        let costs = costTotals(snapshot)
        ForEach(costs, id: \.currencyCode) { money in
            MetricRow(label: "Official cost", value: MetricFormatting.money(money))
        }

        ForEach(snapshot.balances, id: \.total.value.currencyCode) { balance in
            MetricRow(
                label: "Balance · \(balance.total.value.currencyCode)",
                value: MetricFormatting.money(balance.total.value)
            )
        }

        if let tokens = tokenTotal(snapshot) {
            MetricRow(label: "Input tokens", value: MetricFormatting.tokens(tokens.input))
            MetricRow(label: "Output tokens", value: MetricFormatting.tokens(tokens.output))
        }

        if costs.isEmpty && snapshot.balances.isEmpty && tokenTotal(snapshot) == nil {
            Text("Connected · financial metrics unavailable")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Text(updateText(snapshot))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var emptyStateText: String {
        metadata.capabilities == [.credentialValidation]
            ? "Connection validation only; spend and balance are unavailable."
            : "Connect this provider to load official data."
    }

    private var statusText: String {
        guard let snapshot else { return "Not connected" }
        return snapshot.issue == nil ? "Connected" : "Outdated"
    }

    private var statusColor: Color {
        guard let snapshot else { return .secondary }
        return snapshot.issue == nil ? .green : .orange
    }

    private func updateText(_ snapshot: ProviderSnapshot) -> String {
        let timestamp = snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)
        guard let issue = snapshot.issue else { return "Updated \(timestamp)" }
        return "Last success \(timestamp) · \(issueText(issue))"
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
        case .partialData: "Partial data"
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
}
