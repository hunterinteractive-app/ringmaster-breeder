import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class LicenseStatus {
  final bool hasActiveLicense;
  final String tierCode;
  final int maxRings;
  final int currentRings;

  LicenseStatus({
    required this.hasActiveLicense,
    required this.tierCode,
    required this.maxRings,
    required this.currentRings,
  });
}

Future<LicenseStatus> fetchLicenseStatus(String userId) async {
  // 1. Get active license
  final license = await supabase
      .from('user_licenses')
      .select('tier_code, license_tiers(max_rings)')
      .eq('user_id', userId)
      .eq('status', 'active')
      .or(
        'expires_at.is.null,expires_at.gt.${DateTime.now().toUtc().toIso8601String()}',
      )
      .order('started_at', ascending: false)
      .limit(1)
      .maybeSingle();

  if (license == null) {
    return LicenseStatus(
      hasActiveLicense: false,
      tierCode: 'FREE',
      maxRings: 0,
      currentRings: 0,
    );
  }

  final String tierCode = license['tier_code'];
  final int maxRings = license['license_tiers']['max_rings'];

  // 2. Count how many Rings the user owns
  final ringCount = await supabase
      .from('farms')
      .select()
      .eq('owner_id', userId)
      .eq('is_demo', false);

  return LicenseStatus(
    hasActiveLicense: true,
    tierCode: tierCode,
    maxRings: maxRings,
    currentRings: ringCount.length,
  );
}
