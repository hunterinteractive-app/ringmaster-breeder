import 'package:flutter/material.dart';
import '../../widgets/ringmaster_page_shell.dart';

class LegalScreen extends StatelessWidget {
  final bool privacy;
  const LegalScreen({super.key, this.privacy = false});
  @override
  Widget build(BuildContext context) {
    final sections = privacy ? privacySections : termsSections;
    return RingMasterPageShell(
      title: privacy ? 'Privacy Policy' : 'Terms of Service',
      showHomeButton: false,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Effective date: October 9, 2026 • Version 2026-10',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    privacy
                        ? 'Hunter Interactive LLC, doing business as RingMaster One, provides RingMaster Breeder. This policy explains how we handle information associated with the service.'
                        : 'RingMaster Breeder is provided by Hunter Interactive LLC, doing business as RingMaster One (“Company,” “we,” “us,” or “our”).',
                  ),
                  const SizedBox(height: 16),
                  for (final section in sections) ...[
                    Text(
                      section.$1,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(section.$2, style: const TextStyle(height: 1.6)),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const termsSections = <(String, String)>[
  (
    "1. Use of the Platform",
    "RingMaster Breeder provides tools for rabbit and cavy records, pedigrees, breeding records, animal health and weight records, family collaboration, private sales records, and supported imports and integrations. Available features depend on your subscription and the current release.\n\nThe platform provides recordkeeping tools. It does not provide veterinary advice, certify pedigrees, verify ownership, or guarantee breeding outcomes.",
  ),
  (
    "2. Eligibility and Account Security",
    "Independent account holders must be at least 13 years old. Parents or guardians may manage younger children’s exhibitor information when they have appropriate authority.\n\nUse your own login credentials, protect your account, and report suspected unauthorized access promptly. Family members should use separate accounts rather than share login codes.",
  ),
  (
    "3. Family Access",
    "Invited family members can view, add, edit, delete, and export shared Breeder records, including private buyer information and sale amounts.\n\nOnly the family owner manages invitations, billing, and closure or permanent deletion of the family’s account. Owners are responsible for inviting appropriate people and removing access when necessary.",
  ),
  (
    "4. Records, Imports, and Synchronization",
    "Users are responsible for reviewing animal identities, parent relationships, pedigrees, imported records, show results, and other information for accuracy.\n\nWhere supported and enabled, Breeder supplies current animal identity information to connected show programs and receives associated results automatically. Setup will explain the connection and provide controls to disable it.\n\nSaved show entries preserve the animal information recorded when the entry was saved. Later changes to Breeder records do not automatically rewrite saved entries or historical results.\n\nIntegration availability depends on the supported program. Imports and matching may require review; users should resolve uncertain matches before relying on records.",
  ),
  (
    "5. Private Sales Records and Pedigree Sharing",
    "Users may record buyer contact information, notes, sale amounts, and other private transaction details, and share selected pedigree information.\n\nUsers must have authority to enter another person’s information and should share only what is appropriate. Buyer contact details, private notes, and sale amounts are excluded from shared pedigrees by default.\n\nBreeder does not currently provide a public marketplace or process animal-sale payments. The Company is not a party to animal sales and does not guarantee an animal’s ownership, health, condition, pedigree, delivery, or suitability.",
  ),
  (
    "6. Subscriptions",
    "Breeder offers monthly and yearly subscriptions. Price, billing interval, renewal arrangements, cancellation instructions, and any refund terms will be disclosed before purchase.\n\nUnless otherwise stated or required by applicable law, monthly and yearly subscription payments are non-refundable. The Company may issue refunds or credits at its discretion on a case-by-case basis.\n\nClosing an account must stop future subscription renewals. Cancelling renewal allows access through the paid subscription period unless the account is closed sooner.",
  ),
  (
    "7. Expiration and Account Closure",
    "When a subscription expires without renewal, or an owner closes the account, the account enters a 30-day period of read-only access with exports allowed.\n\nAfter 30 days, access to stored Breeder records is locked. Records remain recoverable by renewing the subscription until one year from the closure or subscription-expiration date, whichever triggered the inactive period first.\n\nAt that one-year deadline, the stored account records are scheduled for deletion. Renewing before the deadline restores access and ends that inactive period. Closing an already inactive account does not restart the deadline.\n\nUsers should export records they wish to keep before access is locked.",
  ),
  (
    "8. Permanent Deletion",
    "Permanent deletion is separate from account closure and requires identity verification and explicit confirmation.\n\nPermanent deletion removes the account and its privately held Breeder records from active systems and cannot be reversed through subscription renewal. Deleting the family owner’s account also removes the family records held under that account; deleting an invited member’s account removes their access without deleting the owner’s shared records.\n\nPermanently deleted data is removed from active systems. Copies may remain in restricted backups until those backups expire under our retention schedule. If a backup is restored, previously requested deletions will be reapplied before affected records become accessible.\n\nLimited records may remain where legally required. Independent copies already shared, exported, or held in other programs are outside the deletion scope.",
  ),
  (
    "9. Uploaded Content and Acceptable Use",
    "You retain ownership of your submitted content and grant the Company permission to store, process, display, and transmit it as necessary to provide the service.\n\nYou must have the right to upload and share that content. Do not submit unlawful content, impersonate others, access records without authorization, introduce malicious software, or disrupt the platform.",
  ),
  (
    "10. Availability and Third-Party Services",
    "The platform is provided “as is” and “as available,” to the extent permitted by law. We do not guarantee uninterrupted operation, error-free records, or compatibility with every external program.\n\nWe may modify or suspend features for maintenance, security, legal compliance, or business reasons. Hosting, authentication, email, storage, and payment providers may have separate terms.",
  ),
  (
    "11. Intellectual Property",
    "The platform’s software, branding, designs, and related materials belong to the Company or its licensors. Users may not copy, distribute, or reverse engineer them except as permitted by law or written authorization.",
  ),
  (
    "12. Liability",
    "To the fullest extent permitted by law, the Company is not liable for indirect or consequential losses, lost records, incorrect pedigrees or results, breeding outcomes, animal-sale disputes, or actions taken by authorized family members.\n\nThe Company’s aggregate liability relating to the affected subscription or service is limited to the amount you paid the Company for that service during the 12 months preceding the claim. These provisions do not limit liability that cannot lawfully be excluded or limited.",
  ),
  (
    "13. Governing Law and Other Provisions",
    "Indiana law governs these Terms, subject to applicable mandatory law. Proceedings must be brought in the state courts of Delaware County, Indiana, or, where federal jurisdiction exists, the United States District Court for the Southern District of Indiana, Indianapolis Division, except where applicable law requires otherwise.\n\nEvents outside our reasonable control may prevent performance. If a provision is unenforceable, the remaining provisions remain effective. These Terms, the Privacy Policy, and applicable subscription or written service agreements form the agreement governing the service.",
  ),
  (
    "14. Changes and Contact",
    "We will provide notice of material changes and request renewed acceptance where appropriate or required.\n\nContact Hunter Interactive LLC, doing business as RingMaster One, at support@ringmasterone.com.",
  ),
];

const privacySections = <(String, String)>[
  (
    "1. Information We Collect",
    "We collect information needed for enabled features, which may include:\n\n• Account identifiers, email addresses, authentication information, and contact details.\n• Family memberships and exhibitor profiles, including authorized information about dependents.\n• Animal identities, parent relationships, pedigrees, breeding, health, weight, and show records.\n• Private sale records, including buyer name, address, email, phone, notes, and amount paid.\n• Uploaded images, documents, support messages, and diagnostic information.\n• Subscription and transaction information processed through payment providers.\n• Device, browser, IP address, and security information associated with service operation.\n\nInformation may come from you, authorized family members, supported integrations, or your use of the platform.",
  ),
  (
    "2. How We Use Information",
    "We use information to operate accounts and features, maintain records, provide authorized sharing and integrations, manage subscriptions, deliver account notices, provide support, protect security, and meet applicable legal obligations.\n\nWe do not sell personal information.",
  ),
  (
    "3. Family Access",
    "Invited family members have full access to shared Breeder records, including buyer contact details, private notes, and sale amounts. The family owner controls invitations and is responsible for reviewing access.\n\nRemoving a member prevents future access through their account but cannot recall copies they previously downloaded or received.",
  ),
  (
    "4. Connected Programs",
    "Where supported and enabled, connected show programs use current Breeder animal identity information, and show results are brought into Breeder automatically.\n\nSetup explains these connections and provides an option to disable synchronization. Previously saved show entries retain their historical animal details. Disabling a connection does not automatically remove records already imported or transferred.\n\nMatching and transfer must be limited to records the user is authorized to access.",
  ),
  (
    "5. Sales Records and Shared Pedigrees",
    "Sales records are private to the authorized family. Pedigree sharing includes only selected information; buyer contact details, private notes, and sale amounts are excluded by default.\n\nUsers who record buyer or dependent information must have appropriate authority. Recipients of shared pedigrees or exports control their own copies.",
  ),
  (
    "6. Service Providers and Other Disclosures",
    "We share information with providers as needed for hosting, authentication, email, storage, payment processing, security, and support.\n\nWe may disclose limited information where legally required or reasonably necessary to address fraud, security incidents, disputes, or protection of rights. We do not make private family records publicly available merely because a user maintains sales records.",
  ),
  (
    "7. Retention and Account Closure",
    "Active account records are retained to provide the service.\n\nClosure or subscription expiration begins a 30-day read-only period with exports allowed. Records are then locked but remain recoverable through subscription renewal until one year from the event that began the inactive period.\n\nRenewal before that deadline restores access and ends the inactive period. Otherwise, stored account records are scheduled for deletion at the one-year deadline.\n\nLimited billing, legal, and security records may require separate retention periods. Retention must be limited to the information and time necessary for those purposes.",
  ),
  (
    "8. Permanent Deletion",
    "Verified, confirmed permanent deletion removes the account and its privately held Breeder records from active systems. Deleting an invited member’s account does not delete the family owner’s records.\n\nPermanently deleted data is removed from active systems. Copies may remain in restricted backups until those backups expire under our retention schedule. If a backup is restored, previously requested deletions will be reapplied before affected records become accessible.\n\nIndependent exports, shared pedigrees, and records held by other programs or recipients are not erased by a Breeder deletion request.\n\nAny legally required retention exception will be explained where applicable.",
  ),
  (
    "9. Security and Browser Storage",
    "We use reasonable safeguards, authentication, and access restrictions. No online service can guarantee absolute security.\n\nBrowser storage and authentication tokens may keep users signed in and support essential features. Disabling them may affect operation.",
  ),
  (
    "10. Children’s Information",
    "Independent accounts are limited to users aged 13 and older. Parents or guardians may manage younger children’s exhibitor information when appropriate and authorized.\n\nWe do not permit children under 13 to independently create accounts. Concerns about a child’s information should be sent to support so we can investigate and take appropriate action.",
  ),
  (
    "11. Choices, Rights, and Contact",
    "You may request access, correction, export, or deletion of your personal information at support@ringmasterone.com. We may verify identity and authority before acting.\n\nCopies independently held by another family owner, buyer, show program, or organization may require a request to that recipient. Nothing in this policy limits rights available under applicable privacy law.\n\nInformation may be processed where our service providers operate, with safeguards where required.",
  ),
  (
    "12. Policy Changes",
    "We will identify the effective date and version and provide notice of material changes. Where consent is required for a new use or disclosure, we will obtain it before applying that change.",
  ),
];
