import SwiftUI
import MessageUI

/// SwiftUI wrapper for MFMailComposeViewController
struct MailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let recipients: [String]
    let ccRecipients: [String]
    let subject: String
    let body: String
    let isHTML: Bool
    let onComplete: (MFMailComposeResult) -> Void

    init(
        recipients: [String],
        ccRecipients: [String] = [],
        subject: String,
        body: String,
        isHTML: Bool = false,
        onComplete: @escaping (MFMailComposeResult) -> Void
    ) {
        self.recipients = recipients
        self.ccRecipients = ccRecipients
        self.subject = subject
        self.body = body
        self.isHTML = isHTML
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mailVC = MFMailComposeViewController()
        mailVC.mailComposeDelegate = context.coordinator
        mailVC.setToRecipients(recipients)
        if !ccRecipients.isEmpty {
            mailVC.setCcRecipients(ccRecipients)
        }
        mailVC.setSubject(subject)
        mailVC.setMessageBody(body, isHTML: isHTML)
        return mailVC
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView

        init(_ parent: MailComposeView) {
            self.parent = parent
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            parent.onComplete(result)
            parent.dismiss()
        }
    }
}

/// Check if device can send email
extension MailComposeView {
    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }
}

/// View modifier for presenting mail compose
struct MailComposeModifier: ViewModifier {
    @Binding var isPresented: Bool
    let emailDetails: EmailDraftDetails?
    let onComplete: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if let details = emailDetails {
                    MailComposeView(
                        recipients: details.recipients,
                        ccRecipients: details.ccRecipients,
                        subject: details.subject,
                        body: details.body
                    ) { result in
                        let sent = result == .sent
                        onComplete(sent)
                    }
                }
            }
    }
}

extension View {
    func mailCompose(
        isPresented: Binding<Bool>,
        details: EmailDraftDetails?,
        onComplete: @escaping (Bool) -> Void
    ) -> some View {
        modifier(MailComposeModifier(
            isPresented: isPresented,
            emailDetails: details,
            onComplete: onComplete
        ))
    }
}
