import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../utils/device_timezone.dart';

class CalendarSubscriptionDialog extends StatefulWidget {
  final String ringId;
  const CalendarSubscriptionDialog({super.key, required this.ringId});
  @override
  State<CalendarSubscriptionDialog> createState() =>
      _CalendarSubscriptionDialogState();
}

class _CalendarSubscriptionDialogState
    extends State<CalendarSubscriptionDialog> {
  bool busy = true, enabled = false;
  String? token, error, notice;
  String get url =>
      '${AppConfig.supabaseUrl}/functions/v1/calendar-feed?token=$token';
  @override
  void initState() {
    super.initState();
    request('status');
  }

  Future<void> request(String action) async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final data = await Supabase.instance.client.rpc(
        'manage_calendar_subscription',
        params: {
          'p_ring': widget.ringId,
          'p_action': action,
          'p_timezone': deviceTimezone(),
        },
      );
      if (mounted) {
        setState(() {
          enabled = data['enabled'] == true;
          token = data['token'];
          if (action == 'revoke') {
            notice =
                'Link disabled. Remove the subscribed calendar from your devices to clear any saved events.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to update the calendar link. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirm(String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          action == 'revoke'
              ? 'Disconnect device calendar?'
              : 'Replace private link?',
        ),
        content: Text(
          action == 'revoke'
              ? 'Devices using this link will stop receiving updates. You can create a new link later.'
              : 'The old link will stop working. You will need to add the new link on each subscribed device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action == 'revoke' ? 'Disconnect' : 'Replace link'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await request(action);
  }

  Future<void> launchApple() async {
    try {
      if (!await launchUrl(
        Uri.parse(url.replaceFirst('https:', 'webcal:')),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('No calendar app');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => notice =
              'Copy the link, then paste it into Apple Calendar → Add Calendar → Add Subscription Calendar.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect your device calendar'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Subscribe to this herd’s breeding, health, entered-show dates and favorite-show deadlines. Your calendar app refreshes on its own schedule.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notifications_active_outlined),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Check your calendar alerts',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Favorite-show deadlines include alerts 1 day and 2 hours before. Some calendar apps ignore alerts supplied by subscriptions, so you may need to set notifications in your calendar app.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This private link lets anyone who has it read these calendar details. Share it only with calendar apps and people you trust.',
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(notice!),
              ),
            if (!enabled && !busy)
              FilledButton.icon(
                onPressed: () => request('create'),
                icon: const Icon(Icons.link),
                label: const Text('Create private calendar link'),
              ),
            if (enabled && token != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : launchApple,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Open Apple Calendar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: url));
                            if (mounted) {
                              setState(() => notice = 'Calendar link copied.');
                            }
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy subscription link'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'iPhone / iPad',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'Open Apple Calendar above, or paste the link into Calendar → Calendars → Add Calendar → Add Subscription Calendar. Choose iCloud to use it across your Apple devices.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Android / Google Calendar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'On a computer, open Google Calendar → Other calendars + → From URL. Paste the link and add the calendar. It will then be available in Google Calendar on your phone. Initial setup is not available in the Google Calendar mobile app.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Other calendar apps',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'Choose Subscribe from URL / Subscribe from web and paste the link. Subscribe rather than importing a file to keep receiving updates.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: busy ? null : () => confirm('rotate'),
                    child: const Text('Replace private link'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => confirm('revoke'),
                    child: const Text('Disconnect devices'),
                  ),
                ],
              ),
            ],
            if (error != null)
              TextButton(
                onPressed: busy ? null : () => request('status'),
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
