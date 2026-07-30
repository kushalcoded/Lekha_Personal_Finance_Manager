import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth/auth_provider.dart';
import '../../widgets/common/form_bits.dart';
import '../../widgets/common/glass.dart';

/// Sign-in / create-account screen. Signing in is required — it powers cloud
/// backup, cross-device sync, and iPhone SMS capture. Shown as the home gate
/// until a session exists; the auth listener swaps in the app on success.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _createMode = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _emailCtrl.text.trim().isNotEmpty && _passwordCtrl.text.length >= 6;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim();
    final pass = _passwordCtrl.text;
    final notifier = ref.read(authStateProvider.notifier);
    final ok = _createMode
        ? await notifier.signup(email, pass)
        : await notifier.login(email, pass);
    if (!mounted) return;
    if (ok && _createMode && !ref.read(isAuthenticatedProvider)) {
      // Sign-up succeeded but email confirmation is on — nothing to pop yet.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check your email to confirm, then log in.')),
      );
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email first.')),
      );
      return;
    }
    final ok = await ref.read(authStateProvider.notifier).resetPassword(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Password reset email sent.' : 'Could not send reset email.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final auth = ref.watch(authStateProvider);

    // If shown as a pushed route, close once a session is live (as the home
    // gate there's nothing to pop; the auth listener swaps the screen).
    ref.listen(isAuthenticatedProvider, (prev, next) {
      if (next && mounted) Navigator.of(context).maybePop(true);
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const SizedBox(height: 12),
            Text(
              _createMode ? 'Create your account' : 'Welcome back',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sign in to use Lekha — your data is backed up and synced '
              'across all your devices.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            GlassCard(
              radius: 18,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Email'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'you@example.com'),
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('Password'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _canSubmit ? _submit() : null,
                    decoration: const InputDecoration(
                      hintText: 'At least 6 characters',
                    ),
                  ),
                  if (!_createMode) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: auth.isLoading ? null : _forgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  ] else
                    const SizedBox(height: 8),
                  if (auth.errorMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      auth.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 4),
                  auth.isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : GradientButton(
                          label: _createMode ? 'Create account' : 'Sign in',
                          enabled: _canSubmit,
                          onPressed: _submit,
                        ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: auth.isLoading
                  ? null
                  : () => ref.read(authStateProvider.notifier).loginWithGoogle(),
              icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
              label: const Text('Continue with Google'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: auth.isLoading
                    ? null
                    : () => setState(() => _createMode = !_createMode),
                child: Text(
                  _createMode
                      ? 'Already have an account? Sign in'
                      : "New here? Create an account",
                ),
              ),
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 6),
              Center(
                child: TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      'https://github.com/kushalcoded/Lekha_Personal_Finance_Manager/releases/latest',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.android_rounded, size: 18),
                  label: const Text('Get the Android app'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
