import SwiftUI

struct ProviderConnectionView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @State private var isConfirmingDelete = false

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
}
