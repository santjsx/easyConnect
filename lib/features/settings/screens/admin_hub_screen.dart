import 'package:flutter/material.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/settings/screens/manage_contacts_screen.dart';
import 'package:easyconnect/features/settings/screens/app_settings_screen.dart';

class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                iconBgColor: const Color(0xFFF5F3FF), // Purple 50
                iconColor: kAccentPurple, // Purple accent
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
                iconBgColor: const Color(0xFFF5F3FF), // Purple 50
                iconColor: kAccentPurple, // Purple accent
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
}
