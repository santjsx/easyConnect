import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/features/settings/screens/manage_contacts_screen.dart';
import 'package:easyconnect/features/settings/screens/app_settings_screen.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminHubScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const AdminHubScreen({super.key, this.onBack});

  @override
  ConsumerState<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends ConsumerState<AdminHubScreen> {

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
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
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
                          'Last Updated: June 2026',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Introduction',
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w500, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'EasyConnect is designed specifically for elderly and illiterate users to have a completely accessible, foolproof phone calling experience. We believe privacy is a fundamental human right. Because this app is built for family and loved ones, it works entirely offline with zero tracking.',
                          style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '1. Zero Cloud Synchronization',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'EasyConnect does NOT send your contacts list, call logs, phone numbers, or any user activity to external servers or cloud providers. All data remains inside the private local sandbox on your physical device.',
                          style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '2. Completely Local Telephony & Monitoring',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'By registering as a default phone handler, the app monitors active call states purely locally. It uses Android native services to instantly display the large Accept/Decline overlays without recording, uploading, or storing audio conversations.',
                          style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '3. On-Device Voice Guidance (TTS)',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'All spoken names and voice notifications are processed entirely on-device using Android\'s local system text-to-speech framework. No speech profiles or audio clips are sent to third parties.',
                          style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '4. Emergency SOS Alerts',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'When the SOS button is triggered, the app compiles your current GPS location and sends a text message strictly through your cellular SIM card to the emergency contact designated in settings. This information is sent directly to your family member with no intermediate storage.',
                          style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '5. Security & Device Sandbox',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Local data is stored in Hive (NoSQL database) using the system-protected sandboxed file space. Standard security protocols are implemented to prevent external modifications of contacts or emergency parameters.',
                          style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
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
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500),
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
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
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
                          'Last Updated: June 2026',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '1. Acceptance of Terms',
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w500, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'By installing and using EasyConnect, you agree to these terms. This app is designed to replace your system phone dialer and SMS client solely to provide enhanced accessibility.',
                          style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '2. Default Dialer & Permissions',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'For the application to show large incoming call sheets and process dial requests, you must set EasyConnect as the Default Phone App and grant background overlay permissions. The application cannot process phone calls otherwise.',
                          style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '3. Emergency SOS Triggers',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The SOS emergency trigger relies on standard cellular networks to place phone calls and send background SMS alerts containing GPS coordinates. Accuracy depends on your device\'s hardware GPS module and cellular coverage. EasyConnect does not guarantee real-time delivery if network signals are absent.',
                          style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '4. Safe Usage & Liability',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This is a local, sandboxed utility app built for personal use. While we strive to maintain high reliability for calling and accessibility, the app is provided "as is" without warranties of any kind. Developers assume no liability for missed signals or network errors.',
                          style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
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
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500),
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
  Widget build(BuildContext context) {
    final activeAccentColor = ref.watch(dynamicAccentColorProvider);
    return _buildHubContent(activeAccentColor);
  }


  Widget _buildHubContent(Color activeAccentColor) {
    final contactsAsync = ref.watch(contactsStreamProvider);
    final settingsAsync = ref.watch(settingsProvider);

    final contactsCount = contactsAsync.when(
      data: (list) => list.length.toString(),
      loading: () => '...',
      error: (_, _) => '0',
    );

    final activeLang = settingsAsync.when(
      data: (s) => s.language.toUpperCase(),
      loading: () => 'EN',
      error: (_, _) => 'EN',
    );

    final settings = settingsAsync.value ?? AppSettings(adminPin: '1234');

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
              onTap: widget.onBack ?? () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withOpacity(0.18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.25),
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
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
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
            // Admin Hero Card with custom background #534AB7
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF534AB7),
              ),
              child: Stack(
                children: [
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
                          'WELCOME, CAREGIVER',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFAFA9EC),
                            letterSpacing: 0.08 * 12.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Configure for your loved one',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFEEEDFE),
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
                      label: 'Contacts',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      value: activeLang,
                      label: 'Language',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      value: 'v1.5.3',
                      label: 'Version',
                    ),
                  ),
                ],
              ),
            ),

            // Section Label MANAGE
            Padding(
              padding: const EdgeInsets.only(left: 20.0, top: 16.0, bottom: 8.0),
              child: Text(
                "MANAGE",
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF7F77DD),
                  letterSpacing: 0.08 * 10.0,
                ),
              ),
            ),

            // Menu Items & Toggles
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  // Contacts Screen Row
                  _buildHubActionRow(
                    title: 'Contacts',
                    subtitle: 'Add family members, edit numbers, reorder the grid',
                    icon: Icons.people_outline,
                    iconColor: const Color(0xFF534AB7),
                    iconBgColor: const Color(0xFFEEEDFE),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ManageContactsScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  // Emergency SOS Settings Row
                  _buildHubActionRow(
                    title: 'Emergency SOS',
                    subtitle: 'Layouts, language, SOS contacts, triggers',
                    icon: Icons.emergency_share,
                    iconColor: const Color(0xFFE24B4A),
                    iconBgColor: const Color(0xFFFCEBEB),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AppSettingsScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  // Cloud Sync Toggle Mapped to setting
                  _buildHubToggleRow(
                    title: 'Cloud sync',
                    subtitle: 'Keep settings synced automatically with web dashboard',
                    icon: Icons.cloud_sync_outlined,
                    iconColor: const Color(0xFF1D9E75),
                    iconBgColor: const Color(0xFFE1F5EE),
                    value: settings.activeIsSyncEnabled,
                    onChanged: (val) async {
                      settings.isSyncEnabled = val;
                      await settings.save();
                    },
                  ),
                  const SizedBox(height: 10),

                  // Voice Guidance Toggle Mapped to setting
                  _buildHubToggleRow(
                    title: 'Voice guidance',
                    subtitle: 'Announce numbers, caller names and actions aloud',
                    icon: Icons.record_voice_over_outlined,
                    iconColor: const Color(0xFFEF9F27),
                    iconBgColor: const Color(0xFFFAEEDA),
                    value: settings.voiceEnabled,
                    onChanged: (val) async {
                      settings.voiceEnabled = val;
                      await settings.save();
                    },
                  ),
                  const SizedBox(height: 10),

                  // Kiosk Mode / Exit Guard Toggle Mapped to setting
                  _buildHubToggleRow(
                    title: 'Kiosk / exit guard',
                    subtitle: 'Locks user inside simple phone mode using password',
                    icon: Icons.lock_person_outlined,
                    iconColor: const Color(0xFFD4537E),
                    iconBgColor: const Color(0xFFFCEBEB),
                    value: settings.activeIsKioskModeEnabled,
                    onChanged: (val) async {
                      settings.isKioskModeEnabled = val;
                      await settings.save();
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
                border: Border.all(color: const Color(0xFFE4E2F5), width: 0.5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 22.0, horizontal: 18.0),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFEEEDFE),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '❤️',
                      style: TextStyle(fontSize: 22),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Built with love by Santhoshh, for Mom',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF7F77DD),
                    ),
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
                              border: Border.all(color: activeAccentColor.withOpacity(0.25), width: 0.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Privacy',
                              style: GoogleFonts.inter(
                                color: activeAccentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
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
                              border: Border.all(color: activeAccentColor.withOpacity(0.25), width: 0.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Terms',
                              style: GoogleFonts.inter(
                                color: activeAccentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
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
                            }
                          },
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: activeAccentColor.withOpacity(0.25), width: 0.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Portfolio',
                              style: GoogleFonts.inter(
                                color: activeAccentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
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
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF7F77DD),
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
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E2F5), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: kTextNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: kTextSlate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHubActionRow({
    required String title,
    required String subtitle,
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
          border: Border.all(color: const Color(0xFFE4E2F5), width: 0.5),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: kTextNavy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: kTextSlate,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF7F77DD),
              size: 19,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHubToggleRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E2F5), width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: kTextNavy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: kTextSlate,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (val) {
              HapticFeedback.lightImpact();
              onChanged(val);
            },
            activeColor: const Color(0xFF534AB7),
          ),
        ],
      ),
    );
  }
}
