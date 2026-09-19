import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easyconnect/features/ota_update/models/ota_metadata.dart';
import 'package:easyconnect/features/ota_update/services/ota_update_service.dart';

/// Modal dialog for non-mandatory (flexible) OTA updates.
class OtaUpdateDialog extends ConsumerWidget {
  final OtaMetadata metadata;
  final int currentVersionCode;
  final String currentVersionName;

  const OtaUpdateDialog({
    super.key,
    required this.metadata,
    required this.currentVersionCode,
    required this.currentVersionName,
  });

  static Future<void> show(
    BuildContext context, {
    required OtaMetadata metadata,
    required int currentVersionCode,
    required String currentVersionName,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => OtaUpdateDialog(
        metadata: metadata,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(otaStateProvider);
    final notifier = ref.read(otaStateProvider.notifier);

    final isDownloading = state.status == OtaStatus.downloading;
    final isReadyToInstall = state.status == OtaStatus.readyToInstall;
    final isError = state.status == OtaStatus.error;
    final progress = state.progress;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Badge & Icon
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEEDFE),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: Color(0xFF534AB7),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New Update Available',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E1B4B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Version ${metadata.versionName} (Build ${metadata.versionCode})',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF534AB7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Version comparison row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F6FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E2F5), width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Installed: v$currentVersionName ($currentVersionCode)',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  if (metadata.formattedSize.isNotEmpty)
                    Text(
                      metadata.formattedSize,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E1B4B),
                      ),
                    ),
                ],
              ),
            ),

            // Release Notes
            if (metadata.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                "WHAT'S NEW",
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF6B7280),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEBE9F8)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    metadata.releaseNotes,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF374151),
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],

            // Active Progress or Error View
            if (isDownloading && progress != null) ...[
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress.fraction > 0 ? progress.fraction : null,
                  minHeight: 10,
                  backgroundColor: const Color(0xFFE4E2F5),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF534AB7)),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Downloading update...',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  Text(
                    progress.formattedProgress,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF534AB7),
                    ),
                  ),
                ],
              ),
            ] else if (isReadyToInstall) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE1F5EE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF0F766E), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Verified securely (SHA-256). Ready to install!',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF0F766E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isError) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCEBEB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage ?? 'Update failed.',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 22),

            // Action Buttons
            Row(
              children: [
                if (!isDownloading && !isReadyToInstall)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        notifier.dismiss();
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: const BorderBorder(color: Color(0xFFD1D5DB)),
                      ),
                      child: Text(
                        'Later',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF4B5563),
                        ),
                      ),
                    ),
                  ),
                if (!isDownloading && !isReadyToInstall)
                  const SizedBox(width: 12),
                Expanded(
                  flex: isDownloading || isReadyToInstall ? 1 : 1,
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
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF534AB7),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(
                      isDownloading
                          ? 'Cancel Download'
                          : isReadyToInstall
                              ? 'Install Now'
                              : 'Update Now',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BorderBorder extends BorderSide {
  const BorderBorder({super.color = const Color(0xFF000000)});
}
