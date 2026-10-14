import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../services/pedigree_email_service.dart';

Future<void> offerBuyerPedigree(
  BuildContext context, {
  required String animalId,
  String? saleId,
  String buyerEmail = '',
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PedigreeEmailDialog(
      animalId: animalId,
      saleId: saleId,
      buyerEmail: buyerEmail,
    ),
  );
}

class PedigreeEmailDialog extends StatefulWidget {
  final String animalId;
  final String? saleId;
  final String buyerEmail;
  final PedigreeEmailGateway? gateway;
  const PedigreeEmailDialog({
    super.key,
    required this.animalId,
    this.saleId,
    this.buyerEmail = '',
    this.gateway,
  });
  @override
  State<PedigreeEmailDialog> createState() => _PedigreeEmailDialogState();
}

class _PedigreeEmailDialogState extends State<PedigreeEmailDialog> {
  late final gateway = widget.gateway ?? PedigreeEmailService();
  late final recipient = TextEditingController(text: widget.buyerEmail);
  final requestId = PedigreeEmailService.requestId();
  PedigreeEmailDraft? draft;
  String? error, submittedRecipient;
  bool loading = true, sending = false, accepted = false;
  @override
  void initState() {
    super.initState();
    prepare();
  }

  @override
  void dispose() {
    recipient.dispose();
    super.dispose();
  }

  Future<void> prepare() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await gateway.prepare(
        requestId,
        widget.animalId,
        widget.saleId,
      );
      if (mounted) {
        setState(() {
          draft = result;
          if (recipient.text.trim().isEmpty) {
            recipient.text = result.buyerEmail;
          }
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e is StateError
              ? e.message
              : 'Unable to prepare the pedigree. Your sale is saved.';
        });
      }
    }
  }

  Future<void> send() async {
    if (sending || draft == null) return;
    final email = recipient.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+$').hasMatch(email)) {
      setState(() => error = 'Enter the buyer’s email address.');
      return;
    }
    if (submittedRecipient != null && submittedRecipient != email) {
      setState(
        () => error =
            'Check the previous email request before sending to a different address.',
      );
      return;
    }
    setState(() {
      sending = true;
      error = null;
      submittedRecipient = email;
    });
    try {
      await gateway.send(draft!, widget.animalId, email);
      if (mounted) {
        setState(() {
          sending = false;
          accepted = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          sending = false;
          error = e is StateError
              ? e.message
              : 'Email was not confirmed. Retry this same request; your sale is saved.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !sending,
    child: AlertDialog(
      title: Text(
        accepted ? 'Pedigree email submitted' : 'Email pedigree to buyer?',
      ),
      content: SizedBox(
        width: 510,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (accepted)
                Text(
                  'The email provider accepted the pedigree email for $submittedRecipient. This does not yet confirm inbox delivery.',
                )
              else ...[
                const Text(
                  'The animal is marked Sold. You can email its pedigree now or send it later.',
                ),
                const SizedBox(height: 12),
                if (loading) const Center(child: CircularProgressIndicator()),
                if (draft != null) ...[
                  Text('From: ${draft!.ownerName}'),
                  Text('Replies go to: ${draft!.ownerEmail}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: recipient,
                    readOnly: sending || submittedRecipient != null,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Buyer email'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Attachments: pedigree.pdf and pedigree.json'),
                  const Text(
                    'Prices, payments, private sale notes, and buyer details are excluded.',
                  ),
                  TextButton.icon(
                    onPressed: sending
                        ? null
                        : () => Printing.layoutPdf(
                            onLayout: (_) async => draft!.pdf,
                          ),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Preview pedigree PDF'),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (!loading && draft == null)
                  TextButton(
                    onPressed: prepare,
                    child: const Text('Try preparing again'),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: sending ? null : () => Navigator.pop(context),
          child: Text(accepted ? 'Done' : 'Later'),
        ),
        if (!accepted)
          FilledButton(
            onPressed: loading || sending || draft == null ? null : send,
            child: Text(
              sending
                  ? 'Sending…'
                  : submittedRecipient == null
                  ? 'Send PDF and JSON'
                  : 'Retry same email',
            ),
          ),
      ],
    ),
  );
}
