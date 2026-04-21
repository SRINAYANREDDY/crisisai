// location_service.dart
// ---------------------------------------------------------------------------
// Singleton that fetches the device's live GPS location and reverse-geocodes
// it to a human-readable address. Both HomeScreen and MapScreen use this so
// the same location is shared without duplicate permission requests.
// ---------------------------------------------------------------------------

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  // ── State ──────────────────────────────────────────────────────────────────
  Position? _position;
  String _address = '';
  String _shortLocality = ''; // e.g. "Ranipet, Tamil Nadu"
  bool _initialized = false;
  bool _loading = false;
  String? _error;

  // ── Notifiers so UI can rebuild when location arrives ────────────────────
  final ValueNotifier<bool> loadingNotifier = ValueNotifier(false);
  final ValueNotifier<String> addressNotifier = ValueNotifier('');
  final ValueNotifier<String> localityNotifier = ValueNotifier('');

  // ── Getters ─────────────────────────────────────────────────────────────
  Position? get position => _position;
  String get address => _address;
  String get shortLocality => _shortLocality;
  bool get isReady => _initialized && _position != null;
  bool get isLoading => _loading;
  String? get error => _error;

  double? get latitude => _position?.latitude;
  double? get longitude => _position?.longitude;

  // ── Initialize (idempotent — safe to call multiple times) ────────────────
  Future<void> initialize() async {
    if (_initialized || _loading) return;
    _loading = true;
    loadingNotifier.value = true;

    try {
      // 1. Check location service
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _error = 'Location services disabled. Please enable GPS.';
        _initialized = true;
        return;
      }

      // 2. Check / request permission
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _error = 'Location permission denied.';
        _initialized = true;
        return;
      }

      // 3. Get position
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _position = pos;

      // 4. Reverse geocode
      await _reverseGeocode(pos.latitude, pos.longitude);

      _error = null;
    } catch (e) {
      _error = 'Could not determine location.';
      debugPrint('[LocationService] Error: $e');
    } finally {
      _initialized = true;
      _loading = false;
      loadingNotifier.value = false;
    }
  }

  // ── Reverse geocode ──────────────────────────────────────────────────────
  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;

        // Full address: "Ranipet, Tamil Nadu, India"
        final fullParts = [
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.country,
        ].where((s) => s != null && s.isNotEmpty).toList();

        _address = fullParts.isNotEmpty
            ? fullParts.join(', ')
            : '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';

        // Short locality for display in hero card / header
        final shortParts = [
          p.subLocality,
          p.locality,
        ].where((s) => s != null && s.isNotEmpty).toList();

        _shortLocality = shortParts.isNotEmpty
            ? shortParts.join(', ')
            : p.administrativeArea ?? _address;

        addressNotifier.value = _address;
        localityNotifier.value = _shortLocality;
      }
    } catch (e) {
      final fallback = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
      _address = fallback;
      _shortLocality = fallback;
      addressNotifier.value = fallback;
      localityNotifier.value = fallback;
      debugPrint('[LocationService] Geocoding error: $e');
    }
  }

  // ── Force refresh ─────────────────────────────────────────────────────────
  Future<void> refresh() async {
    _initialized = false;
    await initialize();
  }
}
