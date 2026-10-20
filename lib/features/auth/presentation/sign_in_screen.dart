import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/inputs.dart';

/// Email + password sign-in / sign-up. With [restore], a shop owned by the
/// account is downloaded to this device.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.restore = false});

  final bool restore;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authServiceProvider);
    try {
      final user = _signUp
          ? await auth.signUp(_email.text, _password.text)
          : await auth.signIn(_email.text, _password.text);

      final hasShop = ref.read(shopIdProvider) != null;
      final engine = ref.read(syncEngineProvider);
      if (!hasShop && engine != null && !_signUp) {
        final shopId = await engine.adoptOwnedShop(user.uid);
        if (shopId != null) {
          await ref.read(settingsProvider.notifier).set(SettingKeys.shopId, shopId);
          // Router leaves /sign-in for /sell once the shop id is set.
          return;
        }
        if (mounted) showAppSnack(context, 'No shop found for this account. Create one to continue.');
      }
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = AuthService.describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Enter your email first.');
      return;
    }
    try {
      await ref.read(authServiceProvider).sendPasswordReset(_email.text);
      if (mounted) showAppSnack(context, 'Password reset email sent.');
    } catch (e) {
      setState(() => _error = AuthService.describe(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return AppScaffold(
      title: _signUp ? 'Create account' : 'Sign in',
      showBack: true,
      bottom: SizedBox(
        width: double.infinity,
        child: PrimaryButton(label: _signUp ? 'Create account' : 'Sign in', busy: _busy, onPressed: _submit),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.only(top: AppSpace.lg),
              children: [
                Text(
                  widget.restore
                      ? 'Sign in to download your shop to this device.'
                      : 'Sign in to back up your shop and sync it across devices.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: AppSpace.xl),
                LabeledField(
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
                ),
                const SizedBox(height: AppSpace.md),
                LabeledField(
                  label: 'Password',
                  controller: _password,
                  validator: (v) => (v ?? '').length < 6 ? 'At least 6 characters' : null,
                  suffix: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  obscureText: _obscure,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpace.md),
                  Text(_error!, style: text.bodyMedium?.copyWith(color: colors.error)),
                ],
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _signUp = !_signUp;
                        _error = null;
                      }),
                      child: Text(_signUp ? 'I have an account' : 'Create an account'),
                    ),
                    const Spacer(),
                    if (!_signUp) TextButton(onPressed: _reset, child: const Text('Forgot password?')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
