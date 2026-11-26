#if !APP_STORE
import SwiftUI

/// Shown once per agent, before its first rating.
struct EfficiencyConsentSheet: View {
    let agent: AgentClient
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rate with \(agent.name)?")
                .font(.headline)
            Text("This snippet's code, and the code of the snippets it connects to, will be sent to \(agent.name)'s provider, using your own account and tokens.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
#endif
