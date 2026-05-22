import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../router/app_router.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberPassword = false;
  bool _autoLogin = false;
  bool _isAutoLoggingIn = false;

  @override
  void initState() {
    super.initState();
    _checkSavedCredentials();
    _checkAutoLogin();
  }

  Future<void> _checkSavedCredentials() async {
    final username = await StorageService.getUsername();
    final password = await StorageService.getPassword();
    if (username != null && password != null) {
      setState(() {
        _usernameController.text = username;
        _passwordController.text = password;
        _rememberPassword = true;
      });
    }
  }

  Future<void> _checkAutoLogin() async {
    final autoLogin = await StorageService.getAutoLogin();
    if (autoLogin) {
      final username = await StorageService.getUsername();
      final password = await StorageService.getPassword();
      if (username != null && password != null) {
        if (mounted) {
          setState(() => _isAutoLoggingIn = true);
        }
        Future.delayed(const Duration(milliseconds: 500), () async {
          if (mounted) {
            await _handleLogin(isAutoLogin: true);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin({bool isAutoLogin = false}) async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.login(
      _usernameController.text.trim(),
      _passwordController.text,
      context,
    );

    if (!mounted) return;

    if (success) {
      if (_rememberPassword) {
        await StorageService.saveUsername(_usernameController.text.trim());
        await StorageService.savePassword(_passwordController.text);
      } else {
        await StorageService.removePassword();
      }
      if (_autoLogin) {
        await StorageService.setAutoLogin(true);
      } else {
        await StorageService.setAutoLogin(false);
      }

      Navigator.of(context).pushReplacementNamed(AppRouter.home);
    } else {
      if (_isAutoLoggingIn) {
        setState(() => _isAutoLoggingIn = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? '登录失败'),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      size: 56,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  '欢迎回来',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '登录您的账号以继续',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 48),
                TextFormField(
                  controller: _usernameController,
                  enabled: !_isAutoLoggingIn,
                  decoration: InputDecoration(
                    labelText: '用户名',
                    hintText: '请输入用户名',
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入用户名';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: !_isAutoLoggingIn,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: '请输入密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: _isAutoLoggingIn
                          ? null
                          : () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入密码';
                    }
                    if (value.length < 6) {
                      return '密码长度不能少于6位';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) =>
                      _isAutoLoggingIn ? null : _handleLogin(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: _rememberPassword,
                      onChanged: _isAutoLoggingIn
                          ? null
                          : (v) {
                              setState(() => _rememberPassword = v!);
                            },
                    ),
                    GestureDetector(
                      onTap: _isAutoLoggingIn
                          ? null
                          : () {
                              setState(
                                () => _rememberPassword = !_rememberPassword,
                              );
                            },
                      child: Text(
                        '记住密码',
                        style: TextStyle(
                          color: _isAutoLoggingIn
                              ? Colors.grey[400]
                              : AppTheme.textSecondaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Checkbox(
                      value: _autoLogin,
                      onChanged: _isAutoLoggingIn
                          ? null
                          : (v) {
                              setState(() => _autoLogin = v!);
                            },
                    ),
                    GestureDetector(
                      onTap: _isAutoLoggingIn
                          ? null
                          : () {
                              setState(() => _autoLogin = !_autoLogin);
                            },
                      child: Text(
                        '自动登录',
                        style: TextStyle(
                          color: _isAutoLoggingIn
                              ? Colors.grey[400]
                              : AppTheme.textSecondaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Consumer<AuthProvider>(
                  builder: (context, authProvider, _) {
                    final isLoading =
                        authProvider.isLoading || _isAutoLoggingIn;
                    return ElevatedButton(
                      onPressed: isLoading ? null : _handleLogin,
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('登 录', style: TextStyle(fontSize: 16)),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '还没有账号？',
                      style: TextStyle(color: AppTheme.textSecondaryColor),
                    ),
                    TextButton(
                      onPressed: _isAutoLoggingIn
                          ? null
                          : () {
                              Navigator.pushNamed(context, AppRouter.register);
                            },
                      child: const Text('立即注册'),
                    ),
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
