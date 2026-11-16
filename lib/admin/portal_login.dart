import 'package:flutter/material.dart';
import '../src/auth_service.dart';
import 'design.dart';
import 'model.dart';
import 'shell.dart' show PortalShell;
import 'portal_auth.dart';

class PortalEntry extends StatelessWidget {
  const PortalEntry({super.key, required this.session});
  final PortalSession session;

  @override
  Widget build(BuildContext context) {
    if (session.phase == PortalPhase.signedOut) {
      return PortalLoginScreen(session: session);
    }
    if (session.phase == PortalPhase.ready) {
      return StaffWorkspace(session: session);
    }
    final checking = session.phase == PortalPhase.checking;
    final denied = session.phase == PortalPhase.denied;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Panel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (checking)
                    const CircularProgressIndicator()
                  else
                    Icon(
                      denied ? Icons.lock_outline : Icons.cloud_off_outlined,
                      size: 40,
                      color: rose,
                    ),
                  gap(24),
                  Text(
                    checking
                        ? 'Checking workspace access…'
                        : denied
                        ? 'Staff access required'
                        : 'Unable to verify access',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  gap(12),
                  Text(
                    checking
                        ? 'Please wait while we verify your account.'
                        : denied
                        ? 'This account does not have active staff or manager access. Bride accounts use the Luvly mobile app. Contact your administrator if you need staff access.'
                        : session.error ??
                              'Check your connection and try again.',
                    textAlign: TextAlign.center,
                  ),
                  if (session.identity != null) ...[
                    gap(12),
                    Text(session.identity!.email, textAlign: TextAlign.center),
                  ],
                  gap(24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (!checking)
                        FilledButton(
                          onPressed: session.busy ? null : session.retry,
                          child: const Text('Check again'),
                        ),
                      TextButton(
                        onPressed: session.busy ? null : session.signOut,
                        child: const Text('Sign out'),
                      ),
                    ],
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

class PortalLoginScreen extends StatefulWidget {
  const PortalLoginScreen({super.key, required this.session});
  final PortalSession session;
  @override
  State<PortalLoginScreen> createState() => _PortalLoginScreenState();
}

class _PortalLoginScreenState extends State<PortalLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _obscure = true, _reset = false;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.session.busy || !_form.currentState!.validate()) return;
    setState(() => _notice = null);
    if (_reset) {
      final sent = await widget.session.resetPassword(_email.text);
      if (mounted && sent) {
        setState(
          () => _notice =
              'If an account exists for this email, you’ll receive a password-reset link. Check your inbox and spam folder.',
        );
      }
    } else {
      await widget.session.signIn(_email.text, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final form = Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 500 ? 24 : 40),
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LUVLY · STAFF & MANAGER',
                style: TextStyle(
                  color: rose,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              gap(24),
              Text(
                _reset ? 'Reset your password' : 'Welcome to your workspace',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              gap(12),
              Text(
                _reset
                    ? 'Enter your work email to receive a reset link.'
                    : 'Sign in with your assigned Luvly account.',
                style: const TextStyle(color: muted),
              ),
              gap(28),
              TextFormField(
                controller: _email,
                enabled: !session.busy,
                decoration: const InputDecoration(labelText: 'Email address'),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                textInputAction: _reset
                    ? TextInputAction.done
                    : TextInputAction.next,
                autocorrect: false,
                validator: validateEmail,
                onFieldSubmitted: _reset ? (_) => _submit() : null,
              ),
              if (!_reset) ...[
                gap(20),
                TextFormField(
                  controller: _password,
                  enabled: !session.busy,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  // Login accepts existing passwords; strength rules apply to creation/reset.
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your password'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                gap(8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: session.busy
                        ? null
                        : () => setState(() {
                            _reset = true;
                            _password.clear();
                            _notice = null;
                          }),
                    child: const Text('Forgot password?'),
                  ),
                ),
              ],
              if (session.error != null || _notice != null) ...[
                gap(16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _notice ?? session.error!,
                    style: TextStyle(
                      color: _notice != null
                          ? sage
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              gap(24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: session.busy ? null : _submit,
                  child: Text(
                    session.busy
                        ? 'Please wait…'
                        : _reset
                        ? 'Send reset link'
                        : 'Sign in',
                  ),
                ),
              ),
              gap(16),
              if (_reset)
                Center(
                  child: TextButton(
                    onPressed: session.busy
                        ? null
                        : () => setState(() {
                            _reset = false;
                            _notice = null;
                          }),
                    child: const Text('Back to sign in'),
                  ),
                )
              else
                const Text(
                  'Need workspace access? Contact your Luvly administrator.',
                  style: TextStyle(color: muted),
                ),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Panel(
              padding: EdgeInsets.zero,
              child: LayoutBuilder(
                builder: (context, size) {
                  if (size.maxWidth < 760) return form;
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(40),
                            decoration: const BoxDecoration(
                              color: Color(0xFF6F5655),
                              borderRadius: BorderRadius.horizontal(
                                left: Radius.circular(12),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.spa_outlined,
                                  color: Colors.white,
                                  size: 42,
                                ),
                                gap(24),
                                const Text(
                                  'Luvly Portal',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                  ),
                                ),
                                gap(36),
                                const Text(
                                  'Behind every beautiful bridal journey.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'LuvlySerif',
                                    fontSize: 38,
                                    height: 1.2,
                                  ),
                                ),
                                gap(24),
                                const Text(
                                  'A thoughtful workspace for the people who make it happen.',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    height: 1.7,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(child: form),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Restores the original portal shell while the session remains server-verified.
class StaffWorkspace extends StatefulWidget {
  const StaffWorkspace({super.key, required this.session});
  final PortalSession session;
  @override
  State<StaffWorkspace> createState() => _StaffWorkspaceState();
}

class _StaffWorkspaceState extends State<StaffWorkspace> {
  late final PortalModel model;

  TeamMember _member() => TeamMember(
    widget.session.identity!.uid,
    widget.session.access!.name,
    widget.session.identity!.email,
    widget.session.access!.role,
    frontDesk: widget.session.access!.frontDesk,
  );

  @override
  void initState() {
    super.initState();
    model = PortalModel.live(member: _member());
  }

  @override
  void didUpdateWidget(covariant StaffWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Display-name updates do not require a sign-out; role/UID changes also
    // replace the parent MaterialApp and discard all protected routes.
    model.current = _member();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PortalScope(
    model: model,
    child: PortalShell(onSignOut: widget.session.signOut),
  );
}
