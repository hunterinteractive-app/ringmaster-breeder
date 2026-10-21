import '../offline/offline_runtime.dart';

class LicenseStatus {
  final bool hasActiveLicense;
  final String tierCode, tierName;
  final int maxRings, currentRings, maxActiveAnimals, activeAnimals;
  final int annualPriceCents;
  final bool buyerPedigreeEmail, customPedigreeBranding, savedPedigreeLayouts;
  final bool growthBlocked, provisional;
  final DateTime? graceEndsAt;

  const LicenseStatus({
    required this.hasActiveLicense,
    required this.tierCode,
    required this.maxRings,
    required this.currentRings,
    this.tierName = 'Breeder',
    this.maxActiveAnimals = 0,
    this.activeAnimals = 0,
    this.annualPriceCents = 0,
    this.buyerPedigreeEmail = false,
    this.customPedigreeBranding = false,
    this.savedPedigreeLayouts = false,
    this.growthBlocked = false,
    this.provisional = false,
    this.graceEndsAt,
  });

  factory LicenseStatus.fromJson(Map<String, dynamic> data) => LicenseStatus(
    hasActiveLicense: data['active'] == true,
    tierCode: data['code'] as String? ?? 'FREE',
    tierName: data['name'] as String? ?? 'No active license',
    maxRings: (data['max_rings'] as num?)?.toInt() ?? 0,
    currentRings: (data['current_rings'] as num?)?.toInt() ?? 0,
    maxActiveAnimals: (data['max_active_animals'] as num?)?.toInt() ?? 0,
    activeAnimals: (data['active_count'] as num?)?.toInt() ?? 0,
    annualPriceCents: (data['annual_price_cents'] as num?)?.toInt() ?? 0,
    buyerPedigreeEmail: data['buyer_pedigree_email'] == true,
    customPedigreeBranding: data['custom_pedigree_branding'] == true,
    savedPedigreeLayouts: data['saved_pedigree_layouts'] == true,
    growthBlocked: data['growth_blocked'] == true,
    provisional: data['provisional'] == true,
    graceEndsAt: DateTime.tryParse(data['grace_ends_at'] as String? ?? ''),
  );

  double get fraction =>
      maxActiveAnimals > 0 ? activeAnimals / maxActiveAnimals : 0;
  int get warningLevel {
    if (maxActiveAnimals <= 0) return 0;
    for (final level in [100, 95, 85, 75]) {
      if (activeAnimals * 100 >= maxActiveAnimals * level) return level;
    }
    return 0;
  }
}

Future<LicenseStatus> fetchLicenseStatus(String userId) async {
  // The server owns counts, plan selection, and the 30-day clock. Full offline
  // workspaces project the same response from their private downloaded tables.
  final data = await OfflineRuntime.readThrough(
    'license-usage:$userId',
    () async {
      return Map<String, dynamic>.from(
        await OfflineRuntime.client.rpc(
              'breeder_license_status',
              params: {'p_owner': userId},
            )
            as Map,
      );
    },
  );
  return LicenseStatus.fromJson(data);
}
