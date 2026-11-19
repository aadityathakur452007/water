// Privacy Policy and Legal Terms screen for Shodasha Mineral Waters.
// Formulated in strict compliance with the Digital Personal Data Protection
// Act, 2023 (DPDP Act), IT SPDI Rules 2011, and CERT-In Cyber Directions 2022.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PrivacyPolicyScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShodashaTheme.bg,
      appBar: AppBar(
        backgroundColor: ShodashaTheme.surface,
        foregroundColor: ShodashaTheme.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Privacy Policy & Terms',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: ShodashaTheme.ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        children: [
          _complianceBanner(),
          const SizedBox(height: AppSpacing.md),
          _quickSummaryCard(),
          const SizedBox(height: AppSpacing.md),
          _policySection(
            icon: Icons.inventory_2_outlined,
            title: '1. Data We Collect & Purpose Limitation',
            tag: 'DPDP ACT SEC 5 & 6',
            body:
                'We only collect information strictly required to fulfill your '
                'water deliveries and maintain reusable jar inventory:\n\n'
                '• Mobile Number & Name: For secure OTP login, delivery route '
                'coordination, and critical service notifications.\n'
                '• Delivery Address & GPS Coordinates: Exclusively used by '
                'assigned delivery partners to reach your door.\n'
                '• Order & Jar Ledger: To track bottles delivered and empty '
                'jars returned, preventing asset disputes.\n\n'
                'We never sell your data, use it for third-party advertisements, '
                'or track your activities outside our delivery services.',
          ),
          const SizedBox(height: AppSpacing.md),
          _policySection(
            icon: Icons.lock_outline_rounded,
            title: '2. Data Storage & Security Safeguards',
            tag: 'AES-256 · TLS 1.3',
            body:
                'All personal information is secured with bank-grade encryption '
                'in transit (TLS 1.3) and at rest (AES-256) hosted on secure Indian '
                'cloud infrastructure.\n\n'
                'Role-Based Access Control (RBAC): Delivery riders can only see '
                'the name, address, and phone number of stops assigned to their '
                'current shift. They have zero access to your billing history '
                'or other user records.',
          ),
          const SizedBox(height: AppSpacing.md),
          _policySection(
            icon: Icons.shield_outlined,
            title: '3. Data Breach & Incident Response',
            tag: 'CERT-IN & DPDP ACT SEC 8(6)',
            body:
                'Shodasha adheres to strict incident handling policies. In the '
                'unlikely event of any unauthorized data access or security incident:\n\n'
                '• 6-Hour Reporting: We immediately notify the Indian Computer '
                'Emergency Response Team (CERT-In) within 6 hours of discovery.\n'
                '• User Breach Notification: We inform every affected user and '
                'the Data Protection Board of India without delay, detailing the '
                'nature of the incident, data impacted, mitigation taken, and '
                'recommended safety steps.\n'
                '• Zero Cover-Up Guarantee: We believe in complete transparency '
                'and proactive security containment.',
          ),
          const SizedBox(height: AppSpacing.md),
          _policySection(
            icon: Icons.assignment_return_outlined,
            title: '4. ₹650 Reusable Jar Asset Terms',
            tag: 'REUSABLE CONTAINER RULES',
            body:
                'Shodasha delivers water in premium 20L food-grade polycarbonate '
                'jars without charging advance deposit for convenience.\n\n'
                '• Empty Jar Return: Empty jars remain the property of Shodasha '
                'and must be returned to the delivery partner on the next order.\n'
                '• Damage or Loss Charge: If a jar is physically cracked, broken, '
                'contaminated, or lost/unreturned, a replacement charge of ₹650 '
                'per jar will be billed to your account.\n'
                '• Explicit Agreement: You are prompted to confirm this agreement '
                'on each order checkout.',
          ),
          const SizedBox(height: AppSpacing.md),
          _policySection(
            icon: Icons.person_outline_rounded,
            title: '5. Your Rights as a Data Principal',
            tag: 'DPDP ACT SEC 11-13',
            body:
                'Under Indian law, you have full control over your personal data:\n\n'
                '• Right to Access: View your addresses, orders, and wallet balance '
                'anytime in-app.\n'
                '• Right to Correction: Edit your name, phone number, and delivery '
                'addresses directly from the Profile section.\n'
                '• Right to Erasure: Request deletion of your account and personal '
                'data once outstanding orders, dues, and reusable jars are settled.',
          ),
          const SizedBox(height: AppSpacing.md),
          _policySection(
            icon: Icons.support_agent_outlined,
            title: '6. Grievance Redressal Officer',
            tag: 'STATUTORY REDRESSAL',
            body:
                'If you have any questions, feedback, or data privacy complaints, '
                'contact our designated Grievance Officer:\n\n'
                'Officer: Data Protection & Grievance Cell\n'
                'Entity: Shodasha Mineral Waters Pvt. Ltd.\n'
                'Location: Bhopal, Madhya Pradesh, India - 462001\n'
                'Email: support@shodashawater.com\n\n'
                'Acknowledgment: Within 48 hours.\n'
                'Resolution: Within 30 days under Indian IT & DPDP rules.',
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Request Account & Data Deletion',
            kind: AppButtonKind.secondary,
            icon: Icons.delete_outline_rounded,
            onPressed: () => _showAccountDeletionSheet(context),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _complianceBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: ShodashaTheme.tealTint,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        border: Border.all(color: ShodashaTheme.teal.withValues(alpha: 0.2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_rounded, color: ShodashaTheme.teal, size: 22),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DPDP Act 2023 Compliant',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.tealDeep,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Your data is protected under Indian privacy laws. We collect '
                  'only what is necessary and never monetize your data.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        border: Border.all(color: ShodashaTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Privacy at a Glance',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ShodashaTheme.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _summaryPoint(Icons.check_circle_outline, 'Zero data selling or third-party ads'),
          _summaryPoint(Icons.check_circle_outline, 'Strictly limited to water delivery logistics'),
          _summaryPoint(Icons.check_circle_outline, 'Encrypted in transit (TLS 1.3) & at rest'),
          _summaryPoint(Icons.check_circle_outline, 'Full right to edit or erase your data'),
        ],
      ),
    );
  }

  Widget _summaryPoint(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: ShodashaTheme.teal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.3,
                color: ShodashaTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _policySection({
    required IconData icon,
    required String title,
    required String tag,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
        border: Border.all(color: ShodashaTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: ShodashaTheme.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: ShodashaTheme.bg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tag,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: ShodashaTheme.muted,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: ShodashaTheme.ink,
            ),
          ),
        ],
      ),
    );
  }

  void _showAccountDeletionSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ShodashaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: ShodashaTheme.danger, size: 24),
                SizedBox(width: 8),
                Text(
                  'Delete Account & Data',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Under the DPDP Act 2023, you have the right to request erasure of '
              'your personal data. Once submitted, your profile and addresses '
              'will be permanently deleted after verifying that all reusable '
              'jars have been returned and outstanding payments settled.',
              style: TextStyle(fontSize: 13, height: 1.45, color: ShodashaTheme.ink),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'To proceed, please submit an erasure request to our Grievance Cell '
              'at support@shodashawater.com with your registered phone number.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ShodashaTheme.tealDeep,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Close',
              kind: AppButtonKind.secondary,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
