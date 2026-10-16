import 'package:flutter/material.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/models/world_clock_data.dart';
import 'package:nothing_clock/providers/worldclocks_provider.dart';
import 'package:provider/provider.dart';

class TimeZoneClock extends StatefulWidget {
  final WorldClockData data;

  const TimeZoneClock({super.key, required this.data});

  @override
  State<TimeZoneClock> createState() => _TimeZoneClockState();
}

class _TimeZoneClockState extends State<TimeZoneClock> {
  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.data.displayName.toUpperCase()),
        content: Text(tr("Delete this clock?")),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr("CANCEL"))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr("DELETE"))),
        ],
      ),
    );
    if (ok == true && mounted) {
      Provider.of<WorldClocksProvider>(context, listen: false)
          .removeWorldClock(widget.data);
    }
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    return GestureDetector(
      onLongPress: _confirmDelete,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiary,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Color(0xFFD71921)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.data.displayName.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.15,
                        color: theme.colorScheme.onTertiary,
                      ),
                    ),
                  ),
                  Consumer<WorldClocksProvider>(
                    builder: (context, _, __) => Padding(
                      padding: const EdgeInsets.only(left: 6, top: 1),
                      child: Icon(
                        widget.data.isDay
                            ? Icons.wb_sunny_outlined
                            : Icons.nightlight_outlined,
                        size: 16,
                        color: theme.colorScheme.onTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              Consumer<WorldClocksProvider>(
                builder: (context, value, child) {
                  final diff = widget.data.diffLabel;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (diff.isNotEmpty)
                        Text(
                          diff,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onTertiary.withOpacity(0.6),
                          ),
                        ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.data.currentFormattedTime,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 33,
                            color: theme.colorScheme.onTertiary,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
