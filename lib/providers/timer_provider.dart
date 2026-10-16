import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nothing_clock/services/timer_service.dart';
import 'package:nothing_clock/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String formatTimerSeconds(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

class SavedTimer {
  final String id;
  String name;
  int seconds;

  SavedTimer({required this.id, required this.name, required this.seconds});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'seconds': seconds};

  factory SavedTimer.fromJson(Map<String, dynamic> j) => SavedTimer(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        seconds: (j['seconds'] as int?) ?? 60,
      );
}

class TimerProvider with ChangeNotifier, WidgetsBindingObserver {
  List<SavedTimer> _timers = [];
  String? _activeId;
  String _state = 'idle'; // idle | running | paused | completed
  int _totalSeconds = 0;
  int _remainingSeconds = 0;
  DateTime? _endTime;
  bool _viewing = false;
  bool _isPickerMode = false;
  Duration _pickerDuration = Duration.zero;
  Timer? _ui;

  TimerProvider() {
    WidgetsBinding.instance.addObserver(this);
    TimerService.changes.addListener(_syncFromPrefs);
    SyncService.remoteApplied.addListener(_onRemoteApplied);
    _init();
  }

  List<SavedTimer> get timers => _timers;
  bool get viewing => _viewing;
  bool get isRunning => _state == 'running';
  bool get isCompleted => _state == 'completed';
  bool get isPickerMode => _isPickerMode;
  Duration get pickerDuration => _pickerDuration;
  int get remainingSeconds => _remainingSeconds;
  int get totalSeconds => _totalSeconds;
  String? get activeId => _activeId;
  bool get hasActive => _activeId != null && _state != 'idle';

  SavedTimer? get activeTimer {
    for (final t in _timers) {
      if (t.id == _activeId) return t;
    }
    return null;
  }

  double get progress {
    if (_state == 'completed') return 1.0;
    if (_totalSeconds <= 0) return 0.0;
    final totalMs = _totalSeconds * 1000;
    if (_state == 'running' && _endTime != null) {
      final leftMs = _endTime!.difference(DateTime.now()).inMilliseconds;
      return (1 - leftMs / totalMs).clamp(0.0, 1.0).toDouble();
    }
    return (1 - _remainingSeconds / _totalSeconds).clamp(0.0, 1.0).toDouble();
  }

  Future<void> _init() async {
    await _loadSaved();
    await _syncFromPrefs();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncFromPrefs();
  }

