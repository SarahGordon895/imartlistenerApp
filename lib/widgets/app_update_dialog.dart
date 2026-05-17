import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';
import '../shared/themes.dart';

Future<void> showAppUpdateDialogIfNeeded(BuildContext context) async {
  final update = await AppUpdateService.checkForUpdate();
  if (update == null || !context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Update available'),
      content: Text(
        update.message?.trim().isNotEmpty == true
            ? update.message!.trim()
            : 'Version ${update.latestVersion} is ready. Install the latest app to get current fixes and features.',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await AppUpdateService.dismissForBuild(update.latestBuild);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Later'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.lushRed),
          onPressed: () async {
            final uri = Uri.parse(update.downloadUrl);
            final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (!opened && ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text('Could not open download. Open this link in your browser:\n${update.downloadUrl}'),
                  duration: const Duration(seconds: 8),
                ),
              );
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Install update'),
        ),
      ],
    ),
  );
}
