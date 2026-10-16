import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nothing_clock/models/timezone_data.dart';
import 'package:nothing_clock/models/world_clock_data.dart';
import 'package:http/http.dart' as http;
import 'package:nothing_clock/providers/clock_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nothing_clock/services/sync_service.dart';

/// This provider manages a list of world clocks and updates their times
/// based on a native event channel that emits time tick events.
class WorldClocksProvider with ChangeNotifier {
  List<WorldClockData> _worldClocks = [];

  List<WorldClockData> get worldClocks => _worldClocks;

    // Subscription to the time tick stream.
  StreamSubscription<dynamic>? _timeTickSubscription;
  Timer? _secondsTimer;
  bool _showSeconds = false;
  bool get showSeconds => _showSeconds;

  WorldClocksProvider(BuildContext context) {
    _initialize();
    _subscribeToTimeTick(context);
    SyncService.remoteApplied.addListener(_onRemoteApplied);
  }

  /// Asynchronously initializes the world clocks by fetching their time data.
  Future<void> _initialize() async {
    final prefsSeconds = await SharedPreferences.getInstance();
    _showSeconds = prefsSeconds.getBool('show_seconds') ?? false;
    WorldClockData.showSeconds = _showSeconds;
    _updateSecondsTimer();
    await _loadWorldClocks();
    await _fetchInitialTimeData(); 
    notifyListeners();
  }

  /// Loads saved world clocks from SharedPreferences
  Future<void> _loadWorldClocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? worldClockStrings = prefs.getStringList('world_clocks');
      
