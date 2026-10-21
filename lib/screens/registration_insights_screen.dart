import 'package:flutter/material.dart';
import '../services/registration_feedback_service.dart';
import '../widgets/ringmaster_page_shell.dart';

class RegistrationInsightsScreen extends StatefulWidget {
  final RegistrationFeedbackRequest request;
  const RegistrationInsightsScreen({
    super.key,
    this.request = RegistrationFeedbackService.call,
  });
  @override
  State<RegistrationInsightsScreen> createState() =>
      _RegistrationInsightsScreenState();
}

class _RegistrationInsightsScreenState
    extends State<RegistrationInsightsScreen> {
  List<dynamic> rows = [];
  bool busy = true, more = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool append = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.request('admin-list', {
        'offset': append ? rows.length : 0,
      });
      if (mounted) {
        setState(() {
          rows = append
              ? [...rows, ...result['responses']]
              : result['responses'];
          more = result['more'] == true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Unable to load responses. Super Admin access and an internet connection are required.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Registration insights',
    onRefresh: busy ? null : () => load(),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Optional member responses, newest updates first. Referral counts are linked signups, not earned rewards. Names without an exact email or referral-code match remain self-reported.',
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (!busy && error == null && rows.isEmpty)
          const Text('No responses yet.'),
        for (final row in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (row['display_name'] ?? '').toString().isEmpty
                        ? row['email']
                        : row['display_name'],
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SelectableText(row['email'] ?? ''),
                  Text(
                    'Herd tracking: ${(row['herd_tracking'] ?? '').toString().isEmpty ? 'Not answered' : row['herd_tracking']}',
                  ),
                  Text(
                    'Referred by: ${(row['referred_by'] ?? '').toString().isEmpty ? 'Not answered' : row['referred_by']}',
                  ),
                  if (row['referrer_email'] != null)
                    Text(
                      'Matched referrer: ${row['referrer_name'] ?? ''} · ${row['referrer_email']}',
                    ),
                  Text(
                    'Their referral code: ${row['referral_code']} · ${row['referred_signups']} referred signups',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Feature requests: ${(row['requested_features'] ?? '').toString().isEmpty ? 'Not answered' : row['requested_features']}',
                  ),
                ],
              ),
            ),
          ),
        if (more)
          OutlinedButton(
            onPressed: busy ? null : () => load(append: true),
            child: const Text('Load more responses'),
          ),
      ],
    ),
  );
}
