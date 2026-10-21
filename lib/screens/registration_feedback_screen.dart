import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/registration_feedback_service.dart';
import '../widgets/ringmaster_page_shell.dart';

class RegistrationFeedbackScreen extends StatefulWidget {
  final RegistrationFeedbackRequest request;
  final VoidCallback? onContinue;
  final Map<String, dynamic>? initial;
  const RegistrationFeedbackScreen({
    super.key,
    this.request = RegistrationFeedbackService.call,
    this.onContinue,
    this.initial,
  });
  @override
  State<RegistrationFeedbackScreen> createState() =>
      _RegistrationFeedbackScreenState();
}

class _RegistrationFeedbackScreenState
    extends State<RegistrationFeedbackScreen> {
  final tracking = TextEditingController(),
      referral = TextEditingController(),
      features = TextEditingController();
  Map<String, dynamic>? data;
  bool busy = true;
  String? message;
  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      fill(widget.initial!);
    } else {
      load();
    }
  }

  void fill(Map<String, dynamic> value) {
    data = value;
    tracking.text = value['herd_tracking'] ?? '';
    referral.text = value['referred_by'] ?? '';
    features.text = value['requested_features'] ?? '';
    busy = false;
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final result = await widget.request('status', {});
      if (mounted) setState(() => fill(result));
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Connect to the internet to load your answers.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result = await widget.request('save', {
        'herd_tracking': tracking.text.trim(),
        'referred_by': referral.text.trim(),
        'requested_features': features.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        data = result;
        message = 'Your answers are saved. Thank you!';
      });
      widget.onContinue?.call();
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Your answers could not be saved. Please retry online, or continue and answer later in Account.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> skip() async {
    setState(() => busy = true);
    try {
      await widget.request('skip', {});
    } catch (_) {
      /* Optional questions never block access, including when offline. */
    }
    if (mounted) {
      setState(() => busy = false);
      widget.onContinue?.call();
    }
  }

  @override
  void dispose() {
    tracking.dispose();
    referral.dispose();
    features.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: widget.onContinue == null
        ? 'Your feedback & referrals'
        : 'A little about your herd',
    showAccountButton: widget.onContinue == null,
    showHomeButton: widget.onContinue == null,
    showBackButton: widget.onContinue == null,
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'All three questions are optional. Your answers help us improve RingMaster Breeder. You can add or update feedback in Account anytime. Your original referral is kept once submitted.',
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        if (message != null) Text(message!),
        if (data == null && !busy)
          TextButton(
            onPressed: load,
            child: const Text('Retry loading answers'),
          ),
        const Text('How have you been tracking your herd?'),
        const SizedBox(height: 8),
        TextField(
          controller: tracking,
          enabled: !busy && data != null,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Previous tracking (optional)',
            hintText:
                'Paper records, spreadsheets, Rabbit Register, Kintraks, another app, or just getting started',
          ),
        ),
        const SizedBox(height: 16),
        const Text('Were you referred by someone?'),
        const SizedBox(height: 8),
        TextField(
          controller: referral,
          enabled: !busy && data != null && data?['referral_recorded'] != true,
          maxLength: 254,
          decoration: InputDecoration(
            labelText: 'Referrer (optional)',
            hintText: 'Their referral code, email address, or name',
            helperText: data?['referral_recorded'] == true
                ? 'Your original referral has been recorded.'
                : null,
          ),
        ),
        const SizedBox(height: 16),
        const Text('What features would you like us to add?'),
        const SizedBox(height: 8),
        TextField(
          controller: features,
          enabled: !busy && data != null,
          maxLength: 4000,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Feature ideas (optional)',
            hintText: 'Tell us what would make managing your herd easier.',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy || data == null ? null : save,
          child: Text(
            widget.onContinue == null ? 'Save answers' : 'Save & continue',
          ),
        ),
        if (widget.onContinue != null)
          TextButton(
            onPressed: busy ? null : skip,
            child: const Text('Skip for now'),
          ),
        if (widget.onContinue == null && data != null) ...[
          const SizedBox(height: 24),
          Text(
            'Your referral code',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SelectableText(data!['referral_code'] ?? ''),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: data!['referral_code'] ?? ''),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Referral code copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy referral code'),
          ),
          Text('Referred signups: ${data!['referred_signups'] ?? 0}'),
          const Text(
            'This counts active signups linked to your code or email. Referral rewards are not currently enabled.',
          ),
        ],
      ],
    ),
  );
}

/// Optional first-time survey, after profile setup. Existing accounts use Account instead.
class RegistrationFeedbackGate extends StatefulWidget {
  final Widget child;
  final RegistrationFeedbackRequest request;
  const RegistrationFeedbackGate({
    super.key,
    required this.child,
    this.request = RegistrationFeedbackService.call,
  });
  @override
  State<RegistrationFeedbackGate> createState() =>
      _RegistrationFeedbackGateState();
}

class _RegistrationFeedbackGateState extends State<RegistrationFeedbackGate> {
  bool done = false;
  Map<String, dynamic>? data;
  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    try {
      final value = await widget
          .request('status', {})
          .timeout(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          data = value;
          done = value['show_onboarding'] != true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => done = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (done) return widget.child;
    if (data == null) return const Center(child: CircularProgressIndicator());
    return Navigator(
      onDidRemovePage: (_) {},
      pages: [
        MaterialPage<void>(
          child: RegistrationFeedbackScreen(
            request: widget.request,
            initial: data,
            onContinue: () => setState(() => done = true),
          ),
        ),
      ],
    );
  }
}
