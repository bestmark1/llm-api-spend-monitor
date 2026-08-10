import Foundation
import SwiftUI

enum PlatformBalanceInput {
    enum ValidationError: Error {
        case invalidAmount
    }

    static func money(from input: String, currencyCode: String) throws -> Money {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard
            !trimmed.isEmpty,
            !trimmed.contains(where: { !$0.isNumber && $0 != "." && $0 != "," }),
            !(trimmed.contains(".") && trimmed.contains(",")),
            components.count <= 2,
            let integerPart = components.first,
            !integerPart.isEmpty,
            integerPart.count <= 12,
            integerPart.allSatisfy(\.isNumber),
            components.count == 1 || (
                !components[1].isEmpty
                    && components[1].count <= 2
                    && components[1].allSatisfy(\.isNumber)
            ),
            let amount = Decimal(
                string: normalized,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            amount >= 0
        else {
            throw ValidationError.invalidAmount
        }

        return try Money(amount: amount, currencyCode: currencyCode)
    }

    static func prefill(for balance: PlatformBalanceStatus) -> String {
        var amount = balance.remaining.amount
        return NSDecimalString(&amount, Locale(identifier: "en_US_POSIX"))
    }
}

struct PlatformBalanceEditor: View {
    @Environment(\.dismiss) private var dismiss

    let metadata: ProviderMetadata
    let currentBalance: PlatformBalanceStatus?
    let save: (Money) async -> Bool

    @State private var amountText: String
    @State private var isSaving = false
    @State private var saveFailed = false

    init(
        metadata: ProviderMetadata,
        currentBalance: PlatformBalanceStatus?,
        save: @escaping (Money) async -> Bool
    ) {
        self.metadata = metadata
        self.currentBalance = currentBalance
        self.save = save
        _amountText = State(initialValue: currentBalance.map(PlatformBalanceInput.prefill(for:)) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: metadata.systemImageName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ProviderVisualStyle.color(for: metadata.id))
                    .frame(width: 36, height: 36)
                    .background(
                        ProviderVisualStyle.color(for: metadata.id).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentBalance == nil ? "Add platform balance" : "Recalibrate platform balance")
                        .font(.headline)
                    Text(metadata.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(instructionText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let currentBalance {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remaining balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(MetricFormatting.money(currentBalance.remaining))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    Spacer()
                    billingLink
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            } else {
                billingLink
            }

            HStack(spacing: 8) {
                Text("$")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .font(.title2.monospacedDigit())
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Platform balance in US dollars")
                    .accessibilityIdentifier("balance.amount")
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(currentBalance == nil ? "Add Balance" : "Save Calibration") {
                    guard let money = parsedMoney else { return }
                    Task {
                        isSaving = true
                        saveFailed = false
                        if await save(money) {
                            dismiss()
                        } else {
                            saveFailed = true
                            isSaving = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(parsedMoney == nil || isSaving)
                .accessibilityIdentifier("balance.save")
            }

            if isSaving {
                ProgressView("Refreshing official costs…")
                    .controlSize(.small)
            } else if saveFailed {
                Text("Couldn’t load a complete cost report. Check the connection and try again.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("balance.saveError")
            }
        }
        .padding(24)
        .frame(width: 360)
        .accessibilityIdentifier("balance.editor")
    }

    private var parsedMoney: Money? {
        try? PlatformBalanceInput.money(from: amountText, currencyCode: "USD")
    }

    private var instructionText: String {
        if metadata.capabilities.contains(.officialCostHistory) {
            if currentBalance != nil {
                return "The calculated balance is prefilled. Open Billing, replace it with the exact platform balance, then save the new calibration."
            }
            return "Enter the exact balance currently shown in Billing. New official API costs will be deducted after every refresh."
        }
        return "Enter the balance currently shown in Billing. Update it again after using the platform."
    }

    @ViewBuilder
    private var billingLink: some View {
        if let url = metadata.externalLinks.first(where: { $0.kind == .billing })?.url {
            Link(destination: url) {
                Label("Open Billing", systemImage: "arrow.up.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("balance.openBilling")
        }
    }
}
