import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/license_service.dart';

class LicenseUsageCard extends StatelessWidget {
  final LicenseStatus status;
  const LicenseUsageCard({super.key, required this.status});

  String? get warning {
    if (!status.hasActiveLicense) {
      return 'An active license is required to add active animals. Your existing records remain available.';
    }
    if (status.warningLevel >= 100) {
      final due = status.graceEndsAt;
      if (due != null && !DateTime.now().toUtc().isBefore(due.toUtc())) {
        return 'Your 30-day grace period has ended. Upgrade or mark animals sold or deceased to make room. You can still view, update and export existing records.';
      }
      if (due != null) {
        return 'Your 30-day grace period ends ${DateFormat.yMMMd().format(due.toLocal())}. Upgrade or mark animals sold or deceased to get below your limit.';
      }
      return 'You have reached your animal limit. Sync to confirm your 30-day grace period. Upgrade or mark animals sold or deceased to make room.';
    }
    if (status.warningLevel >= 95) {
      return 'Almost full — you have used at least 95% of your animal allowance.';
    }
    if (status.warningLevel >= 85) {
      return 'Your herd is growing — you have used at least 85% of your animal allowance.';
    }
    if (status.warningLevel >= 75) {
      return 'Plan ahead — you have used at least 75% of your animal allowance.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = status.warningLevel >= 95 || !status.hasActiveLicense
        ? theme.colorScheme.error
        : status.warningLevel >= 75
        ? const Color(0xFF936000)
        : theme.colorScheme.primary;
    final message = warning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(status.tierName, style: theme.textTheme.titleMedium),
                if (status.hasActiveLicense)
                  Text(
                    '\$${(status.annualPriceCents / 100).toStringAsFixed(0)}/year',
                  ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Breeder plans'),
                      content: const SingleChildScrollView(
                        child: Text(
                          'Hobby Breeder · \$49/year\n50 active animals · 1 herd\n\n'
                          'Professional Breeder · \$99/year\n250 active animals · 1 herd\nBuyer pedigree emails included\n\n'
                          'Top Tier · \$179/year\n1,000 active animals across up to 5 herds\nBuyer pedigree emails included\n\n'
                          'All plans include core records, pedigrees, health, breeding, sales, household sharing and Show connections.\n\n'
                          'Custom pedigree branding and saved layouts are planned for Professional and Top Tier; they are not available yet.\n\n'
                          'Contact RingMaster support to change your plan. Online payment checkout is not available yet.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('View plans'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${status.activeAnimals} / ${status.maxActiveAnimals} active animals',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Active animal usage',
              value: '${(status.fraction * 100).floor()} percent',
              child: LinearProgressIndicator(
                value: status.fraction.clamp(0.0, 1.0),
                color: color,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${status.currentRings} / ${status.maxRings} herds · Animal allowance is shared across this family’s herds.',
            ),
            const SizedBox(height: 4),
            const Text(
              'Sold, deceased, archived and pedigree-only records do not count.',
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            if (status.provisional) ...[
              const SizedBox(height: 8),
              const Text(
                'Includes saved changes on this device. Sync confirms current limits and grace dates.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
