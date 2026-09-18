import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProviderConnectionView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @State private var isConfirmingDelete = false
    @State private var isConfirmingBillingDelete = false
    @State private var isConfirmingUsageDelete = false

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

            if viewModel.id == .qwen {
                Link(
                    "How to create a Model Studio API key",
                    destination: URL(string: "https://help.aliyun.com/en/model-studio/get-api-key")!
                )
                .font(.caption)
                .accessibilityIdentifier("connection.qwen.modelStudioGuide")

                Link(
                    "How to create a RAM AccessKey pair",
                    destination: URL(string: "https://www.alibabacloud.com/help/en/ram/user-guide/create-an-accesskey-pair")!
                )
                .font(.caption)
                .accessibilityIdentifier("connection.qwen.ramGuide")
            }

            if viewModel.id == .xAI {
                Link(
                    "How to create a Management API key",
                    destination: URL(string: "https://docs.x.ai/developers/management-api-guide")!
                )
                .font(.caption)
                .accessibilityIdentifier("connection.xai.managementKeyGuide")

                Text("If IP restrictions are configured, allow the public IP used by this Mac. VPN or network changes may change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.id == .mistral {
                Link(
                    "How to create an Admin API key",
                    destination: URL(string: "https://docs.mistral.ai/admin/admin-api/authentication")!
                )
                .font(.caption)
                .accessibilityIdentifier("connection.mistral.adminKeyGuide")

                // Mistral publishes the Admin API as a Preview whose endpoints may
                // change. Saying so turns a future break into an explained one.
                Text("Mistral offers the Admin API as a preview on Enterprise plans and may change it, which can interrupt this connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.id == .openRouter {
                Link(
                    "How to create a Management API key",
                    destination: URL(string: "https://openrouter.ai/docs/guides/overview/auth/management-api-keys")!
                )
                .font(.caption)
                .accessibilityIdentifier("connection.openrouter.managementKeyGuide")

                // OpenRouter fixes a management key's expiry when it is created and
                // cannot extend it. Without this note, the day it lapses looks like
                // Spender breaking rather than the key running out.
                Text("An expiry set on the key cannot be extended; when it passes, Spender stops receiving credits until you add a new key. A management key can also create and delete your other OpenRouter keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

            SecureField(viewModel.apiKeyPlaceholder, text: $viewModel.draftSecret)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(viewModel.metadata.displayName) API key")
                .accessibilityIdentifier("connection.\(viewModel.id.rawValue).secret")

            if let apiKeyError = viewModel.apiKeyError {
                Text(apiKeyError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).secretError")
            }

            HStack {
                Button(viewModel.saveButtonTitle, action: viewModel.saveOrReplace)
                    .disabled(!viewModel.canSave)
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).save")

                if viewModel.canDeleteCredential {
                    Button("Delete", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).delete")
                }

                Spacer()
            }

            if let resultMessage = viewModel.resultMessage,
               resultMessage != viewModel.apiKeyError {
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

                Text("Create the AccessKey for a RAM user in the RAM console (Users → username → Credential → AccessKey). The secret is shown only once. The RAM user needs read-only billing permissions bss:DescribeAcccount and bss:QueryAccountBill — never the account key or full access. This version of Spender requires a QueryAccountBill ProductCode, but Alibaba publishes no reliable mapping from the User Center code to this request parameter — do not guess it. The balance covers the whole Alibaba Cloud account; billing spend may stay unavailable until the integration is updated.")
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

            if viewModel.supportsUsageCredentials {
                Divider()

                HStack(alignment: .firstTextBaseline) {
                    Text("Google usage access")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(viewModel.usageConnectionStatus.description)
                        .font(.caption)
                        .foregroundStyle(usageStatusColor)
                }

                Text("The API key is the same for Free and Paid Tier. To read official token usage, import a service-account JSON key from the same project with the Monitoring Viewer role. No Billing setup is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("connection.gemini.tierExplanation")

                Link(
                    "Open Google Cloud Service Accounts",
                    destination: URL(string: "https://console.cloud.google.com/iam-admin/serviceaccounts")!
                )
                .font(.caption)

                HStack {
                    Button("Connect Google usage…") {
                        chooseGeminiUsageCredentials()
                    }
                    .accessibilityIdentifier("connection.\(viewModel.id.rawValue).usageConnect")

                    if viewModel.usageConnectionStatus == .connected {
                        Button("Delete usage access", role: .destructive) {
                            isConfirmingUsageDelete = true
                        }
                        .accessibilityIdentifier("connection.\(viewModel.id.rawValue).usageDelete")
                    }

                    Spacer()
                }

                if let usageResultMessage = viewModel.usageResultMessage {
                    Text(usageResultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("connection.\(viewModel.id.rawValue).usageResult")
                }
            }
        }
        .padding(12)
        .background {
            GlassSurface(cornerRadius: 12, prominence: .secondary)
        }
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
        .confirmationDialog(
            "Delete \(viewModel.metadata.displayName) usage access?",
            isPresented: $isConfirmingUsageDelete
        ) {
            Button(
                "Delete Usage Access",
                role: .destructive,
                action: viewModel.deleteGeminiUsageCredentials
            )
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Gemini token and model usage will no longer refresh.")
        }
    }

    private func chooseGeminiUsageCredentials() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Connect Google usage"
        panel.message = "Choose the service-account JSON key for the Gemini project."
        panel.prompt = "Connect"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                viewModel.saveGeminiUsageCredentials(try Data(contentsOf: url))
            } catch {
                viewModel.reportGeminiUsageImportFailure()
            }
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

    private var usageStatusColor: Color {
        switch viewModel.usageConnectionStatus {
        case .connected:
            .green
        case .locked, .error:
            .orange
        case .notConnected:
            .secondary
        }
    }
}
