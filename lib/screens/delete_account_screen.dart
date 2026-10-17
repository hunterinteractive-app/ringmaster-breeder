import '../widgets/adaptive_layout.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/family_service.dart';
import '../offline/offline_runtime.dart';
import '../widgets/ringmaster_page_shell.dart';

class DeleteAccountScreen extends StatefulWidget {
  final bool resuming;
  const DeleteAccountScreen({super.key, this.resuming = false});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final code = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false, sent = false, pending = false;
  String? error;
  @override
  void initState() {
    super.initState();
    pending = widget.resuming;
  }

  @override
  void dispose() {
    code.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> run(String action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await OfflineRuntime.client.functions.invoke(
        'delete-account',
        body: {
          'action': action,
          'code': code.text.trim(),
          'confirmation': confirmation.text.trim(),
        },
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['deleted'] == true) {
        FamilyService.clear();
        await OfflineRuntime.client.auth.signOut(scope: SignOutScope.local);
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      } else if (mounted) {
        setState(() => sent = true);
      }
    } on FunctionException catch (e) {
      if (mounted) {
        setState(() {
          final details = e.details;
          if (details is Map) {
            pending = pending || details['pending'] == true;
            error = details['error']?.toString();
          }
          error ??= 'Unable to complete the request. Please try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Connection interrupted. Retry; a deletion already started will resume safely.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    showAccountButton: false,
    title: 'Delete account',
    body: SingleChildScrollView(
      padding: BreederLayout.pagePadding(context, normal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Card(
            child: AdaptivePadding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    pending
                        ? 'Finish account deletion'
                        : 'Permanently delete your Breeder account',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const AdaptiveGap(height: 16),
                  Text(
                    pending
                        ? 'Your deletion request is saved and account access is locked. Resume to finish removing your data.'
                        : 'This removes all herds you own, animals, pedigrees, weights, health records, breedings, uploaded files, and your contact details. Family members will lose access to your herds. This cannot be undone.',
                  ),
                  const AdaptiveGap(height: 12),
                  const Text(
                    'Your separate RingMaster Show account and its show records remain. Breeder syncing stops. Herds owned by other family members are not deleted.',
                  ),
                  if (!pending) ...[
                    const AdaptiveGap(height: 12),
                    const Text(
                      'Export anything you want to keep before continuing. The animal CSV is not a complete backup of your account.',
                    ),
                    const AdaptiveGap(height: 20),
                    Text(
                      'Confirm using a code sent to ${OfflineRuntime.client.auth.currentUser?.email ?? 'your email'}.',
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : () => run('request-code'),
                      child: Text(
                        sent ? 'Send a new code' : 'Send confirmation code',
                      ),
                    ),
                    if (sent)
                      const Text(
                        'Check your email for the sign-in code, then enter it below.',
                      ),
                    const AdaptiveGap(height: 16),
                    TextField(
                      controller: code,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Email confirmation code',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const AdaptiveGap(height: 20),
                    TextField(
                      controller: confirmation,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Type DELETE to confirm',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  if (error != null)
                    AdaptivePadding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const AdaptiveGap(height: 24),
                  FilledButton(
                    onPressed:
                        busy ||
                            (!pending &&
                                (confirmation.text.trim() != 'DELETE' ||
                                    code.text.trim().isEmpty))
                        ? null
                        : () => run(pending ? 'resume' : 'delete'),
                    child: Text(
                      busy
                          ? 'Please wait…'
                          : pending
                          ? 'Resume deletion'
                          : 'Permanently delete my account',
                    ),
                  ),
                  if (!pending)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      child: const Text('Keep my account'),
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

/// Recover a partially completed deletion after closing or refreshing the app.
class AccountDeletionGate extends StatefulWidget {
  final Widget child;
  const AccountDeletionGate({super.key, required this.child});
  @override
  State<AccountDeletionGate> createState() => _AccountDeletionGateState();
}

class _AccountDeletionGateState extends State<AccountDeletionGate> {
  late Future<bool> pending = _load();
  Future<bool> _load() async {
    final result = await OfflineRuntime.readThrough('deletion', () async {
      final row = await OfflineRuntime.client
          .from('account_deletions')
          .select('user_id')
          .eq('user_id', OfflineRuntime.client.auth.currentUser!.id)
          .maybeSingle();
      return {'pending': row != null};
    });
    return result['pending'] == true;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: pending,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (OfflineRuntime.enabled && snapshot.hasError) {
        // This gate sits above the app navigator. Its recovery controls need
        // their own route/overlay so Sync can open without unmounting the gate.
        return Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => RingMasterPageShell(
              title: 'Offline access',
              showAccountButton: false,
              showHomeButton: false,
              showBackButton: false,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Reconnect to verify this account before continuing.',
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () => setState(() => pending = _load()),
                      child: const Text('Retry account check'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      if (snapshot.data == true) {
        return Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const DeleteAccountScreen(resuming: true),
          ),
        );
      }
      return widget.child;
    },
  );
}