      if (worldClockStrings != null && worldClockStrings.isNotEmpty) {
        _worldClocks = worldClockStrings.map((clockString) {
          final Map<String, dynamic> clockData = jsonDecode(clockString);
          return WorldClockData(
            currentFormattedTime: clockData['currentFormattedTime'] ?? "00:00",
            utcTime: clockData['utcTime'] ?? 0,
            longitude: clockData['longitude'] ?? 0.0,
            latitude: clockData['latitude'] ?? 0.0,
            displayName: clockData['displayName'] ?? "Unknown",
            timezoneId: clockData['timezoneId'],
          );
        }).toList();
        
        debugPrint("Loaded ${_worldClocks.length} world clocks from storage");
      }
    } catch (e) {
      debugPrint("Error loading world clocks: $e");
    }
  }

  /// Saves world clocks to SharedPreferences
  Future<void> _saveWorldClocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final List<String> worldClockStrings = _worldClocks.map((clock) {
        return jsonEncode({
          'currentFormattedTime': clock.currentFormattedTime,
          'utcTime': clock.utcTime,
          'longitude': clock.longitude,
          'latitude': clock.latitude,
          'displayName': clock.displayName,
          'timezoneId': clock.timezoneId,
        });
      }).toList();
      
      await prefs.setStringList('world_clocks', worldClockStrings);
      SyncService.markDirty();
      debugPrint("Saved ${worldClockStrings.length} world clocks to storage");
    } catch (e) {
      debugPrint("Error saving world clocks: $e");
    }
  }

  Future<void> _fetchInitialTimeData() async {
    for (var worldClock in _worldClocks) {

      // Fetch the UTC offset for the given continent and capital.
      final response = await _fetchUtcTimezone(worldClock.latitude, worldClock.longitude);
      worldClock.utc = response.utcOffset;
      worldClock.timezoneId = _lastTimezoneId ?? worldClock.timezoneId;

      // Recalculate the clock's time offset based on the new UTC value and the standard UTC time.
      worldClock.calculateTimeOffset();
    }
    await _saveWorldClocks();

    notifyListeners();
  }

  /// Subscribes to the shared clock event stream provided by ClockProvider.
  /// This method listens to the native time tick events and updates the clocks.
  void _subscribeToTimeTick(BuildContext context) {
    final clockProvider = Provider.of<ClockProvider>(context, listen: false);

    _timeTickSubscription = clockProvider.clockStream.listen((event) {
      debugPrint("Time tick event received: $event");
      updateWorldClocks();
    }, onError: (error) {
      debugPrint("Error receiving time tick event: $error");
    });
  }

  @override
  void dispose() {
    _timeTickSubscription?.cancel();
    SyncService.remoteApplied.removeListener(_onRemoteApplied);
    _secondsTimer?.cancel();
    super.dispose();
  }

  Future<void> setShowSeconds(bool value) async {
    _showSeconds = value;
    WorldClockData.showSeconds = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_seconds', value);
    SyncService.markDirty();
    _updateSecondsTimer();
    updateWorldClocks();
  }

  void _updateSecondsTimer() {
    _secondsTimer?.cancel();
    _secondsTimer = null;
    if (_showSeconds) {
      _secondsTimer = null;
    }
  }

  Future<void> _onRemoteApplied() async {
    final prefs = await SharedPreferences.getInstance();
    _showSeconds = prefs.getBool('show_seconds') ?? false;
    WorldClockData.showSeconds = _showSeconds;
    _updateSecondsTimer();
    await _loadWorldClocks();
    await _fetchInitialTimeData();
    notifyListeners();
  }

  /// Updates all world clocks by recalculating their time offsets.
  /// Notifies listeners so that the UI can refresh.
  void updateWorldClocks() {
    for (var worldClock in _worldClocks) {
      worldClock.calculateTimeOffset();
    }

    notifyListeners();
  }

  /// Fetches the UTC timezone data for the given coordinates.
  /// Returns a TimezoneData object containing the UTC offset.
  String? _lastTimezoneId;

  Future<TimezoneData> _fetchUtcTimezone(double latitude, double longitude) async {
    _lastTimezoneId = null;
    int offset = 0;
    try {
      final response = await http
          .get(Uri.parse(
              'https://secure.geonames.org/timezoneJSON?lat=$latitude&lng=$longitude&username=sashachverenko'))
          .timeout(const Duration(seconds: 10));
      final jsonData = jsonDecode(response.body);
      _lastTimezoneId = jsonData['timezoneId'] as String?;
      final num raw = (jsonData['dstOffset'] ?? jsonData['gmtOffset'] ?? 0) as num;
      offset = raw.round();
    } catch (e) {
      debugPrint("Error fetching time (geonames): $e");
    }

    if (_lastTimezoneId == null) {
      try {
        final response = await http
            .get(Uri.parse(
                'https://timeapi.io/api/TimeZone/coordinate?latitude=$latitude&longitude=$longitude'))
            .timeout(const Duration(seconds: 10));
        final jsonData = jsonDecode(response.body);
        _lastTimezoneId = jsonData['timeZone'] as String?;
      } catch (e) {
        debugPrint("Error fetching time (timeapi): $e");
      }
    }

    return TimezoneData(utcOffset: offset);
  }

  /// Checks if a world clock with similar coordinates already exists.
  /// We use a small threshold to determine if locations are "close enough" to be considered the same.
  bool _isDuplicateLocation(double latitude, double longitude) {
    const double threshold = 0.1; // Approximately 11km at the equator
    
    for (var clock in _worldClocks) {
      // Check if coordinates are very close
      if ((latitude - clock.latitude).abs() < threshold && 
          (longitude - clock.longitude).abs() < threshold) {
        return true;
      }
    }
    
    return false;
  }

  /// Adds a new world clock to the list.
  /// Returns true if the clock was added, false if it was a duplicate.
  Future<bool> addWorldClock(WorldClockData worldClock) async {
    // Check if the location already exists
    if (_isDuplicateLocation(worldClock.latitude, worldClock.longitude)) {
      debugPrint("Duplicate location found, not adding: ${worldClock.displayName}");
      return false;
    }
    
    TimezoneData timezoneData = await _fetchUtcTimezone(worldClock.latitude, worldClock.longitude);
    worldClock.utc = timezoneData.utcOffset;
    worldClock.timezoneId = _lastTimezoneId;
    worldClock.calculateTimeOffset();
    
    _worldClocks.add(worldClock);
    _saveWorldClocks();

    notifyListeners();
    return true;
  }

  /// Removes a world clock from the list.
  void removeWorldClock(WorldClockData worldClock) {
    _worldClocks.remove(worldClock);
    _saveWorldClocks();
    notifyListeners();
  }
}
