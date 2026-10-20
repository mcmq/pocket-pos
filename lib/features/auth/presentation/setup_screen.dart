import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/data/shop_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/inputs.dart';

/// First launch: create the shop locally. Works offline; signing in for
/// cloud sync is optional and can happen later.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  var _currency = commonCurrencies.first;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(shopRepositoryProvider).createShop(
            name: _name.text,
            currencyCode: _currency.code,
            currencySymbol: _currency.symbol,
            decimalPlaces: _currency.decimals,
            phone: _phone.text,
            address: _address.text,
            ownerUid: ref.read(authServiceProvider).currentUser?.uid,
          );
      // The router redirects to the sell screen once the shop exists.
    } catch (e) {
      if (mounted) showAppSnack(context, 'Could not create shop: $e');
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final auth = ref.watch(authServiceProvider);
    final user = ref.watch(authUserProvider).value;
    const gap = SizedBox(height: AppSpace.md);

    return AppScaffold(
      bottom: SizedBox(
        width: double.infinity,
        child: PrimaryButton(label: 'Create shop', busy: _saving, onPressed: _create),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.only(top: AppSpace.xxxl, bottom: AppSpace.lg),
              children: [
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                  child: Icon(Icons.point_of_sale, color: c.onPrimary, size: 34),
                ),
                const SizedBox(height: AppSpace.lg),
                Text('Welcome to PocketPOS', textAlign: TextAlign.center, style: text.titleLarge),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Set up your shop. Everything works offline. Sign in any time to back up and sync across devices.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
                const SizedBox(height: AppSpace.xxl),
                LabeledField(
                  label: 'Shop name',
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your shop name' : null,
                ),
                gap,
                LabeledDropdown<String>(
                  label: 'Currency',
                  value: _currency.code,
                  items: [
                    for (final cur in commonCurrencies)
                      DropdownMenuItem(value: cur.code, child: Text('${cur.code} (${cur.symbol})')),
                  ],
                  onChanged: (v) => setState(() => _currency = commonCurrencies.firstWhere((cur) => cur.code == v)),
                ),
                gap,
                LabeledField(label: 'Phone (optional)', controller: _phone, keyboardType: TextInputType.phone),
                gap,
                LabeledField(label: 'Address (optional)', controller: _address, maxLines: 2),
                const SizedBox(height: AppSpace.xl),
                if (auth.available)
                  Center(
                    child: user == null
                        ? TextButton(
                            onPressed: () => context.push('/sign-in?restore=1'),
                            child: const Text('Already use PocketPOS? Sign in to restore your shop'),
                          )
                        : Text('Signed in as ${user.email}', style: text.bodyMedium),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
