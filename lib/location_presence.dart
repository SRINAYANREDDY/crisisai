// location_presence.dart
// ---------------------------------------------------------------------------
// Writes the current volunteer's live location and online/offline status to
// their Firestore document.
//
// Call `PresenceService.instance.goOnline()` after login.
// Call `PresenceService.instance.goOffline()` on logout / app background.
//
// Integrates with LocationService so a single permission flow powers both
// the home screen display and the Firestore presence record.
// ---------------------------------------------------------------------------

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'location_service.dart';

class PresenceService {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Call on successful login / app foreground ────────────────────────────
  Future<void> goOnline() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // Ensure location is ready
    if (!LocationService.instance.isReady) {
      await LocationService.instance.initialize();
    }

    final pos = LocationService.instance.position;

    final Map<String, dynamic> update = {
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    };

    if (pos != null) {
      update['location'] = GeoPoint(pos.latitude, pos.longitude);
    }

    try {
      await _db.collection('volunteers').doc(uid).update(update);
      debugPrint(
        '[Presence] ✅ Online — location: ${pos?.latitude}, ${pos?.longitude}',
      );
    } catch (e) {
      // Doc might not exist yet (first login before Firestore write completed)
      try {
        await _db
            .collection('volunteers')
            .doc(uid)
            .set(update, SetOptions(merge: true));
      } catch (e2) {
        debugPrint('[Presence] Failed to set online: $e2');
      }
    }

    // Also refresh location listener so any subsequent GPS update writes back
    LocationService.instance.addressNotifier.addListener(_onLocationUpdate);
  }

  // ── Call on logout / app going to background ─────────────────────────────
  Future<void> goOffline() async {
    LocationService.instance.addressNotifier.removeListener(_onLocationUpdate);

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _db.collection('volunteers').doc(uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
      debugPrint('[Presence] ✅ Offline');
    } catch (e) {
      debugPrint('[Presence] Failed to set offline: $e');
    }
  }

  // ── Refresh location in Firestore when GPS updates ───────────────────────
  Future<void> _onLocationUpdate() async {
    final uid = _auth.currentUser?.uid;
    final pos = LocationService.instance.position;
    if (uid == null || pos == null) return;

    try {
      await _db.collection('volunteers').doc(uid).update({
        'location': GeoPoint(pos.latitude, pos.longitude),
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Presence] Location update failed: $e');
    }
  }
}
