import 'package:flutter/material.dart';
import 'package:nothing_clock/models/alarm.dart';
import 'package:nothing_clock/screens/sleep_time_screen.dart';
import 'package:nothing_clock/widgets/nothing_pill.dart';
import 'package:nothing_clock/services/sync_service.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/services/alarms_service.dart';
import 'package:nothing_clock/widgets/alarms/alarm_form_bottom_sheet.dart';
import 'package:nothing_clock/providers/theme_provider.dart';
import 'package:nothing_clock/view_models/alarms_view_model.dart';
import 'package:nothing_clock/widgets/alarms/alarm_grid.dart';
import 'package:nothing_clock/widgets/alarms/sleep_alarm_block.dart';
import 'package:provider/provider.dart';

/// The main screen for displaying and managing alarms.
/// Shows a fixed "Sleep Time" alarm and a grid of other alarms.
class AlarmsScreen extends StatefulWidget {
  const AlarmsScreen({super.key});

  @override
  State<AlarmsScreen> createState() => _AlarmsScreenState();
}

/// State class for [AlarmsScreen].
/// Handles loading alarms from storage and updating UI.
class _AlarmsScreenState extends State<AlarmsScreen> with WidgetsBindingObserver {
  /// View model that manages business logic for the alarms
  late AlarmsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SyncService.remoteApplied.addListener(_loadAlarms);
    
    // Initialize view model
    _viewModel = AlarmsViewModel();
    
    // Load alarms data when screen initializes
    _loadAlarms();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadAlarms();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SyncService.remoteApplied.removeListener(_loadAlarms);
    super.dispose();
  }

  /// Loads alarms asynchronously via the view model.
  Future<void> _loadAlarms() async {
    await _viewModel.loadAlarms();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    // Calculate block size dynamically based on screen width and padding.
    // This ensures proper responsive layout across different screen sizes.
    final blockSize = (MediaQuery.of(context).size.width - 40 - 10) / 2;

    // Wrap the UI in a ListenableBuilder to respond to view model changes
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sleep Time section header
                    _buildSectionHeader(tr("SLEEP TIME"), theme),
                    const SizedBox(height: 15),
                    
                    // Custom widget for Sleep Time alarm
                    if (_viewModel.sleepAlarm != null)
                      SleepAlarmBlock(
                        key: ValueKey('sleep-${_viewModel.sleepAlarm!.uiRev}-${_viewModel.sleepAlarm!.isEnabled}'),
                        isDarkMode: themeProvider.isDarkMode,
                        sleepTime: _viewModel.sleepAlarm!.time,
                        sleepDays: _sleepDaysList(_viewModel.sleepAlarm!),
                        isSleepEnabled: _viewModel.sleepAlarm!.isEnabled,
                        onToggle: () => _onToggleAlarm(_viewModel.sleepAlarm!),
                        onTap: _editSleep,
                      ),
                    const SizedBox(height: 35),
                    
                    // Other alarms section header
                    _buildSectionHeader(tr("OTHER"), theme),
                    const SizedBox(height: 15),
                    
                    // Grid of alarms with add button
                    AlarmGrid(
                      alarms: _viewModel.alarms,
                      blockSize: blockSize,
                      onToggleAlarm: _onToggleAlarm,
                      onAddAlarm: (alarm) async {
                        await _viewModel.addAlarm(alarm);
                        _showRingsIn(alarm);
                      },
                      onEditAlarm: (alarm, time, days, label) async {
                        await _viewModel.updateAlarm(alarm, time, days, label);
                        _showRingsIn(alarm);
                      },
                      onDeleteAlarm: (alarm) => _viewModel.deleteAlarm(alarm),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<String> _sleepDaysList(Alarm a) {
    const order = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];
    final d = order.where((k) => a.days[k] ?? false).toList();
    return d.isEmpty ? ["ONCE"] : d;
  }

  void _editSleep() {
    final a = _viewModel.sleepAlarm!;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SleepTimeScreen(alarm: a, viewModel: _viewModel),
      ),
    );
  }

  void _showRingsIn(Alarm alarm) {
    if (!mounted) return;
    showRingsInPill(context, alarm);
  }

  Future<void> _onToggleAlarm(Alarm alarm) async {
    if (!alarm.isEnabled || !AlarmsService.hasDays(alarm)) {
      _viewModel.toggleAlarmState(alarm);
      if (alarm.isEnabled) _showRingsIn(alarm);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr("TURN OFF ALARM")),
        content: Text(tr("Next time only, or always?")),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: Text(tr("CANCEL"))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'next'), child: Text(tr("NEXT"))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'off'), child: Text(tr("ALWAYS"))),
        ],
      ),
    );
    if (choice == 'next') {
      await _viewModel.skipNextOccurrence(alarm);
    } else if (choice == 'off') {
      _viewModel.toggleAlarmState(alarm);
    } else {
      _viewModel.refreshAlarm(alarm);
    }
  }

  /// Creates a consistently styled section header
  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Text(
      title,
      style: TextStyle(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.2,
      ),
    );
  }
}
