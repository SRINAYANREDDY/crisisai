// volunteer_repository.dart
// ---------------------------------------------------------------------------
// Live Firestore volunteer feed.
//
// Replaces every hardcoded list in AppData:
//   • AppData.sosVolunteers     → sosVolunteersStream  (VoiceSOSService format)
//   • AppData.nearbyVolunteers  → nearbyVolunteersStream (HomeScreen UI format)
//
// HOW IT WORKS
// ─────────────
// 1. Queries the `volunteers` collection for docs where `isOnline == true`.
// 2. Computes distanceKm from the device's live GPS (LocationService).
// 3. Filters to volunteers within [radiusKm] (default 10 km).
// 4. Sorts by distance ascending.
// 5. Emits two parallel streams: one in SOS-dispatch format, one in UI format.
//
// FIRESTORE DOCUMENT SCHEMA  (collection: `volunteers`)
// ─────────────────────────────────────────────────────
// {
//   uid:        "abc123",
//   name:       "Priya Sharma",
//   initials:   "PS",
//   phone:      "+91 98765 43210",
//   skills:     ["first_aid", "cpr", "trauma"],       // skill-key format
//   skillLabels:["First Aid", "CPR", "Trauma"],       // display labels (optional)
//   level:      5,
//   xp:         1200,
//   color:      0xFFE24B4A,                           // int, optional
//   isOnline:   true,                                 // bool — REQUIRED for query
//   location:   GeoPoint(12.9282, 79.3328),           // REQUIRED for distance calc
//   lastSeen:   Timestamp,
//   role:       "volunteer",
// }
//
// FIRESTORE INDEX REQUIRED
// ─────────────────────────
// Collection: volunteers
// Fields:    isOnline (Ascending) + location (Ascending)   [composite]
//
// OR simply enable isOnline as a single-field index (auto-created on first
// query). The distance filter runs client-side so no geo index is needed.
//
// SECURITY RULES (paste into Firebase Console → Firestore → Rules)
// ─────────────────────────────────────────────────────────────────
// match /volunteers/{uid} {
//   allow read: if request.auth != null;
//   allow write: if request.auth.uid == uid;
// }
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'location_service.dart';

// ---------------------------------------------------------------------------
// VolunteerRepository  (singleton)
// ---------------------------------------------------------------------------

class VolunteerRepository {
  VolunteerRepository._();
  static final VolunteerRepository instance = VolunteerRepository._();

  static const double _defaultRadiusKm = 10.0;
  static const int _maxResults = 20;

  final _firestore = FirebaseFirestore.instance;

  // ── Notifiers that HomeScreen / VoiceSOSSheet can listen to ─────────────
  final ValueNotifier<List<Map<String, dynamic>>> sosVolunteersNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<Map<String, dynamic>>> nearbyVolunteersNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> loadingNotifier = ValueNotifier(false);
  final ValueNotifier<String?> errorNotifier = ValueNotifier(null);

  StreamSubscription<QuerySnapshot>? _sub;
  bool _started = false;

