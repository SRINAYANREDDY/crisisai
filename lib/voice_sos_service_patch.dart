// voice_sos_service.dart  (UPDATED)
// ---------------------------------------------------------------------------
// Feature 1 integration patch — after triage, writes an `sos_events` doc to
// Firestore so the Cloud Function picks it up and fires FCM notifications to
// matched volunteers.
//
// ADD this method to VoiceSOSService (or call it right after triage() returns
// in your voice_sos_screen.dart):
//
//   final result = await VoiceSOSService.instance.triage(transcript, vols);
//   await VoiceSOSService.instance.publishSOSEvent(result, volunteerIds);
//
// The Cloud Function in functions/index.js listens to sos_events/{sosId}
// and sends FCM to every uid in matched_volunteer_ids[].
// ---------------------------------------------------------------------------

// ── PASTE THIS IMPORT AT THE TOP OF voice_sos_service.dart ──────────────────
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'location_service.dart';

// ── PASTE THIS METHOD INSIDE VoiceSOSService class ───────────────────────────

/*
  // Writes an `sos_events` Firestore doc.
  // The Cloud Function in functions/index.js picks this up and
  // sends FCM dispatch notifications to matched volunteers.
  Future<String?> publishSOSEvent(
    SOSTriageResult result,
    List<String> matchedVolunteerUids,
  ) async {
    try {
      final db   = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;
      final pos  = LocationService.instance.position;

      final doc = await db.collection('sos_events').add({
        'incident_type':         result.incidentType,
        'severity':              result.severity,
        'severity_label':        result.severityLabel,
        'required_skills':       result.requiredSkills,
        'immediate_actions':     result.immediateActions,
        'raw_transcription':     result.rawTranscription,
        'location_text':         LocationService.instance.address,
        'location_geopoint':     pos != null
            ? GeoPoint(pos.latitude, pos.longitude)
            : null,
        'reporter_uid':          auth.currentUser?.uid,
        'matched_volunteer_ids': matchedVolunteerUids,
        'responses':             {},
        'created_at':            FieldValue.serverTimestamp(),
        'was_offline':           result.wasOffline,
      });

      debugPrint('[VoiceSOS] SOS event published: ${doc.id}');
      return doc.id;
    } catch (e) {
      debugPrint('[VoiceSOS] Failed to publish SOS event: $e');
      return null;
    }
  }
*/

// ---------------------------------------------------------------------------
// HOW TO WIRE IT UP IN voice_sos_screen.dart
// ---------------------------------------------------------------------------
//
// In your existing _onTriageComplete (or wherever you handle the result):
//
//   // 1. Run triage as normal
//   final result = await VoiceSOSService.instance.triage(
//     transcript,
//     VolunteerRepository.instance.sosVolunteersNotifier.value,
//   );
//
//   // 2. Extract UIDs from matched volunteers
//   final uids = result.matchedVolunteers.map((v) => v.id).toList();
//
//   // 3. Publish SOS event → triggers Cloud Function → FCM notifications
//   final sosId = await VoiceSOSService.instance.publishSOSEvent(result, uids);
//
//   // 4. Navigate to result screen as before
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => SOSResultScreen(result: result, sosId: sosId),
//   ));
//
// ---------------------------------------------------------------------------
// HOW TO WIRE IT UP IN main.dart
// ---------------------------------------------------------------------------
//
// In your main() function, after Firebase.initializeApp:
//
//   void main() async {
//     WidgetsFlutterBinding.ensureInitialized();
//     await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
//
//     // NEW: initialize FCM service
//     await FCMDispatchService.instance.initialize();
//
//     // NEW: start volunteer feed
//     VolunteerRepository.instance.startListening();
//
//     runApp(const CrisisAIApp());
//   }
//
// In your top-level widget (MaterialApp builder or root Scaffold):
//
//   builder: (context, child) => DispatchNotificationOverlay(child: child),
//
// ---------------------------------------------------------------------------
// pubspec.yaml additions summary (BOTH features)
// ---------------------------------------------------------------------------
//
// dependencies:
//   # Feature 1 — FCM
//   firebase_messaging: ^15.0.0
//   flutter_local_notifications: ^17.0.0
//
//   # Feature 2 — Gemini Live
//   web_socket_channel: ^3.0.0
//   record: ^5.1.0
//   flutter_tts: ^4.0.0
//   permission_handler: ^11.0.0   # if not already present
//
// ---------------------------------------------------------------------------
