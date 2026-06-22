import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/features/settings/screens/manage_contacts_screen.dart';
import 'package:easyconnect/features/settings/screens/app_settings_screen.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminHubScreen extends ConsumerWidget {
  final VoidCallback? onBack;
  const AdminHubScreen({super.key, this.onBack});

  void _showPrivacyPolicy(BuildContext context, Color kAccentPurple) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.privacy_tip_outlined, color: kAccentPurple, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'Privacy Policy',
                        style: GoogleFonts.nunito(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: kTextNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        Text(
                          'Last Updated: May 2026',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Introduction',
                          style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'EasyConnect is designed specifically for elderly and illiterate users to have a completely accessible, foolproof phone calling experience. We believe privacy is a fundamental human right. Because this app is built for family and loved ones, it works entirely offline with zero tracking.',
                          style: GoogleFonts.nunito(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '1. Zero Cloud Synchronization',
                          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'EasyConnect does NOT send your contacts list, call logs, phone numbers, or any user activity to external servers or cloud providers. All data remains inside the private local sandbox on your physical device.',
                          style: GoogleFonts.nunito(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '2. Completely Local Telephony & Monitoring',
                          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'By registering as a default phone handler, the app monitors active call states purely locally. It uses Android native services to instantly display the large Accept/Decline overlays without recording, uploading, or storing audio conversations.',
                          style: GoogleFonts.nunito(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '3. On-Device Voice Guidance (TTS)',
                          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'All spoken names and voice notifications are processed entirely on-device using Android\'s local system text-to-speech framework. No speech profiles or audio clips are sent to third parties.',
                          style: GoogleFonts.nunito(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '4. Emergency SOS Alerts',
                          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'When the SOS button is triggered, the app compiles your current GPS location and sends a text message strictly through your cellular SIM card to the emergency contact designated in settings. This information is sent directly to your family member with no intermediate storage.',
                          style: GoogleFonts.nunito(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '5. Security & Device Sandbox',
                          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Local data is stored in Hive (NoSQL database) using the system-protected sandboxed file space. Standard security protocols are implemented to prevent external modifications of contacts or emergency parameters.',
                          style: GoogleFonts.nunito(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: kMinTouchTarget,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Close',
                        style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showTermsOfService(BuildContext context, Color kAccentPurple) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.description_outlined, color: kAccentPurple, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'Terms of Service',
                        style: GoogleFonts.nunito(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: kTextNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        Text(
                          'Last Updated: May 2026',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '1. Acceptance of Terms',
                          style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'By installing and using EasyConnect, you agree to these terms. This app is designed to replace your system phone dialer and SMS client solely to provide enhanced accessibility.',
                          style: GoogleFonts.nunito(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '2. Default Dialer & Permissions',
                          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'For the application to show large incoming call sheets and process dial requests, you must set EasyConnect as the Default Phone App and grant background overlay permissions. The application cannot process phone calls otherwise.',
                          style: GoogleFonts.nunito(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '3. Emergency SOS Triggers',
                          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The SOS emergency trigger relies on standard cellular networks to place phone calls and send background SMS alerts containing GPS coordinates. Accuracy depends on your device\'s hardware GPS module and cellular coverage. EasyConnect does not guarantee real-time delivery if network signals are absent.',
                          style: GoogleFonts.nunito(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '4. Safe Usage & Liability',
                          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This is a local, sandboxed utility app built for personal use. While we strive to maintain high reliability for calling and accessibility, the app is provided "as is" without warranties of any kind. Developers assume no liability for missed signals or network errors.',
                          style: GoogleFonts.nunito(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: kMinTouchTarget,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Close',
                        style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAccentColor = ref.watch(dynamicAccentColorProvider);
    final contactsAsync = ref.watch(contactsStreamProvider);
    final settingsAsync = ref.watch(settingsProvider);

    final contactsCount = contactsAsync.when(
      data: (list) => list.length.toString(),
      loading: () => '...',
      error: (_, _) => '0',
    );

    final sosContactId = settingsAsync.when(
      data: (s) => s.sosContactId,
      loading: () => null,
      error: (_, _) => null,
    );
    final isSosActive = sosContactId != null && sosContactId.isNotEmpty;

    final activeLang = settingsAsync.when(
      data: (s) => s.language.toUpperCase(),
      loading: () => 'EN',
      error: (_, _) => 'EN',
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 96.0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Center(
            child: GestureDetector(
              onTap: onBack ?? () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withValues(alpha: 0.18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Back',
                      style: GoogleFonts.nunito(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Admin Hero
            Container(
              decoration: const BoxDecoration(
                gradient: kPrimaryGradient,
              ),
              child: Stack(
                children: [
                  // Decorative Circle 1 (top-right)
                  Positioned(
                    top: -30,
                    right: -30,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white10,
                      ),
                    ),
                  ),
                  // Decorative Circle 2 (bottom-left)
                  Positioned(
                    bottom: -20,
                    left: 20,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white12,
                      ),
                    ),
                  ),
                  // Content
                  Padding(
                    padding: EdgeInsets.only(
                      left: 20.0,
                      right: 20.0,
                      top: 48.0 + MediaQuery.paddingOf(context).top,
                      bottom: 28.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, Caregiver',
                          style: GoogleFonts.nunito(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Configure the app for your loved one',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Stats row
            Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      value: contactsCount,
                      label: 'Contacts saved',
                      valueColor: const Color(0xFF1B1B2E),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      value: isSosActive ? '✓' : '✕',
                      label: 'SOS active',
                      valueColor: isSosActive ? const Color(0xFF32E08A) : const Color(0xFFFF2147),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      value: activeLang,
                      label: 'Language',
                      valueColor: const Color(0xFF1B1B2E),
                    ),
                  ),
                ],
              ),
            ),

            // Menu Items List
            Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 4.0),
              child: Column(
                children: [
                  _buildHubMenuCard(
                    title: 'Manage Contacts',
                    description: 'Add family members, edit numbers, reorder the grid',
                    icon: Icons.people_outline,
                    iconColor: activeAccentColor,
                    iconBgColor: activeAccentColor.withValues(alpha: 0.08),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ManageContactsScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildHubMenuCard(
                    title: 'App Settings & Backup',
                    description: 'Layouts, language, SOS contacts, exports',
                    icon: Icons.settings_outlined,
                    iconColor: const Color(0xFFFF8C00),
                    iconBgColor: const Color(0xFFFFF4E5),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AppSettingsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFF2F2F8), width: 1.5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 22.0, horizontal: 18.0),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFFFE4EC), Color(0xFFFFDCE8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '❤️',
                      style: TextStyle(fontSize: 22),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Built with love',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF9999B0),
                    ),
                  ),
                  Text(
                    'by Santhoshh, for Mom',
                    style: GoogleFonts.fraunces(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1B1B2E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'An offline, high-privacy calling app\ndesigned for simplicity and accessibility',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF9999B0),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showPrivacyPolicy(context, activeAccentColor),
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: activeAccentColor.withValues(alpha: 0.25), width: 0.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Privacy',
                              style: GoogleFonts.nunito(
                                color: activeAccentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showTermsOfService(context, activeAccentColor),
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: activeAccentColor.withValues(alpha: 0.25), width: 0.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Terms',
                              style: GoogleFonts.nunito(
                                color: activeAccentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final Uri url = Uri.parse('https://santhoshh.xyz/');
                            try {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            } catch (e) {
                              debugPrint('Could not launch portfolio url: $e');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not open link: $e')),
                                );
                              }
                            }
                          },
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: activeAccentColor.withValues(alpha: 0.25), width: 0.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Portfolio',
                              style: GoogleFonts.nunito(
                                color: activeAccentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'EasyConnect v1.5.3 · Offline-First',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFCCCCDA),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String value,
    required String label,
    required Color valueColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF2F2F8), width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.nunito(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF9999B0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHubMenuCard({
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF2F2F8), width: 1.5),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1B1B2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF9999B0),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFFCCCCDA),
              size: 19,
            ),
          ],
        ),
      ),
    );
  }
}
