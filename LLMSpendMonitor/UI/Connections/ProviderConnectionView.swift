import SwiftUI

struct ProviderConnectionView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @State private var isConfirmingDelete = false
    @State private var isConfirmingBillingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(viewModel.metadata.displayName, systemImage: viewModel.metadata.systemImageName)
                    .font(.headline)
                Spacer()
                Text(viewModel.connectionStatus.description)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Text(viewModel.metadata.credentialHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.requiresAPIEndpoint {
                TextField("OpenAI-compatible Base URL", text: $viewModel.draftEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(viewModel.metadata.displayName) API endpoint")
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).endpoint")

                if let apiEndpointHelp = viewModel.apiEndpointHelp {
                    Text(apiEndpointHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let apiEndpointError = viewModel.apiEndpointError {
                    Text(apiEndpointError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("connection.\(viewModel.id.rawValue).endpointError")
                }
            }

            SecureField("API key", text: $viewModel.draftSecret)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(viewModel.metadata.displayName) API key")
                .accessibilityIdentifier("connection.\(viewModel.id.rawValue).secret")

            HStack {
                Button(viewModel.saveButtonTitle, action: viewModel.saveOrReplace)
                    .disabled(!viewModel.canSave)
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).save")

                if viewModel.connectionStatus == .connected {
                    Button("Delete", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).delete")
                }

                Spacer()
            }

            if let resultMessage = viewModel.resultMessage {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).result")
            }


            if viewModel.supportsBillingCredentials {
                Divider()

                HStack(alignment: .firstTextBaseline) {
                    Text("Official billing access")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(viewModel.billingConnectionStatus.description)
                        .font(.caption)
                        .foregroundStyle(billingStatusColor)
                }

                Text("Use a RAM AccessKey limited to read-only BSS billing. Product Code must match Alibaba Cloud Model Studio in Billing Details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let billingURL = viewModel.metadata.externalLinks.first(where: { $0.kind == .billing })?.url {
                    Link("Open Billing Details", destination: billingURL)
                        .font(.caption)
                }

                TextField("AccessKey ID", text: $viewModel.draftBillingAccessKeyID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).billingAccessKeyID")

                SecureField("AccessKey Secret", text: $viewModel.draftBillingAccessKeySecret)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).billingAccessKeySecret")

                TextField("Billing Product Code", text: $viewModel.draftBillingProductCode)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).billingProductCode")

                HStack {
                    Button(
                        viewModel.billingConnectionStatus == .connected ? "Replace Billing" : "Save Billing",
                        action: viewModel.saveOrReplaceBillingCredentials
                    )
                    .disabled(!viewModel.canSaveBilling)
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).billingSave")

                    if viewModel.billingConnectionStatus == .connected {
                        Button("Delete Billing", role: .destructive) {
                            isConfirmingBillingDelete = true
                        }
                        .accessibilityIdentifier("connection.\(viewModel.id.rawValue).billingDelete")
                    }

                    Spacer()
                }

                if let billingResultMessage = viewModel.billingResultMessage {
                    Text(billingResultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("connection.\(viewModel.id.rawValue).billingResult")
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connection.\(viewModel.id.rawValue).card")
        .confirmationDialog(
            "Delete \(viewModel.metadata.displayName) credential?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete Credential", role: .destructive, action: viewModel.deleteCredential)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to enter the API key again to reconnect.")
        }
        .confirmationDialog(
            "Delete \(viewModel.metadata.displayName) billing credentials?",
            isPresented: $isConfirmingBillingDelete
        ) {
            Button("Delete Billing Credentials", role: .destructive, action: viewModel.deleteBillingCredentials)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Official billing history will no longer refresh.")
        }
    }

    private var statusColor: Color {
        switch viewModel.connectionStatus {
        case .connected:
            .green
        case .locked, .error:
            .orange
        case .notConnected:
            .secondary
        }
    }

    private var billingStatusColor: Color {
        switch viewModel.billingConnectionStatus {
        case .connected:
            .green
        case .locked, .error:
            .orange
        case .notConnected:
            .secondary
        }
    }
}
