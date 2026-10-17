import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// The license agreement, asked on first launch: the terms in a scrolling
/// well, Disagree (quits) and Agree (records the answer and carries on to the
/// welcome tour).
struct LicenseAgreementPrompt: View {
    @Environment(LicenseAgreement.self) private var agreement

    private enum Layout {
        static let size = CGSize(width: 540, height: 620)
    }

    var body: some View {
        VStack(spacing: DSToken.Spacing.md) {
            header

            ScrollView {
                Text(LicenseAgreement.displayText)
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSToken.Spacing.md)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: DSToken.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DSToken.Radius.md, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            }

            buttons
        }
        .padding(DSToken.Spacing.lg)
        .frame(width: Layout.size.width, height: Layout.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        // There is no way past this but an answer.
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(spacing: DSToken.Spacing.xs) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("Snippets License Agreement")
                .font(.system(size: 20, weight: .bold))
            Text("Snippets is free to use, at home and at work.\nPlease read the terms and agree to them to continue.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    private var buttons: some View {
        HStack(spacing: DSToken.Spacing.sm) {
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Disagree")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 140)
            }
            .buttonStyle(.glass)
            .help("Quit Snippets without agreeing")

            Button(action: agree) {
                Text("Agree")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 140)
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
    }

    private func agree() {
        agreement.accept()
        #if canImport(AppKit)
        // Held back at launch until now: nothing of the app runs from the
        // menu bar before the terms are accepted.
        MenuBarController.shared.install()
        ClipboardMonitor.shared.start()
        #endif
    }
}

/// Puts the license agreement in front of everything else on first launch.
/// The welcome tour waits for it (see `OnboardingTour`) and starts once the
/// agreement's sheet has gone.
private struct LicenseAgreementGate: ViewModifier {
    @Environment(LicenseAgreement.self) private var agreement
    @Environment(Onboarding.self) private var onboarding

    func body(content: Content) -> some View {
        @Bindable var agreement = agreement
        content
            // Presented from `.task`, after the window's first layout pass,
            // for the same reason the tour is.
            .task { agreement.presentIfNeeded() }
            .sheet(isPresented: $agreement.isPresented, onDismiss: {
                if agreement.isAccepted { onboarding.presentIfNeeded() }
            }) {
                LicenseAgreementPrompt()
            }
    }
}

extension View {
    /// Asks for the license agreement before anything else on first launch.
    /// Attach once, at the app's root, outside `onboardingTour()`.
    func licenseAgreementGate() -> some View {
        modifier(LicenseAgreementGate())
    }
}
