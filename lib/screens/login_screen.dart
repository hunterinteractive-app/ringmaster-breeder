import 'legal/legal_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';

class LoginScreen extends StatefulWidget {
  final AuthGateway auth;
  const LoginScreen({super.key, required this.auth});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  String? _pendingEmail;
  String? _message;
  bool _busy = false;
  int _resendSeconds = 0;
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    _resendSeconds = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendSeconds--);
      if (_resendSeconds <= 0) timer.cancel();
    });
  }

  Future<void> _request() async {
    if (_busy || _resendSeconds > 0 || !_form.currentState!.validate()) return;
    final email = _email.text.trim().toLowerCase();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.auth.requestCode(email);
      if (!mounted) return;
      setState(() {
        _pendingEmail = email;
        _message = 'Check your email for your sign-in code.';
        _startCooldown();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'We could not send a code. Check your email address and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.auth.verifyCode(_pendingEmail!, _code.text);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'The code is invalid or expired. Try again or request a new code.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BreederColors.primary,
            Color(0xFF682435),
            BreederColors.primary,
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 1060 / 420,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Align(
                            alignment: const Alignment(0.30, 0.50),
                            child: FractionallySizedBox(
                              widthFactor: 0.43,
                              heightFactor: 0.25,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Image.asset(
                            'assets/images/ringmaster_breeder_logo_transparent.png',
                            fit: BoxFit.contain,
                            semanticLabel: 'RingMaster Breeder logo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'RingMaster Breeder',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Herd records, pedigrees, and family access in one place.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: BreederColors.accent,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                        surface: BreederColors.text,
                        onSurface: Colors.white,
                        primary: BreederColors.accent,
                        onPrimary: BreederColors.text,
                      ),
                      textTheme: Theme.of(context).textTheme.apply(
                        bodyColor: Colors.white,
                        displayColor: Colors.white,
                      ),
                      inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        labelStyle: const TextStyle(
                          color: BreederColors.accent,
                        ),
                        prefixIconColor: BreederColors.accent,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: BreederColors.accent,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                      ),
                    ),
                    child: Card(
                      color: BreederColors.text,
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _form,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _pendingEmail == null
                                    ? 'Log in or create your account'
                                    : 'Enter your login code',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _pendingEmail == null
                                    ? 'Enter your email to receive a secure code for herd records, pedigrees, and family access.'
                                    : 'Enter the code sent to $_pendingEmail.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: BreederColors.accent,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _email,
                                enabled: _pendingEmail == null && !_busy,
                                autofillHints: const [AutofillHints.email],
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: (v) =>
                                    RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    ).hasMatch(v?.trim() ?? '')
                                    ? null
                                    : 'Enter a valid email address',
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'The code can only be used once and expires soon.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: BreederColors.accent,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'By continuing, you agree to the RingMaster Breeder Terms of Service and Privacy Policy.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: BreederColors.accent,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                              Wrap(
                                alignment: WrapAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const LegalScreen(),
                                      ),
                                    ),
                                    child: const Text('Terms of Service'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const LegalScreen(privacy: true),
                                      ),
                                    ),
                                    child: const Text('Privacy Policy'),
                                  ),
                                ],
                              ),
                              if (_pendingEmail != null) ...[
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _code,
                                  autofillHints: const [
                                    AutofillHints.oneTimeCode,
                                  ],
                                  keyboardType: TextInputType.number,
                                  enabled: !_busy,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    letterSpacing: 8,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Sign-in code',
                                    prefixIcon: Icon(Icons.password_outlined),
                                  ),
                                  onFieldSubmitted: (_) => _verify(),
                                  validator: (v) =>
                                      RegExp(
                                        r'^\d{6,8}$',
                                      ).hasMatch(v?.trim() ?? '')
                                      ? null
                                      : 'Enter the code from your email',
                                ),
                              ],
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: BreederColors.primary,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: _busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        _pendingEmail == null
                                            ? Icons.mark_email_read_outlined
                                            : Icons.login,
                                      ),
                                onPressed: _busy
                                    ? null
                                    : (_pendingEmail == null
                                          ? _request
                                          : _verify),
                                label: Text(
                                  _busy
                                      ? 'Please wait…'
                                      : (_pendingEmail == null
                                            ? 'Send sign-in code'
                                            : 'Sign in'),
                                ),
                              ),
                              if (_pendingEmail != null) ...[
                                TextButton(
                                  onPressed: _busy || _resendSeconds > 0
                                      ? null
                                      : _request,
                                  child: Text(
                                    _resendSeconds > 0
                                        ? 'Resend in $_resendSeconds seconds'
                                        : 'Resend code',
                                  ),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                          _pendingEmail = null;
                                          _code.clear();
                                          _message = null;
                                          _timer?.cancel();
                                          _resendSeconds = 0;
                                        }),
                                  child: const Text('Use another email'),
                                ),
                              ],
                              if (_message != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _message!,
                                      style: const TextStyle(
                                        color: BreederColors.accent,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Version ${AppConfig.version}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: BreederColors.accent, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
