import Foundation

struct Money: Codable, Equatable, Sendable {
    enum ValidationError: Error, Equatable {
        case invalidAmount
        case unsupportedCurrency(String)
    }

    let amount: Decimal
    let currencyCode: String

    init(amount: Decimal, currencyCode: String) throws {
        guard !amount.isNaN else { throw ValidationError.invalidAmount }

        let normalizedCurrency = currencyCode.uppercased()
        guard Self.isoCurrencyCodes.contains(normalizedCurrency) else {
            throw ValidationError.unsupportedCurrency(currencyCode)
        }

        self.amount = amount
        self.currencyCode = normalizedCurrency
    }

    private enum CodingKeys: String, CodingKey {
        case amount
        case currencyCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let amountString = try container.decode(String.self, forKey: .amount)
        let currencyCode = try container.decode(String.self, forKey: .currencyCode)

        guard let amount = Decimal(string: amountString, locale: Self.posixLocale) else {
            throw DecodingError.dataCorruptedError(
                forKey: .amount,
                in: container,
                debugDescription: "Money amount must be a base-10 decimal string."
            )
        }

        do {
            try self.init(amount: amount, currencyCode: currencyCode)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .currencyCode,
                in: container,
                debugDescription: "Money currency must be an ISO 4217 code."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var decimal = amount
        try container.encode(NSDecimalString(&decimal, Self.posixLocale), forKey: .amount)
        try container.encode(currencyCode, forKey: .currencyCode)
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let isoCurrencyCodes = Set(Locale.Currency.isoCurrencies.map(\.identifier))
}
