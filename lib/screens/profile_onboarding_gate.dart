import 'package:flutter/material.dart';
import '../services/record_import_service.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'record_import_screen.dart';

/// Mounted inside LegalGate, before the application navigator is available.
class ProfileOnboardingGate extends StatefulWidget {
  final ProfileOnboardingGateway gateway;
  final RecordImportGateway importGateway;
  final Widget child;
  const ProfileOnboardingGate({
    super.key,
    required this.gateway,
    required this.importGateway,
    required this.child,
  });

  @override
  State<ProfileOnboardingGate> createState() => _ProfileOnboardingGateState();
}

class _ProfileOnboardingGateState extends State<ProfileOnboardingGate> {
  bool _checking = true, _complete = false, _failed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _failed = false;
    });
    try {
      final needed = await widget.gateway.needsReview();
      if (mounted) {
        setState(() {
          _complete = !needed;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _checking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_complete) return widget.child;
    return Navigator(
      onDidRemovePage: (_) {},
      pages: [
        MaterialPage<void>(
          child: PopScope(
            canPop: false,
            child: _checking || _failed
                ? RingMasterPageShell(
                    title: 'Link your RingMaster profiles',
                    showAccountButton: false,
                    showHomeButton: false,
                    showBackButton: false,
                    body: Center(
                      child: _checking
                          ? const CircularProgressIndicator()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Connect to the internet to check your RingMaster profiles.',
                                ),
                                TextButton(
                                  onPressed: _check,
                                  child: const Text('Retry profile check'),
                                ),
                              ],
                            ),
                    ),
                  )
                : RecordImportScreen(
                    gateway: widget.importGateway,
                    onContinue: () => setState(() => _complete = true),
                  ),
          ),
        ),
      ],
    );
  }
}
