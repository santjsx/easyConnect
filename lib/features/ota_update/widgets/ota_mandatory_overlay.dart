import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easyconnect/features/ota_update/models/ota_metadata.dart';
import 'package:easyconnect/features/ota_update/services/ota_update_service.dart';

/// Full-screen non-dismissible blocking overlay for mandatory updates.
class OtaMandatoryOverlay extends ConsumerWidget {
  final OtaMetadata metadata;
  final int currentVersionCode;
  final String currentVersionName;

  const OtaMandatoryOverlay({
    super.key,
    required this.metadata,
    required this.currentVersionCode,
    required this.currentVersionName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(otaStateProvider);
    final notifier = ref.read(otaStateProvider.notifier);

    final isDownloading = state.status == OtaStatus.downloading;
    final isReadyToInstall = state.status == OtaStatus.readyToInstall;
    final isError = state.status == OtaStatus.error;
    final progress = state.progress;
    final isDiskSpaceError = isError && (state.errorMessage?.contains('disk space') ?? false);

    return PopScope(
      canPop: false, // Strict block: User cannot dismiss or back-out of mandatory update
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1B4B),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1E1B4B),
                Color(0xFF312E81),
                Color(0xFF0F172A),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top icon & header
                  Column(
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4338CA).withOpacity(0.3),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF6366F1).withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.security_update_good_rounded,
                          size: 42,
                          color: Color(0xFFA5B4FC),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Critical Update Required',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Version ${metadata.versionName} includes essential security and connectivity improvements required to keep EasyConnect running safely.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: const Color(0xFFC7D2FE),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),

                  // Middle Section: Specs & Progress Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Details row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Target Version',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                            Text(
                              'v${metadata.versionName} (Build ${metadata.versionCode})',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Current Version',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                            Text(
                              'v$currentVersionName ($currentVersionCode)',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: const Color(0xFFCBD5E1),
                              ),
                            ),
                          ],
                        ),
                        if (metadata.formattedSize.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Download Size',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                              Text(
                                metadata.formattedSize,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF38BDF8),
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Progress bar if downloading
                        if (isDownloading && progress != null) ...[
                          const SizedBox(height: 20),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: progress.fraction > 0 ? progress.fraction : null,
                              minHeight: 12,
                              backgroundColor: Colors.white.withOpacity(0.1),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Downloading update securely...',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                              Text(
                                progress.formattedProgress,
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFA5B4FC),
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Verified badge
                        if (isReadyToInstall) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF065F46).withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.verified_rounded, color: Color(0xFF34D399), size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Update verified (SHA-256). Ready to install.',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFFD1FAE5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Error Banner / Insufficient Space Prompt
                        if (isError) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7F1D1D).withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isDiskSpaceError
                                      ? Icons.disc_full_rounded
                                      : Icons.warning_amber_rounded,
                                  color: const Color(0xFFFCA5A5),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    state.errorMessage ?? 'Update encountered an error.',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: const Color(0xFFFEE2E2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Bottom Action Button
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
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
                                ? const Color(0xFFEF4444)
                                : isReadyToInstall
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF6366F1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                          ),
                          child: Text(
                            isDownloading
                                ? 'Cancel Download'
                                : isReadyToInstall
                                    ? 'Install Update Now'
                                    : 'Download & Install',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'EasyConnect requires this update before continuing.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
