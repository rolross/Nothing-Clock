import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/services/sync_service.dart';

class NextcloudSettingsTile extends StatelessWidget {
  const NextcloudSettingsTile({super.key});

  String _two(int v) => v.toString().padLeft(2, '0');

  String _subtitle(SyncService s) {
    if (!s.connected) {
      return s.lastError != null
          ? '${tr("Sync error")}: ${s.lastError}'
          : tr("Not connected");
    }
    final parts = <String>[s.accountLabel ?? ''];
    if (s.lastError != null) {
      parts.add('${tr("Sync error")}: ${s.lastError}');
    } else if (s.lastSync != null) {
      final t = s.lastSync!;
      parts.add('${tr("Synced")} ${_two(t.hour)}:${_two(t.minute)}');
    }
    return parts.join(' · ');
  }

  Future<void> _connect(BuildContext context) async {
    final controller = TextEditingController(text: 'https://');
    final server = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr("Nextcloud server")),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://cloud.example.com'),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr("CANCEL"))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(tr("Connect"))),
        ],
      ),
    );
    if (server == null || server.length < 9) return;
    if (!context.mounted) return;

    var cancelled = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 16),
            Expanded(child: Text(tr("Authorize NothingClock in the browser..."))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(ctx);
            },
            child: Text(tr("CANCEL")),
          ),
        ],
      ),
    );

    String? error;
    try {
      await SyncService.instance.connect(server, isCancelled: () => cancelled);
    } catch (e) {
      if (!cancelled) error = e.toString();
    }
    if (!cancelled && context.mounted) Navigator.of(context).pop();
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr("Sync error")}: $error')),
      );
    }
  }

  Future<void> _manage(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(SyncService.instance.accountLabel ?? 'Nextcloud'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'sync'),
              child: Text(tr("Sync now"))),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'disconnect'),
              child: Text(tr("Disconnect"))),
        ],
      ),
    );
    if (choice == 'sync') {
      await SyncService.instance.sync();
    } else if (choice == 'disconnect') {
      await SyncService.instance.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return AnimatedBuilder(
      animation: sync,
      builder: (context, _) {
        final theme = Theme.of(context);
        return ListTile(
          onTap: () => sync.connected ? _manage(context) : _connect(context),
          title: Row(
            children: [
              Flexible(
                child: Text(tr("Nextcloud sync").toUpperCase(),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 15),
              const Icon(FontAwesomeIcons.cloud, size: 15),
            ],
          ),
          subtitle: Text(
            _subtitle(sync),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurface),
          ),
          trailing: Padding(
            padding: const EdgeInsets.only(left: 15.0),
            child: sync.syncing
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.arrow_forward_ios, size: 15),
          ),
        );
      },
    );
  }
}
