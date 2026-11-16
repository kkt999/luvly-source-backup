import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'workspace_api.dart';
import '../profile/profile_photo.dart';
import '../src/contact_validation.dart';
import '../src/malaysia_phone_field.dart';

class StaffProfileScreen extends StatefulWidget {
  const StaffProfileScreen({
    super.key,
    required this.uid,
    this.api,
    this.verifyEmail,
  });
  final String uid;
  final WorkspaceApi? api;
  final Future<void> Function(String)? verifyEmail;
  @override
  State<StaffProfileScreen> createState() => _StaffProfileState();
}

class _StaffProfileState extends State<StaffProfileScreen> {
  late final api = widget.api ?? WorkspaceApi();
  final name = TextEditingController(),
      phone = TextEditingController(),
      email = TextEditingController();
  final form = GlobalKey<FormState>();
  Map<String, dynamic>? data;
  bool busy = false, loading = true, dirty = false;
  String? error, notice;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final row = await api.request('/v1/my-staff-profile');
      if (row['uid'] != widget.uid ||
          row['revision'] is! int ||
          row['name'] is! String ||
          row['phone'] is! String ||
          row['email'] is! String) {
        throw StateError('Invalid profile');
      }
      if (!mounted) return;
      setState(() {
        data = row;
        name.text = row['name'];
        phone.text = malaysiaNationalInput(row['phone'] as String);
        email.clear();
        dirty = false;
      });
    } catch (e) {
      if (mounted) setState(() => error = workspaceError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || data == null) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final row = await api.request(
        '/v1/my-staff-profile',
        body: {
          'name': name.text.trim(),
          'phone': formatContactPhone(phone.text),
          'revision': data!['revision'],
        },
      );
      if (row['uid'] != widget.uid) throw StateError('Account changed');
      if (mounted) {
        setState(() {
          data = row;
          phone.text = malaysiaNationalInput(row['phone'] as String);
          dirty = false;
          notice = 'Your profile has been saved.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = workspaceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changeEmail() async {
    final value = email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      setState(() => error = 'Enter a valid new email address.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      if (widget.verifyEmail != null) {
        await widget.verifyEmail!(value);
      } else {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null || user.uid != widget.uid) {
          throw StateError('Please sign in again');
        }
        await user.verifyBeforeUpdateEmail(value);
      }
      if (mounted) {
        setState(
          () => notice =
              'Verification email sent. Open the link in your new mailbox, then sign in again with that email. Your role and assignments do not change.',
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => error = e.code == 'requires-recent-login'
              ? 'For security, sign out and sign in again, then retry changing your email.'
              : 'Could not send the verification email. Check the address and retry.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = workspaceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    if (widget.api == null) api.close();
    name.dispose();
    phone.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !dirty,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || busy || !dirty) return;
      final leave = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (leave == true && context.mounted) {
        setState(() => dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ProfilePhotoAvatar(
                  uid: widget.uid,
                  radius: 48,
                  editable: true,
                  showLabel: true,
                  api: widget.api,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your account details',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Keep your contact details current. Access roles and service skills are managed by your manager.',
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: busy ? null : load,
                  child: const Text('Reload latest profile'),
                ),
              ],
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    notice!,
                    style: const TextStyle(color: Color(0xFF46665B)),
                  ),
                ),
              if (data != null)
                Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: name,
                        enabled: !busy && !loading,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                        ),
                        onChanged: (_) => setState(() => dirty = true),
                        validator: validateName,
                      ),
                      const SizedBox(height: 16),
                      MalaysiaPhoneField(
                        controller: phone,
                        enabled: !busy && !loading,
                        existingPhone: data!['phone'] as String,
                        onChanged: (_) => setState(() => dirty = true),
                      ),
                      const SizedBox(height: 12),
                      Text('Access role: ${data!['role']} · read only'),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: busy || loading ? null : save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(busy ? 'Saving…' : 'Save profile'),
                      ),
                      const Divider(height: 48),
                      const Text(
                        'Sign-in email',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Current email: ${data!['email']}'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: email,
                        enabled: !busy,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'New email address',
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: busy ? null : changeEmail,
                        child: const Text('Verify new email'),
                      ),
                      const Text(
                        'The sign-in email changes only after Firebase verifies the new mailbox. After signing in again, Save profile synchronises the verified address.',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
