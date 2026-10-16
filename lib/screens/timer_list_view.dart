import 'package:flutter/material.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/providers/theme_provider.dart';
import 'package:nothing_clock/providers/timer_provider.dart';
import 'package:nothing_clock/widgets/timer_form_sheet.dart';
import 'package:provider/provider.dart';

class TimerListView extends StatelessWidget {
  const TimerListView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<TimerProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final outline =
        themeProvider.isDarkMode ? Colors.white : theme.colorScheme.tertiary;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              tr("TIMERS"),
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 15),
            for (final t in provider.timers) ...[
              _TimerCard(timer: t),
              const SizedBox(height: 10),
            ],
            InkWell(
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => TimerFormSheet(
                  onSave: (name, seconds) => provider.addTimer(name, seconds),
                ),
              ),
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  border: Border.all(color: outline, width: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.add, color: outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerCard extends StatelessWidget {
  final SavedTimer timer;

  const _TimerCard({required this.timer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<TimerProvider>(context);
    final isActive = provider.activeId == timer.id && provider.hasActive;
    final running = isActive && provider.isRunning;
    final seconds = isActive ? provider.remainingSeconds : timer.seconds;

    return Material(
      color: theme.colorScheme.tertiary,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => TimerFormSheet(
            timer: timer,
            onSave: (name, secs) => provider.updateTimer(timer, name, secs),
            onDelete: () => provider.deleteTimer(timer),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatTimerSeconds(seconds),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(color: Colors.white, fontSize: 32),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (running) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle, color: Color(0xFFD71921)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            timer.name.isEmpty
                                ? tr("TIMER")
                                : timer.name.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: theme.colorScheme.onTertiary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => provider.playSaved(timer),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: running ? Color(0xFFD71921) : Colors.transparent,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: Icon(running ? Icons.timer : Icons.play_arrow,
                      color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
