import 'package:flutter/material.dart';
import '../../data/auth_repository.dart';
import '../../app/routes.dart';
import '../../core/mixins/safe_execution_mixin.dart';

class ProfileScreen extends StatefulWidget {
  final bool isMainTab;
  const ProfileScreen({super.key, this.isMainTab = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SafeExecutionMixin {
  String? _email;
  String? _displayName;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // Basic shared pref read, usually fast, but good to be safe
    await safeExecute(() async {
      final email = await authRepository.getEmail();
      final displayName = await authRepository.getDisplayName();
      final photoUrl = await authRepository.getPhotoUrl();
      if (mounted) {
        setState(() {
          _email = email;
          _displayName = displayName;
          _photoUrl = photoUrl;
        });
      }
    }, showLoading: false);
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await safeExecute(() async {
      await authRepository.logout();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        automaticallyImplyLeading: !widget.isMainTab,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            _Avatar(photoUrl: _photoUrl, size: 100),
            const SizedBox(height: 16),
            Text(
              _displayName?.isNotEmpty == true ? _displayName! : (_email ?? 'Пользователь'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (_email != null) ...[
              const SizedBox(height: 4),
              Text(
                _email!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 32),
            
            // Menu Items
            _ProfileMenuItem(
              icon: Icons.folder_outlined,
              title: 'Локальные записи',
              onTap: () => Navigator.pushNamed(context, AppRoutes.localRecordings),
            ),
            const SizedBox(height: 12),
            _ProfileMenuItem(
              icon: Icons.note_alt_outlined,
              title: 'Заметки',
              onTap: () => Navigator.pushNamed(context, AppRoutes.notes),
            ),
            const SizedBox(height: 12),
             _ProfileMenuItem(
              icon: Icons.chat_bubble_outline,
              title: 'Общий чат',
              onTap: () => Navigator.pushNamed(context, AppRoutes.globalChat),
            ),
            
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Выйти из аккаунта'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final double size;

  const _Avatar({this.photoUrl, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
        image: photoUrl != null && photoUrl!.isNotEmpty
            ? DecorationImage(image: NetworkImage(photoUrl!), fit: BoxFit.cover)
            : null,
      ),
      child: photoUrl == null || photoUrl!.isEmpty
          ? Icon(
              Icons.person,
              size: size * 0.5,
              color: theme.colorScheme.onPrimaryContainer,
            )
          : null,
    );
  }
}
