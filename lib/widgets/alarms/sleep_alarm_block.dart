import 'package:flutter/material.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/widgets/switch_button.dart';

class SleepAlarmBlock extends StatelessWidget {
  final bool isDarkMode;
  final DateTime sleepTime;
  final List<String> sleepDays;
  final bool isSleepEnabled;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const SleepAlarmBlock({
    super.key,
    required this.isDarkMode,
    required this.sleepTime,
    required this.sleepDays,
    required this.isSleepEnabled,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = isDarkMode ? Colors.black : theme.colorScheme.onSecondary;

    final formattedTime =
        "${sleepTime.hour.toString().padLeft(2, '0')}:${sleepTime.minute.toString().padLeft(2, '0')}";
    final formattedDays = sleepDays.map(tr).join(", ");

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white : Colors.transparent,
          border: isDarkMode
              ? null
              : Border.all(color: theme.colorScheme.onSurface, width: 1),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(25),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formattedTime,
                    style: theme.textTheme.titleLarge?.copyWith(
                        color: textColor, fontSize: 32)),
                const SizedBox(height: 10),
                Text(formattedDays,
                    style: TextStyle(color: textColor)),
              ],
            ),
            SwitchButton(
              defaultValue: isSleepEnabled,
              onChanged: onToggle,
              inactiveTrackColor: Colors.transparent,
              activeTrackColor: Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
