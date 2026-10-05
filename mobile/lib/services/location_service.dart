import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {

  // ============================================================
  // GET CURRENT GPS POSITION
  // ============================================================

  Future<Position> getCurrentLocation() async {
    final serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception(
        'Location services are disabled. Please enable GPS.',
      );
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        throw Exception(
          'Location permission was denied.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. '
            'Please enable it from app settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  // ============================================================
  // REVERSE GEOCODE — coordinates → human-readable address
  // Returns a short address string, or null on failure.
  // ============================================================

  Future<String?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isEmpty) return null;

      final place = placemarks.first;

      // Build a short, human-readable address
      final parts = <String>[];

      if (place.name != null &&
          place.name!.isNotEmpty &&
          place.name != place.street) {
        parts.add(place.name!);
      }

      if (place.street != null &&
          place.street!.isNotEmpty) {
        parts.add(place.street!);
      }

      if (place.subLocality != null &&
          place.subLocality!.isNotEmpty) {
        parts.add(place.subLocality!);
      }

      if (place.locality != null &&
          place.locality!.isNotEmpty) {
        parts.add(place.locality!);
      }

      if (parts.isEmpty) {
        // Fallback to just showing coordinates
        return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
      }

      return parts.take(3).join(', ');
    } catch (_) {
      return null;
    }
  }
}