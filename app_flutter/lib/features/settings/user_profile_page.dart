import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/state/profile_controller.dart';

class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key});

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(profileControllerProvider.notifier).loadMe();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await ref.read(profileControllerProvider.notifier).updateMe(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
    );

    if (!mounted) return;

    final state = ref.read(profileControllerProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (state.success ?? 'Perfil atualizado com sucesso.')
            : (state.error ?? 'Falha ao salvar.')),
      ),
    );
  }

  Future<void> _openChangePassword() async {
    final payload = await showDialog<_PasswordPayload>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _ChangePasswordDialog(),
    );

    if (!mounted || payload == null) return;

    final ok = await ref.read(profileControllerProvider.notifier).changePassword(
      currentPassword: payload.currentPassword,
      newPassword: payload.newPassword,
    );

    if (!mounted) return;

    final state = ref.read(profileControllerProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (state.success ?? 'Senha alterada com sucesso.')
            : (state.error ?? 'Falha ao alterar senha.')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileControllerProvider);
    final theme = Theme.of(context);

    if (!_seeded && state.me != null) {
      _seeded = true;
      _nameCtrl.text = state.me!.name;
      _emailCtrl.text = state.me!.email;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            onPressed: state.loading
                ? null
                : () => ref.read(profileControllerProvider.notifier).loadMe(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.error.withOpacity(0.35),
                ),
              ),
              child: Text(
                state.error!,
                style: TextStyle(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          _SectionCard(
            title: 'Conta',
            subtitle: 'Dados do usuário e segurança',
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: state.saving ? null : _save,
                    icon: state.saving
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Segurança',
            subtitle: 'Troque sua senha com segurança.',
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: state.changingPassword ? null : _openChangePassword,
                icon: state.changingPassword
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.password_outlined),
                label: const Text('Alterar senha'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _PasswordPayload {
  final String currentPassword;
  final String newPassword;

  const _PasswordPayload({
    required this.currentPassword,
    required this.newPassword,
  });
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final current = _currentCtrl.text.trim();
    final next = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (current.isEmpty) {
      setState(() => _error = 'Informe a senha atual.');
      return;
    }

    if (next.length < 8) {
      setState(() => _error = 'A nova senha deve ter pelo menos 8 caracteres.');
      return;
    }

    if (next != confirm) {
      setState(() => _error = 'Confirmação não confere.');
      return;
    }

    Navigator.of(context).pop(
      _PasswordPayload(
        currentPassword: current,
        newPassword: next,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Alterar senha'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextField(
              controller: _currentCtrl,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Senha atual'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newCtrl,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Nova senha'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Confirmar nova senha',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}