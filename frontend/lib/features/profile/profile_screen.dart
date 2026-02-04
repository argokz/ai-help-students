import 'package:flutter/material.dart';
import '../../data/auth_repository.dart';
import '../../app/routes.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _email;
  String? _displayName;
  String? _photoUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final email = await authRepository.getEmail();
    final displayName = await authRepository.getDisplayName();
    final photoUrl = await authRepository.getPhotoUrl();
    if (mounted) {
      setState(() {
        _email = email;
        _displayName = displayName;
        _photoUrl = photoUrl;
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await authRepository.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pad = MediaQuery.paddingOf(context);
    final padding = EdgeInsets.fromLTRB(pad.left + 20, 24, pad.right + 20, pad.bottom + 24);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Профиль')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: padding,
          child: Column(
            children: [
              const SizedBox(height: 24),
              Center(
                child: _Avatar(photoUrl: _photoUrl, size: 96),
              ),
              const SizedBox(height: 16),
              Text(
                _displayName?.isNotEmpty == true ? _displayName! : (_email ?? 'Пользователь'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (_email != null && _email!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _email!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 40),
              ListTile(
                leading: Icon(Icons.person_outline, color: theme.colorScheme.primary),
                title: const Text('Мои лекции'),
                trailing: const Icon(Icons.chevron_right),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                  Navigator.pushReplacementNamed(context, AppRoutes.lectures);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.chat_bubble_outline, color: theme.colorScheme.primary),
                title: const Text('Общий чат'),
                trailing: const Icon(Icons.chevron_right),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () {
                  Navigator.pushNamed(context, AppRoutes.globalChat);
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _logout,
                  style: FilledButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Выйти'),
                ),
              ),
            ],
          ),
        ),
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
    final circle = CircleAvatar(
      radius: size / 2,
      backgroundColor: theme.colorScheme.primaryContainer,
      backgroundImage: photoUrl != null && photoUrl!.isNotEmpty
          ? NetworkImage(photoUrl!)
          : null,
      child: photoUrl == null || photoUrl!.isEmpty
          ? Icon(
              Icons.person,
              size: size * 0.5,
              color: theme.colorScheme.onPrimaryContainer,
            )
          : null,
    );
    return circle;
  }
}