  Future<void> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('saved_timers') ?? [];
      _timers = list
          .map((s) => SavedTimer.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading timers: $e');
    }
  }

  Future<void> _saveTimers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'saved_timers', _timers.map((t) => jsonEncode(t.toJson())).toList());
    SyncService.markDirty();
  }

  Future<void> _onRemoteApplied() async {
    await _loadSaved();
    notifyListeners();
  }

  Future<void> _syncFromPrefs() async {
    final s = await TimerService.loadState();
    _activeId = s.activeId;
    _totalSeconds = s.total;
    _endTime = s.end;
    _state = s.state;
    if (_activeId == null) {
      _state = 'idle';
      _viewing = false;
      _isPickerMode = false;
    }
    switch (_state) {
      case 'running':
        _recompute();
        break;
      case 'paused':
        _remainingSeconds = s.pausedRemaining;
        break;
      default:
        _remainingSeconds = 0;
    }
    _manageUiTimer();
    notifyListeners();
  }

  void _recompute() {
    if (_endTime == null) return;
    final ms = _endTime!.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) {
      _remainingSeconds = 0;
      _state = 'completed';
    } else {
      _remainingSeconds = (ms + 999) ~/ 1000;
    }
  }

  void _manageUiTimer() {
    if (_state == 'running') {
      _ui ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
        _recompute();
        if (_state != 'running') {
          _ui?.cancel();
          _ui = null;
        }
        notifyListeners();
      });
    } else {
      _ui?.cancel();
      _ui = null;
    }
  }

  // ---------- Saved timers ----------

  Future<void> addTimer(String name, int seconds) async {
    _timers.add(SavedTimer(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      seconds: seconds,
    ));
    await _saveTimers();
    notifyListeners();
  }

  Future<void> updateTimer(SavedTimer t, String name, int seconds) async {
    t.name = name;
    t.seconds = seconds;
    await _saveTimers();
    if (_activeId == t.id) {
      await TimerService.updateName(name);
    }
    notifyListeners();
  }

  Future<void> deleteTimer(SavedTimer t) async {
    if (_activeId == t.id) {
      await stopActive();
    }
    _timers.removeWhere((x) => x.id == t.id);
    await _saveTimers();
    notifyListeners();
  }

  // ---------- Running timer ----------

  Future<void> playSaved(SavedTimer t) async {
    _isPickerMode = false;
    if (_activeId == t.id && (_state == 'running' || _state == 'paused')) {
      _viewing = true;
      notifyListeners();
      if (_state == 'paused') {
        await toggle();
      }
      return;
    }
    _activeId = t.id;
    _totalSeconds = t.seconds;
    _remainingSeconds = t.seconds;
    _state = 'running';
    _endTime = DateTime.now().add(Duration(seconds: t.seconds));
    _viewing = true;
    _manageUiTimer();
    notifyListeners();
    await TimerService.start(
      id: t.id,
      name: t.name,
      total: t.seconds,
      remaining: t.seconds,
    );
  }

  Future<void> toggle() async {
    if (_activeId == null) return;
    if (_state == 'running') {
      _recompute();
      final rem = _remainingSeconds;
      _state = 'paused';
      _endTime = null;
      _manageUiTimer();
      notifyListeners();
      await TimerService.pause(remaining: rem, total: _totalSeconds);
    } else if (_state == 'paused') {
      _state = 'running';
      _endTime = DateTime.now().add(Duration(seconds: _remainingSeconds));
      _manageUiTimer();
      notifyListeners();
      await TimerService.start(
        id: _activeId!,
        name: activeTimer?.name ?? '',
        total: _totalSeconds,
        remaining: _remainingSeconds,
      );
    }
  }

  /// Ajuste rápido (+1/-1 min): solo afecta a esta ejecución, no se guarda.
  Future<void> adjust(int delta) async {
    if (_activeId == null || _state == 'completed') return;
    _recompute();
    final newRemaining = (_remainingSeconds + delta).clamp(1, 360000).toInt();
    final eff = newRemaining - _remainingSeconds;
    var newTotal = _totalSeconds + eff;
    if (newTotal < newRemaining) newTotal = newRemaining;
    _totalSeconds = newTotal;
    _remainingSeconds = newRemaining;
    if (_state == 'running') {
      _endTime = DateTime.now().add(Duration(seconds: newRemaining));
      notifyListeners();
      await TimerService.start(
        id: _activeId!,
        name: activeTimer?.name ?? '',
        total: newTotal,
        remaining: newRemaining,
      );
    } else {
      notifyListeners();
      await TimerService.pause(remaining: newRemaining, total: newTotal);
    }
  }

  Future<void> openPicker() async {
    if (_activeId == null || _state == 'completed') return;
    if (_state == 'running') await toggle();
    _pickerDuration = Duration(seconds: activeTimer?.seconds ?? _totalSeconds);
    _isPickerMode = true;
    notifyListeners();
  }

  void updatePickerDuration(Duration d) {
    _pickerDuration = d;
  }

  Future<void> confirmPicker() async {
    final secs = _pickerDuration.inSeconds;
    _isPickerMode = false;
    final t = activeTimer;
    if (secs > 0 && t != null) {
      t.seconds = secs;
      await _saveTimers();
      _totalSeconds = secs;
      _remainingSeconds = secs;
      notifyListeners();
      await TimerService.pause(remaining: secs, total: secs);
    } else {
      notifyListeners();
    }
  }

  void cancelPicker() {
    _isPickerMode = false;
    notifyListeners();
  }

  Future<void> renameActive(String name) async {
    final t = activeTimer;
    if (t == null) return;
    t.name = name;
    await _saveTimers();
    await TimerService.updateName(name);
    notifyListeners();
  }

  void closeView() {
    _viewing = false;
    _isPickerMode = false;
    notifyListeners();
  }

  Future<void> stopActive() async {
    _state = 'idle';
    _activeId = null;
    _viewing = false;
    _isPickerMode = false;
    _ui?.cancel();
    _ui = null;
    notifyListeners();
    await TimerService.stop();
  }

  Future<void> snoozeActive() async {
    await TimerService.snooze(1);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TimerService.changes.removeListener(_syncFromPrefs);
    SyncService.remoteApplied.removeListener(_onRemoteApplied);
    _ui?.cancel();
    super.dispose();
  }
}
