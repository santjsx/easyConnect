import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easyconnect/features/ota_update/models/ota_metadata.dart';
import 'package:easyconnect/features/ota_update/services/ota_update_service.dart';
import 'package:easyconnect/features/ota_update/services/ota_installer_platform.dart';

class OtaUpdateScreen extends ConsumerStatefulWidget {
  const OtaUpdateScreen({super.key});

  @override
  ConsumerState<OtaUpdateScreen> createState() => _OtaUpdateScreenState();
}

class _OtaUpdateScreenState extends ConsumerState<OtaUpdateScreen> {
  String _selectedChannel = 'stable';
  int _availableDiskBytes = -1;
  bool _canInstallPackages = true;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _loadSystemInfo();
  }

  Future<void> _loadSystemInfo() async {
    final bytes = await OtaInstallerPlatform.getAvailableDiskSpace();
    final canInstall = await OtaInstallerPlatform.canRequestPackageInstalls();
    if (mounted) {
      setState(() {
        _availableDiskBytes = bytes;
        _canInstallPackages = canInstall;
      });
    }
  }

  Future<void> _checkNow() async {
    setState(() => _isChecking = true);
    final notifier = ref.read(otaStateProvider.notifier);
    final result = await notifier.check(isManual: true, channel: _selectedChannel);
    await _loadSystemInfo();
    if (mounted) {
      setState(() => _isChecking = false);
      if (!result.hasUpdate && result.errorMessage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'EasyConnect is up to date! (v${result.currentVersionName})',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(otaStateProvider);
    final notifier = ref.read(otaStateProvider.notifier);
    final isDownloading = state.status == OtaStatus.downloading;
    final isReadyToInstall = state.status == OtaStatus.readyToInstall;
    final progress = state.progress;

    final freeSpaceMb = _availableDiskBytes > 0
        ? (_availableDiskBytes / (1024 * 1024)).toStringAsFixed(1)
        : 'Unknown';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(
        title: Text(
          'Software Update',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: const Color(0xFF1E1B4B),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E1B4B), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20.0,
          right: 20.0,
          top: 20.0,
          bottom: 20.0 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current Version Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF534AB7).withOpacity(0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEEDFE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Color(0xFF534AB7),
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'EasyConnect',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E1B4B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Installed Version: v${state.currentVersionName} (Build ${state.currentVersionCode})',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF534AB7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFE4E2F5)),
                  const SizedBox(height: 16),
                  // System telemetry status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMiniInfo(
                        label: 'Free Cache Space',
                        value: '$freeSpaceMb MB',
                        icon: Icons.storage_rounded,
                      ),
                      Container(width: 1, height: 32, color: const Color(0xFFE4E2F5)),
                      _buildMiniInfo(
                        label: 'Install Permission',
                        value: _canInstallPackages ? 'Granted' : 'Needed',
                        icon: _canInstallPackages ? Icons.verified_user_rounded : Icons.warning_amber_rounded,
                        valueColor: _canInstallPackages ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Release Channel Selector
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE4E2F5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RELEASE CHANNEL',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF7F77DD),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildChannelButton(
                          title: 'Stable',
                          subtitle: 'Verified releases',
                          isSelected: _selectedChannel == 'stable',
                          onTap: () {
                            setState(() => _selectedChannel = 'stable');
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildChannelButton(
                          title: 'Beta / Canary',
                          subtitle: 'Early test releases',
                          isSelected: _selectedChannel == 'beta',
                          onTap: () {
                            setState(() => _selectedChannel = 'beta');
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Update Status / Metadata view
            if (state.status == OtaStatus.updateAvailable && state.metadata != null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF534AB7).withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF534AB7).withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEEDFE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            state.isMandatory ? 'MANDATORY UPDATE' : 'UPDATE AVAILABLE',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: state.isMandatory ? const Color(0xFFDC2626) : const Color(0xFF534AB7),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (state.metadata!.formattedSize.isNotEmpty)
                          Text(
                            state.metadata!.formattedSize,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF4B5563),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Version ${state.metadata!.versionName} (Build ${state.metadata!.versionCode})',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E1B4B),
                      ),
                    ),
                    if (state.metadata!.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        state.metadata!.releaseNotes,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: const Color(0xFF4B5563),
                          height: 1.4,
                        ),
                      ),
                    ],

                    // Progress bar
                    if (isDownloading && progress != null) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress.fraction > 0 ? progress.fraction : null,
                          minHeight: 10,
                          backgroundColor: const Color(0xFFE4E2F5),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF534AB7)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        progress.formattedProgress,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF534AB7),
                        ),
                      ),
                    ],

                    if (isReadyToInstall) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE1F5EE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Update package verified securely via SHA-256.',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF0F766E),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: () {
                        if (isDownloading) {
                          notifier.cancel();
                        } else if (isReadyToInstall) {
                          notifier.install();
                        } else {
                          notifier.startDownload();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDownloading
                            ? const Color(0xFFDC2626)
                            : isReadyToInstall
                                ? const Color(0xFF10B981)
                                : const Color(0xFF534AB7),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text(
                        isDownloading
                            ? 'Cancel'
                            : isReadyToInstall
                                ? 'Install Update'
                                : 'Download & Install',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Install Permission Banner if not yet granted
            if (!_canInstallPackages) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security_rounded, color: Color(0xFFB45309), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Install Permission Required',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Allow EasyConnect to install unknown apps in Android Settings.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF78350F),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await OtaInstallerPlatform.openInstallPermissionSettings();
                        await _loadSystemInfo();
                      },
                      child: Text(
                        'Settings',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Check for updates action button
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isChecking ? null : _checkNow,
                icon: _isChecking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded, color: Colors.white),
                label: Text(
                  _isChecking ? 'Checking GitHub Releases...' : 'Check for Updates',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF534AB7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniInfo({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF534AB7)),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? const Color(0xFF1E1B4B),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            color: const Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelButton({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEEEDFE) : const Color(0xFFFAFAFE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF534AB7) : const Color(0xFFE4E2F5),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16,
                  color: isSelected ? const Color(0xFF534AB7) : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? const Color(0xFF534AB7) : const Color(0xFF374151),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 22.0),
              child: Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: const Color(0xFF6B7280),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
