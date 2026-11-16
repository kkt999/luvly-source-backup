# Free Gmail appointment notifications

Google login/Calendar and sending mail are separate permissions. This sender uses Gmail SMTP, not inbox access. App passwords require Google Account 2-Step Verification and may be unavailable for some managed or protected accounts.

1. Sign into the Gmail account you want customers to see as the sender.
2. Enable 2-Step Verification in your Google Account, then open https://myaccount.google.com/apppasswords and create an app password named `Luvly university project`.
3. Copy `secrets/mail-config.example.json` to `secrets/mail-config.json`. Fill email and appPassword locally and set enabled to true. Do not paste the password into chat, screenshots or source control.
4. Restart the existing backend (do not restart the Cloudflare tunnel). A newly created booking queues its confirmation automatically. Cancellations and completed visits also queue notifications. Calendar continues independently for connected users.

No sender is configured by default. Missing/disabled configuration leaves mail Queued; appointment booking still works. Sent means Gmail accepted the message, not confirmed inbox delivery. Ambiguous SMTP failures remain ReviewRequired, not blindly resent. Superseded states are skipped. Never publish either secrets or appointmentMail (recipient data) to clients.

For university-project volumes only; personal Gmail has sending limits. No paid hosting or Gmail API subscription is enabled.

Official references: https://support.google.com/accounts/answer/185833 and https://nodemailer.com/guides/using-gmail
