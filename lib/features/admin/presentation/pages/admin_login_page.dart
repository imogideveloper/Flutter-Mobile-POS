import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/backend_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../providers/admin_providers.dart';

/// Login Administrator (email + password) - akun dibuat operator lewat
/// `POST /admin/akun`. Terpisah dari login kasir/OTP toko.
class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _memproses = false;
  bool _sembunyikan = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _masuk() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _memproses = true);
    try {
      await ref
          .read(adminSesiProvider.notifier)
          .masuk(email: _emailController.text, password: _passwordController.text);
      if (mounted) context.go('/admin');
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    } catch (e) {
      if (mounted) showAppToast(context, message: 'Gagal masuk: $e', variant: ToastVariant.danger);
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Masuk sebagai Administrator')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Dashboard Administrator', style: AppTypography.headerTitle),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Khusus tim pengembang Imogi: melihat usaha terdaftar dan kemajuan fitur.',
                    style: AppTypography.secondary,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  TextFormField(
                    key: const Key('adminLogin.email'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Isi email yang valid' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const Key('adminLogin.password'),
                    controller: _passwordController,
                    obscureText: _sembunyikan,
                    decoration: InputDecoration(
                      labelText: 'Kata sandi',
                      suffixIcon: IconButton(
                        icon: Icon(_sembunyikan ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _sembunyikan = !_sembunyikan),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Isi kata sandi' : null,
                    onFieldSubmitted: (_) => _masuk(),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  AppPrimaryButton(
                    key: const Key('adminLogin.masuk'),
                    label: _memproses ? 'Memproses...' : 'Masuk',
                    onPressed: _memproses ? null : _masuk,
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
