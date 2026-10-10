import 'package:flutter/material.dart';
import '../../config/legal_config.dart';
import '../../services/legal_service.dart';
import '../../widgets/ringmaster_page_shell.dart';
import 'legal_screen.dart';

class LegalGate extends StatefulWidget {
  final LegalGateway gateway;
  final Widget child;
  const LegalGate({super.key, required this.gateway, required this.child});
  @override
  State<LegalGate> createState() => _LegalGateState();
}

class _LegalGateState extends State<LegalGate> {
  bool _checking = true, _accepted = false;
  bool _terms = false, _privacy = false, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final accepted = await widget.gateway.hasAccepted();
      if (mounted) {
        setState(() {
          _accepted = accepted;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
          _error = 'Unable to check your policy agreement. Please retry.';
        });
      }
    }
  }

  Future<void> _accept() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.gateway.accept();
      if (mounted) {
        setState(() {
          _accepted = true;
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Unable to save your agreement. Please try again.';
        });
      }
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.gateway.signOut();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Unable to sign out. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted) return widget.child;
    // Separate review navigator keeps all application routes unmounted until agreement.
    return Navigator(
      onDidRemovePage: (_) {},
      pages: [
        MaterialPage<void>(
          child: Builder(
            builder: (context) => PopScope(
              canPop: false,
              child: RingMasterPageShell(
                title: 'Review our policies',
                showHomeButton: false,
                showBackButton: false,
                body: _checking
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Before continuing, please review and agree to the current Terms of Service and Privacy Policy. Each family member must agree using their own account.',
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Terms ${LegalConfig.termsVersion} • Privacy ${LegalConfig.privacyVersion}',
                                ),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  children: [
                                    TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () => Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    const LegalScreen(),
                                              ),
                                            ),
                                      child: const Text(
                                        'Review Terms of Service',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () => Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    const LegalScreen(
                                                      privacy: true,
                                                    ),
                                              ),
                                            ),
                                      child: const Text(
                                        'Review Privacy Policy',
                                      ),
                                    ),
                                  ],
                                ),
                                CheckboxListTile(
                                  value: _terms,
                                  onChanged: _saving
                                      ? null
                                      : (v) =>
                                            setState(() => _terms = v ?? false),
                                  title: const Text(
                                    'I have reviewed and agree to the Terms of Service',
                                  ),
                                ),
                                CheckboxListTile(
                                  value: _privacy,
                                  onChanged: _saving
                                      ? null
                                      : (v) => setState(
                                          () => _privacy = v ?? false,
                                        ),
                                  title: const Text(
                                    'I have reviewed and acknowledge the Privacy Policy',
                                  ),
                                ),
                                if (_error != null) ...[
                                  Text(_error!, semanticsLabel: _error),
                                  TextButton(
                                    onPressed: _saving ? null : _check,
                                    child: const Text('Retry policy check'),
                                  ),
                                ],
                                ElevatedButton(
                                  onPressed:
                                      !_terms ||
                                          !_privacy ||
                                          _saving ||
                                          (_error?.startsWith(
                                                'Unable to check',
                                              ) ??
                                              false)
                                      ? null
                                      : _accept,
                                  child: Text(
                                    _saving
                                        ? 'Please wait…'
                                        : 'Agree and continue',
                                  ),
                                ),
                                TextButton(
                                  onPressed: _saving ? null : _signOut,
                                  child: const Text('Sign out'),
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
      ],
    );
  }
}
