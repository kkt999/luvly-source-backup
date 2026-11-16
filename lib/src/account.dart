import '../recommendations/recommendation_screen.dart';
import 'package:flutter/material.dart';
import '../promotions/promotion_screen.dart';
import 'design.dart';
import 'model.dart';
import 'auth_service.dart';
import 'account_terms.dart';
import 'password_policy.dart';
import 'malaysia_phone_field.dart';
import 'email_typo_suggestion.dart';
import '../shortlist/shortlist_widgets.dart';
import 'google_account.dart';
import 'calendar_screen.dart';
import 'dresses.dart';
import 'commerce.dart';
import '../profile/profile_photo.dart';
import '../profile/my_rentals.dart';
import '../reviews/review_screen.dart';
import '../support/assistant_launcher.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          gap(12),
          const Text(
            'Luvly',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'LuvlySerif',
              fontStyle: FontStyle.italic,
              fontSize: 48,
              color: rose,
            ),
          ),
          gap(6),
          const Text(
            'YOUR FOREVER STARTS HERE',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, letterSpacing: 2.8, color: muted),
          ),
          gap(24),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(150),
              bottom: Radius.circular(20),
            ),
            child: Image.asset(
              'assets/images/bridal_welcome_hd.png',
              height: 290,
              width: double.infinity,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
          gap(26),
          Text(
            'Find your\nforever gown.',
            textAlign: TextAlign.center,
            style: Theme.of(c).textTheme.headlineLarge,
          ),
          gap(12),
          const Text(
            'A little inspiration. A perfect fit.\nA bridal journey that is beautifully yours.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, height: 1.6),
          ),
          gap(26),
          Primary('Get started', () => go(c, const AuthScreen(register: true))),
          gap(8),
          TextButton(
            onPressed: () => go(c, const AuthScreen()),
            child: const Text('I already have an account'),
          ),
          gap(12),
          Center(
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF75676B),
                minimumSize: const Size(120, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontFamily: 'LuvlySans',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  decoration: TextDecoration.underline,
                ),
              ),
              onPressed: () => go(c, const AccountTermsScreen(readOnly: true)),
              child: const Text('Terms & privacy'),
            ),
          ),
        ],
      ),
    ),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.register = false});
  final bool register;
  @override
  State<AuthScreen> createState() => _AuthState();
}

