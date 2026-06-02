import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/features/settings/screens/manage_contacts_screen.dart';
import 'package:easyconnect/features/settings/screens/app_settings_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminHubScreen extends ConsumerWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAccentColor = ref.watch(dynamicAccentColorProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Slate 50 background
      appBar: AppBar(
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(
            color: kTextNavy,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: kTextNavy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: kTextDark, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Welcome, Caregiver',
                  style: TextStyle(
                    fontSize: 24.0,
                    fontWeight: FontWeight.bold,
                    color: kTextNavy,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose a section to configure the app for your loved one.',
                  style: TextStyle(
                    fontSize: 14.0,
                    color: kTextSlate,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 32),

                // 1. Manage Contacts Card
                _buildHubCard(
                  context: context,
                  title: 'Manage Contacts',
                  subtitle: 'Add new family members, take profile photos, edit phone numbers, or drag to reorder the screen grid.',
                  icon: Icons.people_alt_rounded,
                  iconBgColor: activeAccentColor.withValues(alpha: 0.08), // Dynamic background tint
                  iconColor: activeAccentColor, // Dynamic accent color
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ManageContactsScreen()),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // 2. App Settings Card
                _buildHubCard(
                  context: context,
                  title: 'App Settings & Backup',
                  subtitle: 'Toggle Classic or Modern layouts, change languages, pick emergency SOS contacts, or export CSV/JSON backups.',
                  icon: Icons.tune_rounded,
                  iconBgColor: activeAccentColor.withValues(alpha: 0.08), // Dynamic background tint
                  iconColor: activeAccentColor, // Dynamic accent color
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AppSettingsScreen()),
                    );
                  },
                ),

                const SizedBox(height: 28),

                // Developer Credits & Info Card
                _buildAboutSection(context, activeAccentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHubCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5), // Slate 200
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03), // Soft slate shadow
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon Frame
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      color: iconColor,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Text details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18.0,
                              fontWeight: FontWeight.bold,
                              color: kTextNavy,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: kTextSlate,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13.0,
                          color: kTextSlate,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context, Color kAccentPurple) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFECDD3),
                width: 1.5,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.favorite_rounded,
                color: Color(0xFFF43F5E),
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'E A S Y C O N N E C T',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade400,
              letterSpacing: 4.0,
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                fontSize: 16,
                color: kTextDark,
                letterSpacing: -0.3,
              ),
              children: [
                const TextSpan(
                  text: 'Built by ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(
                  text: 'Santhoshh',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF43F5E),
                  ),
                ),
                const TextSpan(
                  text: ' with love for ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: 'Mom',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: kAccentPurple,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'An offline, high-privacy calling application designed to make communication simple and accessible.',
            style: TextStyle(
              fontSize: 12,
              color: kTextSlate,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: kMinTouchTarget,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kAccentPurple,
                      side: BorderSide(color: kAccentPurple, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => _showPrivacyPolicy(context, kAccentPurple),
                    icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                    label: const Text(
                      'Privacy Policy',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: kMinTouchTarget,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kAccentPurple,
                      side: BorderSide(color: kAccentPurple, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => _showTermsOfService(context, kAccentPurple),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text(
                      'Terms of Service',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: kMinTouchTarget,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccentPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              onPressed: () async {
                final Uri url = Uri.parse('https://santhoshh.xyz/');
                try {
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  debugPrint('Could not launch portfolio url: $e');
                }
              },
              icon: const Icon(Icons.language_rounded, size: 20),
              label: const Text(
                'Visit Developer Portfolio',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'EasyConnect v1.5.3 — Offline-First & Private',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

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
                      const Text(
                        'Privacy Policy',
                        style: TextStyle(
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
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Introduction',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'EasyConnect is designed specifically for elderly and illiterate users to have a completely accessible, foolproof phone calling experience. We believe privacy is a fundamental human right. Because this app is built for family and loved ones, it works entirely offline with zero tracking.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '1. Zero Cloud Synchronization',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'EasyConnect does NOT send your contacts list, call logs, phone numbers, or any user activity to external servers or cloud providers. All data remains inside the private local sandbox on your physical device.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '2. Completely Local Telephony & Monitoring',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'By registering as a default phone handler, the app monitors active call states purely locally. It uses Android native services to instantly display the large Accept/Decline overlays without recording, uploading, or storing audio conversations.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '3. On-Device Voice Guidance (TTS)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'All spoken names and voice notifications are processed entirely on-device using Android\'s local system text-to-speech framework. No speech profiles or audio clips are sent to third parties.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '4. Emergency SOS Alerts',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'When the SOS button is triggered, the app compiles your current GPS location and sends a text message strictly through your cellular SIM card to the emergency contact designated in settings. This information is sent directly to your family member with no intermediate storage.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '5. Security & Device Sandbox',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Local data is stored in Hive (NoSQL database) using the system-protected sandboxed file space. Standard security protocols are implemented to prevent external modifications of contacts or emergency parameters.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
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
                      child: const Text(
                        'Close',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                      const Text(
                        'Terms of Service',
                        style: TextStyle(
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
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '1. Acceptance of Terms',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'By installing and using EasyConnect, you agree to these terms. This app is designed to replace your system phone dialer and SMS client solely to provide enhanced accessibility.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '2. Default Dialer & Permissions',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'For the application to show large incoming call sheets and process dial requests, you must set EasyConnect as the Default Phone App and grant background overlay permissions. The application cannot process phone calls otherwise.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '3. Emergency SOS Triggers',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The SOS emergency trigger relies on standard cellular networks to place phone calls and send background SMS alerts containing GPS coordinates. Accuracy depends on your device\'s hardware GPS module and cellular coverage. EasyConnect does not guarantee real-time delivery if network signals are absent.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '4. Safe Usage & Liability',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This is a local, sandboxed utility app built for personal use. While we strive to maintain high reliability for calling and accessibility, the app is provided "as is" without warranties of any kind. Developers assume no liability for missed signals or network errors.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
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
                      child: const Text(
                        'Close',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
}
