enum ProviderCapability: String, Codable, Hashable, Sendable {
    case officialCostHistory
    case estimatedCostHistory
    case tokenUsage
    case modelBreakdown
    case balance
    case credentialValidation
}
