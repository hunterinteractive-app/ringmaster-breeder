import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import '../services/family_service.dart';

class FamilyAccessScreen extends StatefulWidget {
  const FamilyAccessScreen({super.key});
  @override
  State<FamilyAccessScreen> createState() => _FamilyAccessScreenState();
}

class _FamilyAccessScreenState extends State<FamilyAccessScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _update({String action = 'list', String? id}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FamilyService.refresh(
        action: action,
        id: id,
        email: action == 'invite' ? _email.text : null,
      );
      if (!mounted) return;
      if (action == 'invite') {
        _email.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Invitation created. Ask your family member to sign in with this email and open Family Access.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to update family access. Check the email address and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Family Access',
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Invite family members to access all Rings, animals, weights, health records, and pedigrees in your family. Each member signs in with their own email.',
        ),
        const SizedBox(height: 12),
        const Text(
          'The family owner manages invitations and the license. Members can leave, and owners can revoke access at any time.',
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Family member’s email'),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _busy ? null : () => _update(action: 'invite'),
          child: const Text('Create invitation'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Semantics(liveRegion: true, child: Text(_error!)),
          ),
        const SizedBox(height: 24),
        Text(
          'Invitations and members',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (!_busy && FamilyService.invitations.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No invitations yet.'),
          ),
        ...FamilyService.invitations.map((invite) {
          final owner = invite['is_owner'] == true;
          final accepted = invite['accepted_at'] != null;
          return Card(
            child: ListTile(
              title: Text(
                owner
                    ? invite['email'] as String
                    : invite['owner_email'] as String,
              ),
              subtitle: Text(
                accepted
                    ? 'Family member'
                    : 'Invitation expires ${invite['expires_at'].toString().split('T').first}',
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  if (!owner && !accepted)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _update(action: 'accept', id: invite['id']),
                      child: const Text('Accept'),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _update(
                            action: owner ? 'revoke' : 'leave',
                            id: invite['id'],
                          ),
                    child: Text(
                      owner
                          ? 'Revoke'
                          : accepted
                          ? 'Leave'
                          : 'Decline',
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    ),
  );
}
