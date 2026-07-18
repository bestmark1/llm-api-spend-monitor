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
}

struct PlatformBalanceEditor: View {
    @Environment(\.dismiss) private var dismiss

    let metadata: ProviderMetadata
    let currentBalance: PlatformBalanceStatus?
    let save: (Money) -> Void

    @State private var amountText: String

    init(
        metadata: ProviderMetadata,
        currentBalance: PlatformBalanceStatus?,
        save: @escaping (Money) -> Void
    ) {
        self.metadata = metadata
        self.currentBalance = currentBalance
        self.save = save
        _amountText = State(initialValue: currentBalance.map {
            var amount = $0.remaining.amount
            return NSDecimalString(&amount, Locale(identifier: "en_US_POSIX"))
        } ?? "")
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
                    Text(currentBalance == nil ? "Add platform balance" : "Update platform balance")
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
                Button(currentBalance == nil ? "Add Balance" : "Update Balance") {
                    guard let money = parsedMoney else { return }
                    save(money)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(parsedMoney == nil)
                .accessibilityIdentifier("balance.save")
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
            return "Enter the balance currently shown in Billing. New official API costs will be deducted from this amount after every refresh."
        }
        return "Enter the balance currently shown in Billing. Update it again after using the platform."
    }
}
