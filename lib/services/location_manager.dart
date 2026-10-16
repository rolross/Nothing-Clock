import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:nothing_clock/models/user_position.dart';

class LocationManager {
  static final LocationManager _instance = LocationManager._internal();

  UserPosition? _currentPosition;
  UserPosition? get currentPosition => _currentPosition;

  String? lastError;

  late final Future<void> initialization;

  LocationManager._internal() {
    initialization = _initializeLocation();
  }

  factory LocationManager() {
    return _instance;
  }

  int _deviceUtcOffset() => DateTime.now().timeZoneOffset.inHours;

  Future<Placemark?> _reverseGeocodeOnline(double lat, double lon) async {
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json&zoom=10&addressdetails=1');
      final response = await http
          .get(url, headers: {'User-Agent': 'NothingClock/1.0'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final address = (data['address'] as Map?) ?? {};
      final name = address['city'] ??
          address['town'] ??
          address['village'] ??
          address['municipality'] ??
          address['county'] ??
          address['state'];
      if (name == null) return null;
      return Placemark(
        locality: name.toString(),
        country: address['country']?.toString(),
        isoCountryCode: address['country_code']?.toString().toUpperCase(),
      );
    } catch (e) {
      debugPrint("Online reverse geocoding failed: $e");
      return null;
    }
  }

  Future<UserPosition> getAddressFromLatLng(Position? position) async {
    position ??= await _determineUserPosition();

    Placemark? placemark;
    try {
      final list =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      if (list.isNotEmpty) placemark = list.first;
    } catch (e) {
      debugPrint("Geocoding failed: $e");
    }

    final locality = placemark?.locality;
    if (locality == null || locality.isEmpty) {
      final fallback =
          await _reverseGeocodeOnline(position.latitude, position.longitude);
      if (fallback != null) placemark = fallback;
    }

    return UserPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      utcOffset: _deviceUtcOffset(),
      placemark: placemark,
    );
  }

  Future<void> saveLocation(UserPosition position) async {
    const FlutterSecureStorage storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true));
    await storage.write(key: "latitude", value: position.latitude.toString());
    await storage.write(key: "longitude", value: position.longitude.toString());
    await storage.write(
        key: "placemark",
        value: UserPosition.serializePlacemark(position.placemark));
    await storage.write(key: "utcOffset", value: position.utcOffset.toString());
  }

  Future<UserPosition> loadLocation() async {
    const FlutterSecureStorage storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true));
    String? latitude = await storage.read(key: "latitude");
    String? longitude = await storage.read(key: "longitude");
    String? utcOffset = await storage.read(key: "utcOffset");
    String? placemarkString = await storage.read(key: "placemark");

    Placemark? placemark;
    if (placemarkString != null) {
      placemark = UserPosition.deserializePlacemark(placemarkString);
    }

    if (latitude == null || longitude == null || utcOffset == null) {
      return UserPosition(
          latitude: null, longitude: null, placemark: placemark, utcOffset: 0);
    }

    return UserPosition(
        latitude: double.parse(latitude),
        longitude: double.parse(longitude),
        utcOffset: int.parse(utcOffset),
        placemark: placemark);
  }

  Future<Position> _determineUserPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception("Location services are disabled.");
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception("Location permission not granted.");
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      rethrow;
    }
  }

  Future<void> _initializeLocation() async {
    UserPosition cached;
    try {
      cached = await loadLocation();
    } catch (e) {
      debugPrint("Secure storage failed, resetting: $e");
      try {
        await const FlutterSecureStorage(
                aOptions: AndroidOptions(encryptedSharedPreferences: true))
            .deleteAll();
      } catch (_) {}
      cached = UserPosition(latitude: null, longitude: null, utcOffset: 0);
    }

    if (cached.latitude != null && cached.longitude != null) {
      _currentPosition = UserPosition(
        latitude: cached.latitude,
        longitude: cached.longitude,
        placemark: cached.placemark,
        utcOffset: _deviceUtcOffset(),
      );
      debugPrint("Loaded cached location: $_currentPosition");
      return;
    }

    await _refreshLocation();
  }

  Future<void> openSettingsIfBlocked() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> refresh() => _refreshLocation();

  Future<void> _refreshLocation() async {
    try {
      final locationAddress = await getAddressFromLatLng(null);
      _currentPosition = locationAddress;
      lastError = null;
      await saveLocation(locationAddress);
    } catch (e) {
      debugPrint("Error initializing location: $e");
      lastError = e.toString().replaceFirst('Exception: ', '');
    }
  }
}
