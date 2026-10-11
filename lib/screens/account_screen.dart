import 'package:flutter/material.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'family_access_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Account',
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Family access'),
            subtitle: const Text(
              'Invite family members and manage shared access.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const FamilyAccessScreen(),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
