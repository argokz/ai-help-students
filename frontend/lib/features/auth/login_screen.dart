import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../app/routes.dart';
import '../../core/config/app_config.dart';
import '../../data/api_client.dart';
import '../../data/auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    if (await authRepository.isLoggedIn()) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.main);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;
    setState(() {
      _error = null;
      _isLoading = true;
    });
    try {
      final res = await apiClient.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await authRepository.saveSession(
        token: res.accessToken,
        userId: res.userId,
        email: res.email,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.main);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    if (AppConfig.googleClientId.isEmpty) {
      setState(() {
        _error = 'Google Sign-In не настроен. Укажите googleClientId в конфиге.';
      });
      return;
    }
    setState(() {
      _error = null;
      _isLoading = true;
    });
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: AppConfig.googleClientId,
      );
      final account = await googleSignIn.signIn();
      if (account == null) {
        setState(() => _isLoading = false);
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        setState(() {
          _error = 'Не удалось получить токен от Google';
          _isLoading = false;
        });
        return;
      }
      final res = await apiClient.loginWithGoogle(idToken);
      await authRepository.saveSession(
        token: res.accessToken,
        userId: res.userId,
        email: res.email,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.main);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ассистент Лекций',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Войдите в аккаунт',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'example@mail.com',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Введите email';
                      if (!v.contains('@')) return 'Некорректный email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Пароль',
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Введите пароль';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isLoading ? null : () async {
                      if (_formKey.currentState?.validate() ?? false) await _login();
                    },
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Войти'),
                  ),
                  if (AppConfig.googleClientId.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 24),
                      label: const Text('Войти через Google'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, AppRoutes.register);
                    },
                    child: const Text('Нет аккаунта? Зарегистрироваться'),
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
