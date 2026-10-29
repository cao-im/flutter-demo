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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreLoginPreferences();
    });
  }

  Future<void> _restoreLoginPreferences() async {
    final username = await StorageService.getUsername();
    final password = await StorageService.getPassword();
    final autoLogin = await StorageService.getAutoLogin();
    if (!mounted) return;

    final savedUsername = username;
    final savedPassword = password;
    final hasCredentials = savedUsername != null &&
        savedUsername.isNotEmpty &&
        savedPassword != null &&
        savedPassword.isNotEmpty;
    if (!hasCredentials && autoLogin) {
      await StorageService.setAutoLogin(false);
    }
    if (!mounted) return;

    if (savedUsername != null &&
        savedUsername.isNotEmpty &&
        savedPassword != null &&
        savedPassword.isNotEmpty) {
      _usernameController.text = savedUsername;
      _passwordController.text = savedPassword;
    }

    final shouldAutoLogin = hasCredentials && autoLogin;
    setState(() {
      _rememberPassword = hasCredentials;
      _autoLogin = shouldAutoLogin;
      _isAutoLoggingIn = shouldAutoLogin;
    });

    if (shouldAutoLogin) {
      await _handleLogin(isAutoLogin: true);
    }
  }

  void _setRememberPassword(bool value) {
    setState(() {
      _rememberPassword = value;
      if (!value) {
        _autoLogin = false;
      }
    });
  }

  void _setAutoLogin(bool value) {
    setState(() {
      _autoLogin = value;
      if (value) {
        _rememberPassword = true;
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin({bool isAutoLogin = false}) async {
    if (_formKey.currentState?.validate() != true) {
      if (isAutoLogin && mounted) {
        setState(() => _isAutoLoggingIn = false);
      }
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.login(
      _usernameController.text.trim(),
      _passwordController.text,
      context,
    );

    if (!mounted) return;

    if (success) {
      final keepCredentials = _rememberPassword || _autoLogin;
      if (keepCredentials) {
        await StorageService.saveUsername(_usernameController.text.trim());
        await StorageService.savePassword(_passwordController.text);
      } else {
        await StorageService.removePassword();
      }
      await StorageService.setAutoLogin(_autoLogin);

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
      backgroundColor: AppTheme.background(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 800;

          if (isDesktop) {
            return _buildDesktopLayout();
          } else {
            return _buildMobileLayout();
          }
        },
      ),
    );
  }

  /// 桌面端布局：左侧品牌区 + 右侧表单区
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // 左侧品牌区域
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primaryColor,
                  AppTheme.primaryColor.withOpacity(0.8),
                ],
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/images/caoim_logo.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      '曹操IM',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '即时通讯，连接你我',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '登录您的账号以继续',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 右侧表单区域
        Expanded(
          flex: 4,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 40),
                      Center(
                        child: Text(
                          '登录',
                          style: TextStyle(
                            fontSize: 60,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
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
                                    _setRememberPassword(v!);
                                  },
                          ),
                          GestureDetector(
                            onTap: _isAutoLoggingIn
                                ? null
                                : () {
                                    _setRememberPassword(!_rememberPassword);
                                  },
                            child: Text(
                              '记住密码',
                              style: TextStyle(
                                color: _isAutoLoggingIn
                                    ? Colors.grey[400]
                                    : AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Checkbox(
                            value: _autoLogin,
                            onChanged: _isAutoLoggingIn
                                ? null
                                : (v) {
                                    _setAutoLogin(v!);
                                  },
                          ),
                          GestureDetector(
                            onTap: _isAutoLoggingIn
                                ? null
                                : () {
                                    _setAutoLogin(!_autoLogin);
                                  },
                            child: Text(
                              '自动登录',
                              style: TextStyle(
                                color: _isAutoLoggingIn
                                    ? Colors.grey[400]
                                    : AppTheme.textSecondary(context),
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
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text('登 录',
                                    style: TextStyle(fontSize: 16)),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '还没有账号？',
                            style: TextStyle(color: AppTheme.textSecondary(context)),
                          ),
                          TextButton(
                            onPressed: _isAutoLoggingIn
                                ? null
                                : () {
                                    Navigator.pushNamed(
                                        context, AppRouter.register);
                                  },
                            child: const Text('立即注册'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 移动端布局：保持原有的垂直居中布局
  Widget _buildMobileLayout() {
    return SafeArea(
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
                    borderRadius: BorderRadius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/images/caoim_logo.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '欢迎回来',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '登录您的账号以继续',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary(context),
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
                            _setRememberPassword(v!);
                          },
                  ),
                  GestureDetector(
                    onTap: _isAutoLoggingIn
                        ? null
                        : () {
                            _setRememberPassword(!_rememberPassword);
                          },
                    child: Text(
                      '记住密码',
                      style: TextStyle(
                        color: _isAutoLoggingIn
                            ? Colors.grey[400]
                            : AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Checkbox(
                    value: _autoLogin,
                    onChanged: _isAutoLoggingIn
                        ? null
                        : (v) {
                            _setAutoLogin(v!);
                          },
                  ),
                  GestureDetector(
                    onTap: _isAutoLoggingIn
                        ? null
                        : () {
                            _setAutoLogin(!_autoLogin);
                          },
                    child: Text(
                      '自动登录',
                      style: TextStyle(
                        color: _isAutoLoggingIn
                            ? Colors.grey[400]
                            : AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Consumer<AuthProvider>(
                builder: (context, authProvider, _) {
                  final isLoading = authProvider.isLoading || _isAutoLoggingIn;
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
                    style: TextStyle(color: AppTheme.textSecondary(context)),
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
    );
  }
}