class _AuthState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final repeatField = GlobalKey<FormFieldState<String>>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(),
      phone = TextEditingController(),
      repeat = TextEditingController();
  bool hidden = true, consent = false;

  Future<void> reviewTerms() async {
    FocusScope.of(context).unfocus();
    final accepted = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AccountTermsScreen()));
    if (mounted && accepted == true) setState(() => consent = true);
  }

  @override
  void dispose() {
    for (final c in [email, password, name, phone, repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final session = AccountScope.maybeOf(c);
    final busy = session?.busy ?? false;
    return PopScope(
      canPop: !busy,
      child: PageFrame(
        title: widget.register ? 'Create account' : 'Welcome back',
        child: PageList(
          children: [
            gap(20),
            Text(
              widget.register
                  ? 'Your bridal journey\nbegins here.'
                  : 'A little closer to\nyour dream day.',
              style: Theme.of(c).textTheme.headlineLarge,
            ),
            gap(10),
            const Text(
              'Welcome to Luvly, your personal bridal companion.',
              style: TextStyle(color: muted),
            ),
            gap(28),
            Form(
              key: form,
              child: AutofillGroup(
                child: Column(
                  children: [
                    if (widget.register) ...[
                      TextFormField(
                        controller: name,
                        enabled: !busy,
                        autofillHints: const [AutofillHints.name],
                        textCapitalization: TextCapitalization.words,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          errorMaxLines: 6,
                        ),
                        validator: validateName,
                      ),
                      gap(),
                    ],
                    TextFormField(
                      controller: email,
                      enabled: !busy,
                      autocorrect: false,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                      ),
                      validator: validateEmail,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                    if (widget.register)
                      EmailTypoSuggestion(controller: email, enabled: !busy),
                    gap(),
                    if (widget.register) ...[
                      MalaysiaPhoneField(controller: phone, enabled: !busy),
                      gap(),
                    ],
                    TextFormField(
                      controller: password,
                      enabled: !busy,
                      obscureText: hidden,
                      autocorrect: false,
                      enableSuggestions: false,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onChanged: (_) {
                        if (repeat.text.isNotEmpty) {
                          repeatField.currentState?.validate();
                        }
                      },
                      autofillHints: [
                        widget.register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        errorMaxLines: 6,
                        suffixIcon: IconButton(
                          tooltip: hidden ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => hidden = !hidden),
                          icon: Icon(
                            hidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (v) => widget.register
                          ? validateNewPassword(v)
                          : ((v ?? '').isEmpty ? 'Enter your password' : null),
                    ),
                    gap(),
                    if (widget.register) ...[
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: password,
                        builder: (_, value, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final rule in passwordRequirements(
                              value.text,
                            ).entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Icon(
                                      rule.value
                                          ? Icons.check_circle_outline
                                          : Icons.radio_button_unchecked,
                                      size: 16,
                                      color: rule.value
                                          ? Colors.green.shade700
                                          : muted,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        rule.key,
                                        semanticsLabel:
                                            '${rule.value ? "Met" : "Not met"}: ${rule.key}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      gap(),
                      TextFormField(
                        key: repeatField,
                        controller: repeat,
                        enabled: !busy,
                        obscureText: hidden,
                        autocorrect: false,
                        enableSuggestions: false,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          errorMaxLines: 6,
                        ),
                        validator: (v) => (v ?? '').isEmpty
                            ? 'Confirm your password'
                            : v != password.text
                            ? 'Passwords do not match'
                            : null,
                      ),
                      gap(),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: consent,
                        onChanged: busy
                            ? null
                            : (v) {
                                if (consent) {
                                  setState(() => consent = false);
                                } else {
                                  reviewTerms();
                                }
                              },
                        title: const Text(
                          'I agree to the Terms & Conditions and account privacy notice.',
                          style: TextStyle(fontSize: 12),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      TextButton(
                        onPressed: busy ? null : reviewTerms,
                        child: const Text('Read Terms & Conditions'),
                      ),
                      gap(),
                    ] else
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: busy
                              ? null
                              : () => go(c, const ResetPasswordScreen()),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    if (session?.error != null) ...[
                      Text(
                        session!.error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      gap(),
                    ],
                    Primary(
                      busy
                          ? 'Please wait…'
                          : (widget.register ? 'Create account' : 'Sign in'),
                      busy || (widget.register && !consent)
                          ? null
                          : () async {
                              if (!form.currentState!.validate()) return;
                              if (widget.register && !consent) {
                                toast(
                                  c,
                                  'Please read and accept the Terms & Conditions.',
                                );
                                return;
                              }
                              if (session == null) {
                                toast(
                                  c,
                                  'Account service unavailable. Please restart the app.',
                                );
                                return;
                              }
                              FocusScope.of(c).unfocus();
                              if (widget.register) {
                                await session.register(
                                  email.text.trim(),
                                  password.text,
                                  name.text.trim(),
                                  phone.text.trim(),
                                );
                              } else {
                                await session.signIn(
                                  email.text.trim(),
                                  password.text,
                                );
                              }
                              // AccountSession, not the form, decides whether protected pages may open.
                            },
                    ),
                    if (session?.supportsGoogle == true) ...[
                      gap(),
                      const Text('or'),
                      gap(),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () async {
                                // Google can create a new Firebase account, even on
                                // the sign-in screen. Review terms before continuing.
                                if (!consent) await reviewTerms();
                                if (!mounted || !consent) return;
                                await session!.signInGoogle();
                              },
                        child: const Text('Continue with Google'),
                      ),
                      const Text(
                        'Google login does not grant access to your Gmail or calendar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                    if (busy) ...[gap(), const LinearProgressIndicator()],
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(c).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AuthScreen(register: !widget.register),
                              ),
                            ),
                      child: Text(
                        widget.register
                            ? 'Already have an account? Sign in'
                            : 'New to Luvly? Create account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.account});

  final AccountIdentity? account;
  @override
  State<ResetPasswordScreen> createState() => _ResetState();
}

class _ResetState extends State<ResetPasswordScreen> {
  final form = GlobalKey<FormState>(), email = TextEditingController();
  bool sent = false, busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    final gateway = AccountScope.of(context).gateway;
    final account = widget.account;
    if (account == null) {
      if (form.currentState?.validate() != true) return;
    } else {
      final current = gateway.current;
      if (current == null ||
          current.uid != account.uid ||
          current.email != account.email ||
          !current.hasPassword) {
        setState(
          () => error =
              'Your sign-in changed. Reopen this page from your profile.',
        );
        return;
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await gateway.resetPassword(account?.email ?? email.text.trim());
      if (mounted) setState(() => sent = true);
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => PageFrame(
    title: 'Reset password',
    child: PageList(
      children: [
        gap(38),
        const CircleAvatar(
          radius: 40,
          backgroundColor: blush,
          child: Icon(Icons.lock_reset, color: rose, size: 36),
        ),
        gap(24),
        Text(
          sent
              ? 'Check your inbox'
              : widget.account == null
              ? 'Forgot your password?'
              : 'Change your Luvly password',
          textAlign: TextAlign.center,
          style: Theme.of(c).textTheme.headlineMedium,
        ),
        gap(),
        Text(
          widget.account == null
              ? sent
                    ? 'If an account exists for this email, you will receive a password reset link. Check your spam folder too.'
                    : 'Enter your account email and we will help you reset your password.'
              : sent
              ? 'Open the reset link in your email to choose a new password. Check your spam folder if it hasn’t arrived.'
              : 'We’ll email a reset link to your sign-in address. Open the link to choose a new password.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
        gap(28),
        if (widget.account case final account?)
          SelectableText(account.email, textAlign: TextAlign.center)
        else if (!sent)
          Form(
            key: form,
            child: TextFormField(
              controller: email,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Email address'),
              keyboardType: TextInputType.emailAddress,
              validator: validateEmail,
            ),
          ),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.redAccent)),
        gap(),
        Primary(
          sent
              ? (widget.account == null ? 'Back to login' : 'Back to profile')
              : (busy ? 'Sending…' : 'Send reset link'),
          busy
              ? null
              : () {
                  if (sent) {
                    Navigator.pop(c);
                  } else {
                    submit();
                  }
                },
        ),
      ],
    ),
  );
}

class AccountRecoveryScreen extends StatelessWidget {
  const AccountRecoveryScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final session = AccountScope.of(c);
    return PageFrame(
      title: 'Account connection',
      child: PageList(
        children: [
          gap(32),
          const Text(
            'Your account is signed in, but your profile could not be loaded. Check your connection and retry. You do not need to register again.',
          ),
          gap(),
          Text(session.error ?? 'Please retry.'),
          gap(),
          Primary('Retry', session.busy ? null : session.retry),
          TextButton(
            onPressed: session.busy ? null : session.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});
  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileState();
}

class _CompleteProfileState extends State<CompleteProfileScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), phone = TextEditingController();
  bool loaded = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      final s = AccountScope.of(context);
      name.text = s.pendingName;
      phone.text = malaysiaNationalInput(s.pendingPhone);
      loaded = true;
    }
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final s = AccountScope.of(c);
    return PageFrame(
      title: 'Complete your profile',
      child: PageList(
        children: [
          const Text(
            'Your login already exists. Add your contact details to finish setting up your bridal profile.',
          ),
          gap(),
          Text(s.identity?.email ?? ''),
          gap(),
          Form(
            key: form,
            child: Column(
              children: [
                TextFormField(
                  controller: name,
                  enabled: !s.busy,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    errorMaxLines: 6,
                  ),
                  validator: validateName,
                ),
                gap(),
                MalaysiaPhoneField(controller: phone, enabled: !s.busy),
              ],
            ),
          ),
          gap(),
          const Text(
            'These details are stored securely with your Luvly account.',
          ),
          gap(),
          Primary(
            s.busy ? 'Saving…' : 'Save profile',
            s.busy
                ? null
                : () {
                    if (form.currentState!.validate()) {
                      s.completeProfile(name.text, phone.text);
                    }
                  },
          ),
          TextButton(
            onPressed: s.busy ? null : s.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c);
    final saved = ShortlistScope.maybeOf(c);
    final session = AccountScope.maybeOf(c);
    final current = session?.gateway.current;
    final passwordAccount =
        current != null &&
            current.uid == m.accountId &&
            current.hasPassword &&
            current.email.isNotEmpty
        ? current
        : null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: PageList(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  ProfilePhotoAvatar(
                    uid: m.accountId,
                    radius: 30,
                    editable: m.accountId != null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.name, style: Theme.of(c).textTheme.titleLarge),
                        gap(4),
                        Text(
                          m.email,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _ProfileGroup('Your details', [
              _ProfileRow(
                Icons.person_outline,
                'Personal profile',
                'Photo and contact details',
                () => go(c, const EditProfileScreen()),
              ),
              _ProfileRow(
                Icons.straighten,
                'Body information',
                'Measurements and fit preferences',
                () => go(c, const MeasurementsScreen()),
              ),
            ]),
            _ProfileGroup('Your bridal plans', [
              if (m.accountId != null)
                _ProfileRow(
                  Icons.checkroom,
                  'My rentals & packages',
                  'Your selections, dates and progress',
                  () => go(c, const MyRentalsScreen()),
                ),
              _ProfileRow(
                Icons.payments_outlined,
                'Payments & receipts',
                'Balances and payment history',
                () => go(c, const PaymentsScreen()),
              ),
              _ProfileRow(
                Icons.favorite_border,
                'My shortlist',
                m.accountId == null || saved == null
                    ? '${m.shortlist.length} favourite dresses'
                    : saved.loading
                    ? 'Loading your favourites…'
                    : saved.error != null
                    ? 'Open to retry loading'
                    : '${saved.ids.length} saved gowns',
                () => go(c, const ShortlistScreen()),
              ),
              _ProfileRow(
                Icons.camera_alt_outlined,
                'Try-on history',
                'Looks saved on this phone',
                () => go(c, const TryOnHistoryScreen()),
              ),
              if (m.accountId != null)
                _ProfileRow(
                  Icons.rate_review_outlined,
                  'My reviews',
                  'Ratings, photos and videos',
                  () => go(c, const ReviewsScreen(mine: true)),
                ),
            ]),
            if (session?.supportsGoogle == true || m.accountId != null)
              _ProfileGroup('Account & connections', [
                if (passwordAccount != null)
                  _ProfileRow(
                    Icons.lock_reset,
                    'Reset password',
                    'Email a link to change your Luvly password',
                    () => go(c, ResetPasswordScreen(account: passwordAccount)),
                  ),
                if (session?.supportsGoogle == true)
                  _ProfileRow(
                    Icons.link,
                    'Google account',
                    'Manage your Google sign-in',
                    () => go(c, const GoogleAccountScreen()),
                  ),
                if (m.accountId != null)
                  _ProfileRow(
                    Icons.calendar_month_outlined,
                    'Google Calendar',
                    'Appointment calendar connection',
                    () => go(c, const CalendarScreen()),
                  ),
              ]),
            _ProfileGroup('Privacy & information', [
              _ProfileRow(
                Icons.privacy_tip_outlined,
                'Terms & privacy',
                'Your information, permissions and choices',
                () => go(c, const AccountTermsScreen(readOnly: true)),
              ),
            ]),
            gap(24),
            OutlinedButton.icon(
              onPressed: () async {
                if (await confirm(
                      c,
                      'Sign out?',
                      'You will need to sign in again to access your account.',
                      action: 'Sign out',
                    ) &&
                    c.mounted) {
                  await AccountScope.of(c).signOut();
                }
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile-only compact rows; other screens keep their existing MenuTile design.
class _ProfileGroup extends StatelessWidget {
  const _ProfileGroup(this.title, this.rows);
  final String title;
  final List<Widget> rows;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: muted),
        ),
      ),
      Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: line),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.only(left: 52),
                  child: Divider(height: 1, color: line),
                ),
              rows[i],
            ],
          ],
        ),
      ),
    ],
  );
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 68),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: rose, size: 21),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: muted),
          ],
        ),
      ),
    ),
  );
}

class GoogleAccountScreen extends StatefulWidget {
  const GoogleAccountScreen({super.key});
  @override
  State<GoogleAccountScreen> createState() => _GoogleAccountState();
}

class _GoogleAccountState extends State<GoogleAccountScreen> {
  bool busy = false;
  String? message;
  @override
  Widget build(BuildContext context) {
    final accountGateway = AccountScope.of(context).gateway;
    final gateway = accountGateway as GoogleAccountGateway;
    final account = accountGateway.current;
    return PageFrame(
      title: 'Google account',
      child: PageList(
        children: [
          const Text(
            'Link Google to sign in to this same Luvly account. Your existing profile, appointments and orders stay together. This does not connect Gmail or Google Calendar.',
          ),
          gap(),
          Text(
            gateway.googleLinked ? 'Google is linked' : 'Google is not linked',
          ),
          if (gateway.googleLinked && account?.hasPassword == false) ...[
            gap(),
            const Text(
              'You sign in with Google. To change that password, use your Google Account settings.',
            ),
          ],
          if (message != null) ...[gap(), Text(message!)],
          gap(),
          Primary(
            busy ? 'Connecting…' : 'Link Google account',
            busy || gateway.googleLinked
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      message = null;
                    });
                    try {
                      await gateway.linkGoogle();
                      if (mounted) {
                        setState(() => message = 'Google linked successfully.');
                      }
                    } catch (error) {
                      if (mounted) {
                        setState(() => message = accountError(error));
                      }
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfileScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  ({String name, String phone})? _saved;
  String? _owner, _saveError;
  bool saving = false, _confirmingDiscard = false, _allowExit = false;

  ({String name, String phone}) _values(String name, String phone) => (
    name: normalizeContactName(name),
    phone: normalizeMalaysiaPhone(phone) ?? phone.trim(),
  );

  bool get _dirty => _saved != null && _saved != _values(name.text, phone.text);

  BrideProfile? _profileFor(AccountSession? session, String? owner) =>
      owner != null && session?.identity?.uid == owner
      ? session?.profile
      : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final model = AppScope.of(context);
    final account = AccountScope.maybeOf(context);
    final sameOwner = _saved != null && _owner == model.accountId;
    if (sameOwner && (_dirty || saving)) return;

    final profile = _profileFor(account, model.accountId);
    final savedName = profile?.name ?? model.name;
    final savedPhone = profile?.phone ?? model.phone;
    final values = _values(savedName, savedPhone);
    if (sameOwner && values == _saved) return;

    _owner = model.accountId;
    _saved = values;
    name.text = savedName;
    phone.text = malaysiaNationalInput(savedPhone);
    _saveError = null;
    _allowExit = false;
    saving = false;
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  void _edited(String _) => setState(() => _saveError = null);

  void _leaveEditor() {
    if (!Navigator.canPop(context)) return;
    setState(() => _allowExit = true);
    // Let PopScope observe the saved/discarded draft before leaving the route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.isCurrentOf(context) == true) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _confirmDiscard() async {
    if (saving || !_dirty || _allowExit || _confirmingDiscard) return;
    _confirmingDiscard = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('You have unsaved contact changes.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard changes'),
            ),
          ],
        ),
      );
      if (discard == true && mounted) _leaveEditor();
    } finally {
      _confirmingDiscard = false;
    }
  }

  Future<void> save() async {
    if (saving ||
        !_dirty ||
        _allowExit ||
        !(form.currentState?.validate() ?? false)) {
      return;
    }
    final session = AccountScope.maybeOf(context);
    final owner = _owner;
    final profile = _profileFor(session, owner);
    if (session == null || profile == null) return;

    final draft = BrideProfile(
      name: name.text,
      phone: phone.text,
      notes: profile.notes,
      contact: profile.contact,
      membership: profile.membership,
      points: profile.points,
    );
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      _saveError = null;
    });
    try {
      await session.updateProfile(draft);
      if (!mounted || _owner != owner || session.identity?.uid != owner) return;
      setState(() {
        _saved = _values(draft.name, draft.phone);
        saving = false;
      });
      toast(context, 'Profile updated successfully.');
      _leaveEditor();
    } catch (e) {
      if (mounted && _owner == owner) {
        setState(() {
          saving = false;
          _saveError = accountError(e);
        });
      }
    }
  }

  Widget _section(String title, ThemeData theme) => Semantics(
    header: true,
    child: Text(title, style: theme.textTheme.titleMedium),
  );

  @override
  Widget build(BuildContext c) {
    final model = AppScope.of(c);
    final session = AccountScope.maybeOf(c);
    final profile = _profileFor(session, model.accountId);
    final identity = session?.identity;
    final email = identity != null && identity.uid == model.accountId
        ? identity.email.trim()
        : '';
    final theme = Theme.of(c);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final editable = profile != null && !saving && !_allowExit;

    return PopScope<void>(
      canPop: !saving && (!_dirty || _allowExit),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: AssistantExclusion(
        child: PageFrame(
          title: 'Personal profile',
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        if (model.accountId != null &&
                            session?.phase == AccountPhase.loading)
                          const LinearProgressIndicator(
                            semanticsLabel: 'Loading personal information',
                          ),
                        Center(
                          child: IgnorePointer(
                            ignoring: saving,
                            child: ProfilePhotoAvatar(
                              uid: model.accountId,
                              radius: 46,
                              editable: model.accountId != null,
                              showLabel: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _section('Personal information', theme),
                        const SizedBox(height: 10),
                        Theme(
                          data: theme.copyWith(
                            inputDecorationTheme: theme.inputDecorationTheme
                                .copyWith(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                ),
                          ),
                          child: AutofillGroup(
                            child: Form(
                              key: form,
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: name,
                                    enabled: editable,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [AutofillHints.name],
                                    autovalidateMode:
                                        AutovalidateMode.onUserInteraction,
                                    decoration: const InputDecoration(
                                      labelText: 'Name',
                                      errorMaxLines: 6,
                                    ),
                                    validator: validateName,
                                    onChanged: _edited,
                                  ),
                                  const SizedBox(height: 10),
                                  MalaysiaPhoneField(
                                    controller: phone,
                                    enabled: editable,
                                    compact: true,
                                    onChanged: _edited,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _section('Account information', theme),
                        const SizedBox(height: 8),
                        Container(
                          decoration: CustomerUi.tintedCard,
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.mail_outline,
                                size: 18,
                                color: secondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sign-in email',
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 3),
                                    if (email.isEmpty)
                                      const Text('Email unavailable')
                                    else
                                      SelectableText(email),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Used to sign in to Luvly.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: secondary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.lock_outline,
                                size: 17,
                                color: secondary,
                                semanticLabel: 'Read only',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: CustomerUi.divider),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_saveError case final error?)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  error,
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          FilledButton(
                            onPressed: editable && _dirty ? save : null,
                            child: saving
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Flexible(child: Text('Saving…')),
                                    ],
                                  )
                                : const Text('Save changes'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MeasurementsScreen extends StatelessWidget {
  const MeasurementsScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const BridalPreferencesEditor(measurementsOnly: true);
}

class BodyScanScreen extends StatelessWidget {
  const BodyScanScreen({super.key});
  @override
  Widget build(BuildContext c) => PageFrame(
    title: 'Body scan preview',
    child: PageList(
      children: [
        gap(),
        Surface(
          color: blush,
          child: const SizedBox(
            height: 260,
            width: double.infinity,
            child: Icon(Icons.accessibility_new, size: 160, color: rose),
          ),
        ),
        const Section('Get ready for your scan'),
        for (final s in [
          'Stand 2–3 metres from the camera',
          'Keep your whole body in the frame',
          'Wear fitted clothing',
          'Choose a well-lit, plain background',
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle_outline, color: rose),
            title: Text(s),
          ),
        const DemoNote(
          text:
              'Camera and MediaPipe integration are planned for a later stage. This preview does not capture photos or calculate measurements.',
        ),
        Primary('Enter measurements manually', () => Navigator.pop(c)),
      ],
    ),
  );
}

// Compatibility aliases for old preview routes; loyalty redemption is retired.
class MembershipScreen extends StatelessWidget {
  const MembershipScreen({super.key});
  @override
  Widget build(BuildContext c) =>
      OffersScreen(preview: AppScope.of(c).accountId == null);
}

class LoyaltyScreen extends StatelessWidget {
  const LoyaltyScreen({super.key});
  @override
  Widget build(BuildContext c) =>
      OffersScreen(preview: AppScope.of(c).accountId == null);
}
