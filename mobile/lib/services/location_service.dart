import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'issue_service.dart';

class LocationService {
  // Shared in-memory cache of rounded coordinates -> address
  static final Map<String, String> _cache = {};

  // In-flight deduplication to prevent duplicate concurrent lookups
  static final Map<String, Future<String?>> _inFlight = {};

  // ============================================================
  // GET CURRENT GPS POSITION
  // ============================================================

  Future<Position> getCurrentLocation({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        throw Exception('Location permission was denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Please enable it in app settings.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
    } on TimeoutException {
      // Try last known position as fallback if available
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          return lastKnown;
        }
      } catch (_) {}
      throw Exception('GPS request timed out. Please check your signal and try again.');
    } catch (e) {
      throw Exception('Unable to get GPS location: ${e.toString()}');
    }
  }

  // ============================================================
  // REVERSE GEOCODE — coordinates → human-readable address
  // Returns a short address string, or null on failure (NEVER coordinates).
  // ============================================================

  Future<String?> reverseGeocode({
    required double latitude,
    required double longitude,
    IssueService? issueService,
  }) async {
    // Validate bounds
    if (latitude < -90.0 || latitude > 90.0 || longitude < -180.0 || longitude > 180.0) {
      return null;
    }

    final key = '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';

    // 1. Check in-memory cache
    if (_cache.containsKey(key)) {
      return _cache[key];
    }

    // 2. Deduplicate in-flight requests for identical coordinates
    if (_inFlight.containsKey(key)) {
      return _inFlight[key];
    }

    final future = _performReverseGeocode(
      latitude: latitude,
      longitude: longitude,
      key: key,
      issueService: issueService,
    );

    _inFlight[key] = future;

    try {
      final result = await future;
      if (result != null && result.isNotEmpty) {
        _cache[key] = result;
      }
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<String?> _performReverseGeocode({
    required double latitude,
    required double longitude,
    required String key,
    IssueService? issueService,
  }) async {
    // Attempt 1 & 2: Native device geocoding
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final geocoding = Geocoding();
        final placemarks = await geocoding
            .placemarkFromCoordinates(
              latitude,
              longitude,
            )
            .timeout(const Duration(seconds: 5));

        if (placemarks.isNotEmpty) {
          final formatted = _formatPlacemark(placemarks.first);
          if (formatted != null && formatted.isNotEmpty) {
            return formatted;
          }
        }
      } catch (e) {
        debugPrint('[LocationService] Native geocoding attempt $attempt failed: $e');
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    }

    // Attempt 3: Backend reverse-geocoding fallback (OpenStreetMap Nominatim via Django)
    if (issueService != null) {
      try {
        final backendAddress = await issueService
            .reverseGeocodeViaBackend(
              latitude: latitude,
              longitude: longitude,
            )
            .timeout(const Duration(seconds: 6));

        if (backendAddress != null && backendAddress.isNotEmpty) {
          return backendAddress;
        }
      } catch (e) {
        debugPrint('[LocationService] Backend geocoding fallback failed: $e');
      }
    }

    return null;
  }

  String? _formatPlacemark(Placemark place) {
    final parts = <String>[];

    // 1. Street / Road name
    final street = place.street?.trim();
    final name = place.name?.trim();

    if (name != null && name.isNotEmpty && name != street && !name.contains('+')) {
      parts.add(name);
    }

    if (street != null && street.isNotEmpty && !street.contains('+') && !parts.contains(street)) {
      parts.add(street);
    }

    // 2. SubLocality / Neighborhood
    final subLocality = place.subLocality?.trim();
    if (subLocality != null && subLocality.isNotEmpty && !parts.contains(subLocality)) {
      parts.add(subLocality);
    }

    // 3. Locality / City / Town
    final locality = place.locality?.trim();
    if (locality != null && locality.isNotEmpty && !parts.contains(locality)) {
      parts.add(locality);
    }

    // 4. District / Administrative Area fallback
    if (parts.length < 2) {
      final subAdmin = place.subAdministrativeArea?.trim();
      if (subAdmin != null && subAdmin.isNotEmpty && !parts.contains(subAdmin)) {
        parts.add(subAdmin);
      }
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.take(3).join(', ');
  }
}