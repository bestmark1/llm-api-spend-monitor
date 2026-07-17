enum ProviderCapability: String, Codable, Hashable, Sendable {
    case officialCostHistory
    case tokenUsage
    case modelBreakdown
    case balance
    case credentialValidation
}