  // ── Start listening (call once from main.dart or HomeScreen.initState) ───
  void startListening({double radiusKm = _defaultRadiusKm}) {
    if (_started) return;
    _started = true;
    loadingNotifier.value = true;

    _sub = _firestore
        .collection('volunteers')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .listen(
          (snap) => _onSnapshot(snap, radiusKm),
          onError: (Object e) {
            errorNotifier.value = 'Could not load volunteers.';
            loadingNotifier.value = false;
            debugPrint('[VolunteerRepository] Firestore error: $e');
          },
        );
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  // ── Process a Firestore snapshot ─────────────────────────────────────────
  void _onSnapshot(QuerySnapshot snap, double radiusKm) {
    final userLat = LocationService.instance.latitude;
    final userLng = LocationService.instance.longitude;

    final List<_VolunteerEntry> entries = [];

    for (final doc in snap.docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;

        // Skip self (logged-in user's own doc) — uid stored in AppData
        // Uncomment if you import AppData:
        // if (doc.id == AppData.volunteerProfile['uid']) continue;

        // Distance calculation
        double distanceKm = 0.0;
        final geoPoint = data['location'] as GeoPoint?;
        if (geoPoint != null && userLat != null && userLng != null) {
          distanceKm = _haversineKm(
            userLat,
            userLng,
            geoPoint.latitude,
            geoPoint.longitude,
          );
        }

        // Filter by radius (skip if location unknown — include them anyway
        // so the app doesn't silently drop volunteers with missing geopoints)
        if (geoPoint != null && distanceKm > radiusKm) continue;

        entries.add(
          _VolunteerEntry(id: doc.id, data: data, distanceKm: distanceKm),
        );
      } catch (e) {
        debugPrint('[VolunteerRepository] Bad doc ${doc.id}: $e');
      }
    }

    // Sort by distance
    entries.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    final top = entries.take(_maxResults).toList();

    // Emit both formats
    sosVolunteersNotifier.value = top.map(_toSosFormat).toList();
    nearbyVolunteersNotifier.value = top.map(_toUiFormat).toList();
    loadingNotifier.value = false;
    errorNotifier.value = null;
  }

  // ── SOS dispatch format (consumed by VoiceSOSService.triage) ─────────────
  // Keys: id, name, skills (skill-key strings), distanceKm
  Map<String, dynamic> _toSosFormat(_VolunteerEntry e) {
    final d = e.data;

    // Accept both `skills` (key list) and `skillLabels` — normalise to keys
    final raw = d['skills'] as List?;
    final skills =
        raw?.map((s) => s.toString().toLowerCase().trim()).toList() ??
        <String>[];

    return {
      'id': e.id,
      'name': (d['name'] as String? ?? 'Volunteer').trim(),
      'skills': skills,
      'distanceKm': e.distanceKm,
    };
  }

  // ── UI display format (consumed by HomeScreen NearbyVolunteers panel) ────
  // Keys: name, skills (display labels), distance, level, initials, color,
  //       isOnline, phone
  Map<String, dynamic> _toUiFormat(_VolunteerEntry e) {
    final d = e.data;

    // Prefer skillLabels for display; fall back to prettified skill keys
    final rawLabels = d['skillLabels'] as List?;
    final rawKeys = d['skills'] as List?;
    final List<String> displaySkills;

    if (rawLabels != null && rawLabels.isNotEmpty) {
      displaySkills = rawLabels.map((s) => s.toString()).toList();
    } else if (rawKeys != null && rawKeys.isNotEmpty) {
      displaySkills = rawKeys
          .map((s) => _prettifySkillKey(s.toString()))
          .toList();
    } else {
      displaySkills = [];
    }

    final name = (d['name'] as String? ?? 'Volunteer').trim();
    final initials = d['initials'] as String? ?? _initials(name);

    final distLabel = e.distanceKm < 0.1
        ? '< 100 m'
        : '${e.distanceKm.toStringAsFixed(1)} km';

    return {
      'id': e.id,
      'name': name,
      'skills': displaySkills.take(2).toList(), // HomeScreen shows max 2
      'distance': distLabel,
      'level': (d['level'] as num?)?.toInt() ?? 1,
      'initials': initials,
      'color': (d['color'] as num?)?.toInt() ?? 0xFF4285F4,
      'isOnline': d['isOnline'] as bool? ?? true,
      'phone': d['phone'] as String? ?? '',
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371.0; // Earth radius km
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _deg2rad(double deg) => deg * math.pi / 180;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  static String _prettifySkillKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

// ---------------------------------------------------------------------------
// Internal data holder
// ---------------------------------------------------------------------------

class _VolunteerEntry {
  final String id;
  final Map<String, dynamic> data;
  final double distanceKm;

  const _VolunteerEntry({
    required this.id,
    required this.data,
    required this.distanceKm,
  });
}
