import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/models/alarm.dart';
import 'package:nothing_clock/services/ha_service.dart';
import 'package:nothing_clock/services/nextcloud_client.dart';
import 'package:nothing_clock/view_models/alarms_view_model.dart';
import 'package:nothing_clock/widgets/alarms/day_selector.dart';
import 'package:nothing_clock/widgets/nothing_pill.dart';
import 'package:nothing_clock/widgets/switch_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color _card = Color(0xFF1B1B1B);
const Color _gray = Color(0xFFA3A3A3);

class SleepTimeScreen extends StatefulWidget {
  final Alarm alarm;
  final AlarmsViewModel viewModel;

  const SleepTimeScreen({super.key, required this.alarm, required this.viewModel});

  @override
  State<SleepTimeScreen> createState() => _SleepTimeScreenState();
}

class _SleepTimeScreenState extends State<SleepTimeScreen> {
  static const List<String> _order = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  late int _wakeMin;
  int _bedMin = 23 * 60;
  int _reminder = 0;
  late Map<String, bool> _days;
  Timer? _saveTimer;

  bool _hasNc = false;
  bool _haConfigured = false;
  String _haUrl = '';
  final Map<String, String> _haNames = {};

  @override
  void initState() {
    super.initState();
    _wakeMin = widget.alarm.time.hour * 60 + widget.alarm.time.minute;
    _days = {for (final d in _order) d: widget.alarm.days[d] ?? false};
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    _bedMin = p.getInt('sleep_bedtime') ?? 23 * 60;
    _reminder = p.getInt('sleep_reminder') ?? 0;
    for (final e in HaService.events) {
      final n = p.getString('ha_name_$e');
      if (n != null && n.isNotEmpty) _haNames[e] = n;
    }
    if (mounted) setState(() {});
    _hasNc = (await NextcloudClient.loadCredentials()) != null;
    await HaService.refreshConfig();
    _haConfigured = await HaService.isConfigured();
    _haUrl = await HaService.url();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _save();
    }
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('sleep_bedtime', _bedMin);
    await p.setInt('sleep_reminder', _reminder);
    final wake = DateTime(2000, 1, 1, _wakeMin ~/ 60, _wakeMin % 60);
    await widget.viewModel
        .updateAlarm(widget.alarm, wake, _days, widget.alarm.label);
    if (mounted) showRingsInPill(context, widget.alarm);
  }

  void _toggleEnabled() {
    widget.viewModel.toggleAlarmState(widget.alarm);
    setState(() {});
    if (widget.alarm.isEnabled) showRingsInPill(context, widget.alarm);
  }

  int get _sleepMinutes => (_wakeMin - _bedMin + 1440) % 1440;

  String _durationText() {
    final m = _sleepMinutes;
    final h = m ~/ 60;
    final mm = m % 60;
    return mm == 0 ? '$h H' : '$h H ${mm.toString().padLeft(2, '0')} MIN';
  }

  String _eventLabel(String event) {
    switch (event) {
      case 'bedtime':
        return tr('AT BEDTIME');
      case 'wake':
        return tr('WHEN THE ALARM RINGS');
      default:
        return tr('WHEN I WAKE UP');
    }
  }

  Future<void> _pick(String event) async {
    List<HaEntity> entities;
    try {
      entities = await HaService.listEntities();
    } catch (e) {
      if (mounted) {
        showNothingPill(context, e.toString().replaceFirst('Exception: ', ''));
      }
      return;
    }
    if (!mounted) return;
    final result = await showDialog<_PickResult>(
      context: context,
      builder: (_) => _EntityPicker(entities: entities),
    );
    if (result == null) return;
    final p = await SharedPreferences.getInstance();
    if (result.entity == null) {
      await p.remove('ha_entity_$event');
      await p.remove('ha_name_$event');
      _haNames.remove(event);
    } else {
      await p.setString('ha_entity_$event', result.entity!.id);
      await p.setString('ha_name_$event', result.entity!.name);
      _haNames[event] = result.entity!.name;
    }
    if (mounted) setState(() {});
  }

  Future<void> _test(String event) async {
    final err = await HaService.test(event);
    if (mounted) showNothingPill(context, err ?? tr('Sent'));
  }

  Widget _label(String text) => Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                const BoxDecoration(shape: BoxShape.circle, color: nothingRed),
          ),
          const SizedBox(width: 10),
          Text(text,
              style: const TextStyle(color: _gray, fontSize: 12, letterSpacing: 2)),
        ],
      );

  Widget _timeCard(String label, int minutes, ValueChanged<int> onChanged) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          SizedBox(
            height: 140,
            child: CupertinoTheme(
              data: const CupertinoThemeData(brightness: Brightness.dark),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: true,
                initialDateTime: DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60),
                onDateTimeChanged: (d) {
                  onChanged(d.hour * 60 + d.minute);
                  setState(() {});
                  _scheduleSave();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          color: selected ? Colors.white : Colors.transparent,
          border: Border.all(color: Colors.white54, width: 0.5),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _haCard() {
    final theme = Theme.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(tr('HOME ASSISTANT')),
          const SizedBox(height: 10),
          if (!_haConfigured)
            Text(
              _hasNc
                  ? tr('Add haUrl and haToken to .ecosystem/config.json in your Nextcloud')
                  : tr('Connect Nextcloud first'),
              style: TextStyle(color: _gray, fontSize: 13, height: 1.3, backgroundColor: theme.colorScheme.tertiary.withOpacity(0)),
            )
          else ...[
            Text(Uri.tryParse(_haUrl)?.host ?? _haUrl,
                style: const TextStyle(color: _gray, fontSize: 12)),
            for (final e in HaService.events)
              InkWell(
                onTap: () => _pick(e),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_eventLabel(e),
                                style: const TextStyle(
                                    color: _gray, fontSize: 11, letterSpacing: 1.5)),
                            const SizedBox(height: 4),
                            Text(_haNames[e] ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 15)),
                          ],
                        ),
                      ),
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _test(e),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white54, width: 0.5),
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('SLEEP TIME'), style: theme.textTheme.bodyMedium),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            Center(
              child: Text(
                _durationText(),
                style: TextStyle(
                    fontFamily: 'NDot',
                    fontSize: 46,
                    color: theme.colorScheme.onSurface),
              ),
            ),
            Center(
              child: Text(tr('SLEEP'),
                  style: const TextStyle(color: _gray, fontSize: 12, letterSpacing: 3)),
            ),
            const SizedBox(height: 22),
            _timeCard(tr('BEDTIME'), _bedMin, (v) => _bedMin = v),
            const SizedBox(height: 10),
            _timeCard(tr('WAKE UP'), _wakeMin, (v) => _wakeMin = v),
            const SizedBox(height: 10),
            _Card(
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final d in _order)
                          AlarmDayBtn(
                            dayInital: trInitial(d),
                            dayKey: d,
                            selectedDays: _days,
                            isEnabled: true,
                            isSelected: _days[d] ?? false,
                            onPressed: () {
                              setState(() {});
                              _scheduleSave();
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(tr('ACTIVE'),
                          style: const TextStyle(
                              color: _gray, fontSize: 12, letterSpacing: 2)),
                      const Spacer(),
                      SwitchButton(
                        defaultValue: widget.alarm.isEnabled,
                        onChanged: _toggleEnabled,
                        inactiveTrackColor: Colors.transparent,
                        activeTrackColor: Colors.transparent,
                        outlineColor: Colors.white,
                        inactiveThumbColor: Colors.white,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(tr('REMINDER')),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in const [0, 15, 30, 45, 60])
                        _chip(m == 0 ? tr('OFF') : '$m MIN', _reminder == m, () {
                          setState(() => _reminder = m);
                          _scheduleSave();
                        }),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _haCard(),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(15),
      ),
      child: child,
    );
  }
}

class _PickResult {
  final HaEntity? entity;
  const _PickResult(this.entity);
}

class _EntityPicker extends StatefulWidget {
  final List<HaEntity> entities;
  const _EntityPicker({required this.entities});

  @override
  State<_EntityPicker> createState() => _EntityPickerState();
}

class _EntityPickerState extends State<_EntityPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.entities
        .where((e) =>
            e.name.toLowerCase().contains(_q) || e.id.toLowerCase().contains(_q))
        .toList();
    return AlertDialog(
      title: TextField(
        decoration: InputDecoration(hintText: tr('Search')),
        onChanged: (v) => setState(() => _q = v.toLowerCase().trim()),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: ListView(
          children: [
            ListTile(
              title: Text(tr('None')),
              onTap: () => Navigator.pop(context, const _PickResult(null)),
            ),
            for (final e in filtered)
              ListTile(
                title: Text(e.name),
                subtitle: Text(e.id, style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(context, _PickResult(e)),
              ),
          ],
        ),
      ),
    );
  }
}
