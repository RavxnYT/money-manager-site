import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../data/app_repository.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/animated_appear.dart';
import '../../core/ui/glass_panel.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.repository,
    this.noticeMessage,
  });

  final AppRepository repository;
  final String? noticeMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _error = null;
      _isLoading = true;
    });
    try {
      if (_isLogin) {
        await widget.repository.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        final configuredConfirmRedirect = (dotenv.env['EMAIL_CONFIRM_REDIRECT_URL'] ?? '').trim();
        await widget.repository.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          fullName: _nameController.text.trim(),
          emailRedirectTo: configuredConfirmRedirect.isEmpty ? null : configuredConfirmRedirect,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account created. Please verify your email if prompted.')),
          );
        }
      }
    } catch (e) {
      setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendResetPassword() async {
    final controller = TextEditingController(text: _emailController.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset Password'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final configuredRedirect = (dotenv.env['PASSWORD_RESET_REDIRECT_URL'] ?? '').trim();
      await widget.repository.sendPasswordResetEmail(
        email: controller.text.trim(),
        redirectTo: configuredRedirect.isEmpty ? null : configuredRedirect,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent. Check your inbox.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _resendVerificationEmail() async {
    final controller = TextEditingController(text: _emailController.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resend Verification Email'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repository.resendSignUpVerificationEmail(email: controller.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent. Please check your inbox.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A1022), Color(0xFF151F38), Color(0xFF0A1022)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: AnimatedAppear(
              delayMs: 80,
              child: GlassPanel(
                margin: const EdgeInsets.all(18),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 50,
                        width: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7B8BFF), Color(0xFF58C2FF)],
                          ),
                        ),
                        child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _isLogin ? 'Welcome back' : 'Create your account',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isLogin
                            ? 'Sign in to continue managing your money.'
                            : 'Start tracking income, expenses, budgets, and savings.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                      if (widget.noticeMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          widget.noticeMessage!,
                          style: const TextStyle(color: Color(0xFF7EE787), fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (!_isLogin)
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: 'Full Name'),
                          validator: (value) {
                            if (!_isLogin) {
                              if (value == null || value.trim().isEmpty) return 'Enter your name';
                            }
                            return null;
                          },
                        ),
                      if (!_isLogin) const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('login_email_field'),
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Enter your email';
                          if (!value.contains('@')) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('login_password_field'),
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return 'Use at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      if (_isLogin) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton(
                              onPressed: _isLoading ? null : _sendResetPassword,
                              child: const Text('Forgot password?'),
                            ),
                            TextButton(
                              onPressed: _isLoading ? null : _resendVerificationEmail,
                              child: const Text('Resend verification'),
                            ),
                          ],
                        ),
                      ],
                      if (!_isLogin) const SizedBox(height: 12),
                      if (!_isLogin)
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscureConfirmPassword = !_obscureConfirmPassword,
                              ),
                              icon: Icon(
                                _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (_isLogin) return null;
                            if (value == null || value.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: Colors.red.shade300)),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _submit,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_isLoading ? 'Please wait...' : (_isLogin ? 'Sign In' : 'Sign Up')),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(() {
                                    _isLogin = !_isLogin;
                                    _error = null;
                                  }),
                          child: Text(_isLogin ? 'Need an account? Sign up' : 'Already have an account? Sign in'),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
