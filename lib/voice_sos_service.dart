// lib/voice_sos_service.dart
// Feature 3 — Voice SOS with real-time Gemini dispatch

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:http/http.dart' as http;

import 'consts.dart'; // GeminiKeyManager
import 'offline_ai_service.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'location_service.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class SOSTriageResult {
  final String incidentType;
  final int severity;
  final List<String> requiredSkills;
  final List<String> immediateActions;
  final List<MatchedVolunteer> matchedVolunteers;
  final bool wasOffline;
  final String rawTranscription;

  const SOSTriageResult({
    required this.incidentType,
    required this.severity,
    required this.requiredSkills,
    required this.immediateActions,
    required this.matchedVolunteers,
    required this.rawTranscription,
    this.wasOffline = false,
  });

  String get severityLabel {
    switch (severity) {
      case 1:
        return 'Minor';
      case 2:
        return 'Low';
      case 3:
        return 'Moderate';
      case 4:
        return 'High';
      case 5:
        return 'Critical';
      default:
        return 'Unknown';
    }
  }

  Color get severityColor {
    switch (severity) {
      case 1:
      case 2:
        return const Color(0xFF1D9E75);
      case 3:
        return const Color(0xFFBA7517);
      case 4:
      case 5:
        return const Color(0xFFE24B4A);
      default:
        return const Color(0xFF6B6B6B);
    }
  }
}

class MatchedVolunteer {
  final String id;
  final String name;
  final List<String> skills;
  final double distanceKm;
  final List<String> matchedSkills;

  const MatchedVolunteer({
    required this.id,
    required this.name,
    required this.skills,
    required this.distanceKm,
    required this.matchedSkills,
  });
}

// ---------------------------------------------------------------------------
// Internal exception for quota signalling
// ---------------------------------------------------------------------------
class _QuotaExceededException implements Exception {
  final String message;
  const _QuotaExceededException(this.message);
  @override
  String toString() => '_QuotaExceededException: $message';
}

// ---------------------------------------------------------------------------
// VoiceSOSService  (singleton)
// ---------------------------------------------------------------------------

class VoiceSOSService {
  VoiceSOSService._();
  static final VoiceSOSService instance = VoiceSOSService._();

  static const String _geminiModel = 'gemini-2.0-flash';

  SpeechToText _stt = SpeechToText();
  bool _sttReady = false;

  final ValueNotifier<bool> isRecording = ValueNotifier(false);
  final ValueNotifier<String> liveTranscript = ValueNotifier('');
  final ValueNotifier<double> soundLevel = ValueNotifier(0.0);

  // -------------------------------------------------------------------------
  // Initialise
  // -------------------------------------------------------------------------

  Future<bool> initialize() async {
    if (_sttReady) return true;
    _sttReady = await _stt.initialize(
      onError: (e) => debugPrint('[VoiceSOS] STT error: $e'),
      onStatus: (s) => debugPrint('[VoiceSOS] STT status: $s'),
    );
    return _sttReady;
  }

  bool get available => _sttReady;

  // -------------------------------------------------------------------------
  // Recording
  // -------------------------------------------------------------------------

  Future<void> startRecording() async {
    if (!_sttReady) {
      final ok = await initialize();
      if (!ok) return;
    }
    liveTranscript.value = '';
    soundLevel.value = 0.0;
    isRecording.value = true;

    await _stt.listen(
      onResult: (result) {
        liveTranscript.value = result.recognizedWords;
      },
      onSoundLevelChange: (level) {
        soundLevel.value = ((level + 2) / 12).clamp(0.0, 1.0);
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      localeId: 'en_IN',
      cancelOnError: false,
      listenMode: ListenMode.confirmation,
    );
  }

  Future<String> stopRecording() async {
    await _stt.stop();
    isRecording.value = false;
    soundLevel.value = 0.0;
    return liveTranscript.value.trim();
  }

  Future<void> cancelRecording() async {
    await _stt.cancel();
    isRecording.value = false;
    liveTranscript.value = '';
    soundLevel.value = 0.0;
  }

  // -------------------------------------------------------------------------
  // Triage pipeline
  // -------------------------------------------------------------------------

  Future<SOSTriageResult> triage(
    String transcription,
    List<Map<String, dynamic>> nearbyVolunteers,
  ) async {
    final online = await NetworkChecker.check();

    Map<String, dynamic> parsed;
    bool wasOffline = false;

    if (online) {
      try {
        parsed = await _callGeminiWithRotation(transcription);
      } catch (e) {
        debugPrint('[VoiceSOS] Gemini failed, using offline: $e');
        parsed = _keywordHeuristic(transcription);
        wasOffline = true;
      }
    } else {
      parsed = _keywordHeuristic(transcription);
      wasOffline = true;
    }

    final requiredSkills = List<String>.from(
      parsed['required_skills'] as List? ?? [],
    );

    return SOSTriageResult(
      incidentType: parsed['incident_type'] as String? ?? 'General Emergency',
      severity: (parsed['severity'] as num?)?.toInt().clamp(1, 5) ?? 3,
      requiredSkills: requiredSkills,
      immediateActions: List<String>.from(
        parsed['immediate_actions'] as List? ?? [],
      ),
      matchedVolunteers: _matchVolunteers(nearbyVolunteers, requiredSkills),
      rawTranscription: transcription,
      wasOffline: wasOffline,
    );
  }

  // -------------------------------------------------------------------------
  // Gemini with automatic key rotation
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> _callGeminiWithRotation(
    String transcription,
  ) async {
    final manager = GeminiKeyManager.instance;
    final totalKeys = manager.totalKeys;

    for (int attempt = 0; attempt < totalKeys; attempt++) {
      try {
        return await _callGemini(transcription);
      } on _QuotaExceededException catch (e) {
        debugPrint(
          '[VoiceSOS] Key #${manager.currentIndex} quota exceeded — rotating. ($e)',
        );
        final hasNext = manager.rotateKey();
        if (!hasNext) {
          debugPrint('[VoiceSOS] All Gemini keys exhausted.');
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    throw Exception('All Gemini API keys exhausted for VoiceSOS.');
  }

  // -------------------------------------------------------------------------
  // Gemini call (single attempt, throws _QuotaExceededException on 429/503)
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> _callGemini(String transcription) async {
    const systemPrompt = '''
You are an emergency dispatch AI integrated into a first-responder app.
A volunteer has described an incident via voice. Your job is to classify it and help dispatch the right people.

Respond ONLY with a single valid JSON object — no markdown, no code fences, no explanation.

JSON schema:
{
  "incident_type": "string (e.g. Fire, Flood, Medical, Road Accident, Structural Collapse, Chemical Spill, Drowning, Violence, Missing Person, General Emergency)",
  "severity": integer 1-5 (1=minor, 5=critical/life-threatening),
  "required_skills": ["array of skill strings from: first_aid, cpr, trauma, firefighting, flood_rescue, medical, rescue, chemical, structural, search_and_rescue, counselling, navigation, communication"],
  "immediate_actions": ["array of 3-5 short imperative action strings for responders on scene"]
}
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': '$systemPrompt\n\nVoice description: "$transcription"'},
          ],
        },
      ],
      'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 512},
    });

    final geminiUrl = GeminiKeyManager.instance.endpoint(_geminiModel);

    final response = await http
        .post(
          Uri.parse(geminiUrl),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 15));

    // 429 = quota / rate limit → rotate key
    if (response.statusCode == 429 || response.statusCode == 503) {
      throw _QuotaExceededException('HTTP ${response.statusCode}');
    }

    if (response.statusCode != 200) {
      throw Exception('Gemini HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    // Gemini sometimes embeds quota errors inside a 200 response body
    final errorMsg =
        (decoded['error']?['message'] as String? ?? '').toLowerCase();
    if (errorMsg.contains('quota') || errorMsg.contains('rate')) {
      throw _QuotaExceededException(errorMsg);
    }

    final text = (decoded['candidates'] as List?)
            ?.firstOrNull?['content']?['parts']
            ?.firstOrNull?['text'] as String? ??
        '';

    final cleaned = text.replaceAll(RegExp(r'```json|```'), '').trim();
    return jsonDecode(cleaned) as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Offline / keyword heuristic triage
  // -------------------------------------------------------------------------

  Map<String, dynamic> _keywordHeuristic(String text) {
    final t = text.toLowerCase();

    if (_has(t, ['fire', 'smoke', 'burn', 'flame', 'blaze'])) {
      return {
        'incident_type': 'Fire',
        'severity': 4,
        'required_skills': ['firefighting', 'rescue', 'first_aid'],
        'immediate_actions': [
          'Evacuate the area immediately',
          'Do not use elevators',
          'Call fire department',
          'Account for all personnel',
          'Do not re-enter building',
        ],
      };
    }
    if (_has(t, ['flood', 'water', 'drown', 'submerge', 'river'])) {
      return {
        'incident_type': 'Flood / Drowning',
        'severity': 4,
        'required_skills': ['flood_rescue', 'cpr', 'first_aid'],
        'immediate_actions': [
          'Move to highest available ground',
          'Do not walk through flowing water',
          'Throw a rope or flotation device',
          'Begin CPR if victim is unresponsive',
          'Alert emergency services',
        ],
      };
    }
    if (_has(t, [
      'heart',
      'chest',
      'breathe',
      'collapse',
      'unconscious',
      'faint',
    ])) {
      return {
        'incident_type': 'Medical — Cardiac / Respiratory',
        'severity': 5,
        'required_skills': ['cpr', 'medical', 'first_aid'],
        'immediate_actions': [
          'Call ambulance immediately',
          'Begin CPR if no pulse detected',
          'Use AED if available',
          'Keep victim still and calm',
          'Do not give food or water',
        ],
      };
    }
    if (_has(t, [
      'accident',
      'crash',
      'collision',
      'vehicle',
      'car',
      'truck',
    ])) {
      return {
        'incident_type': 'Road Accident',
        'severity': 4,
        'required_skills': ['rescue', 'trauma', 'first_aid'],
        'immediate_actions': [
          'Secure the scene with warning triangles',
          'Do not move critically injured persons',
          'Control visible bleeding with pressure',
          'Call emergency services with location',
          'Keep bystanders back',
        ],
      };
    }
    if (_has(t, [
      'building',
      'collapse',
      'structure',
      'wall',
      'roof',
      'rubble',
    ])) {
      return {
        'incident_type': 'Structural Collapse',
        'severity': 5,
        'required_skills': ['search_and_rescue', 'structural', 'first_aid'],
        'immediate_actions': [
          'Do not enter unstable structure',
          'Call for trapped persons verbally',
          'Mark entry and exit points',
          'Await heavy rescue team',
          'Treat accessible casualties outside',
        ],
      };
    }
    if (_has(t, ['chemical', 'gas', 'leak', 'spill', 'hazmat', 'toxic'])) {
      return {
        'incident_type': 'Chemical / HAZMAT',
        'severity': 5,
        'required_skills': ['chemical', 'rescue', 'medical'],
        'immediate_actions': [
          'Evacuate upwind immediately',
          'Do not touch spilled substance',
          'Isolate area 100m radius',
          'Remove contaminated clothing',
          'Contact HAZMAT team',
        ],
      };
    }

    return {
      'incident_type': 'General Emergency',
      'severity': 3,
      'required_skills': ['first_aid', 'rescue'],
      'immediate_actions': [
        'Ensure your own safety first',
        'Call emergency services',
        'Keep victim calm and still',
        'Do not leave victim alone',
        'Follow dispatcher instructions',
      ],
    };
  }

  bool _has(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  // -------------------------------------------------------------------------
  // Publish SOS event to Firestore → triggers Cloud Function → FCM dispatch
  // -------------------------------------------------------------------------

  Future<String?> publishSOSEvent(
    SOSTriageResult result,
    List<String> matchedVolunteerUids,
  ) async {
    try {
      final db = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;
      final pos = LocationService.instance.position;

      final doc = await db.collection('sos_events').add({
        'incident_type': result.incidentType,
        'severity': result.severity,
        'severity_label': result.severityLabel,
        'required_skills': result.requiredSkills,
        'immediate_actions': result.immediateActions,
        'raw_transcription': result.rawTranscription,
        'location_text': LocationService.instance.address,
        'location_geopoint':
            pos != null ? GeoPoint(pos.latitude, pos.longitude) : null,
        'reporter_uid': auth.currentUser?.uid,
        'matched_volunteer_ids': matchedVolunteerUids,
        'responses': {},
        'created_at': FieldValue.serverTimestamp(),
        'was_offline': result.wasOffline,
      });

      debugPrint('[VoiceSOS] SOS event published: ${doc.id}');
      return doc.id;
    } catch (e) {
      debugPrint('[VoiceSOS] Failed to publish SOS event: $e');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Volunteer matching
  // -------------------------------------------------------------------------

  List<MatchedVolunteer> _matchVolunteers(
    List<Map<String, dynamic>> volunteers,
    List<String> requiredSkills,
  ) {
    final List<MatchedVolunteer> result = [];

    for (final v in volunteers) {
      final vSkills = List<String>.from(v['skills'] as List? ?? []);
      final matched = vSkills.where((s) => requiredSkills.contains(s)).toList();
      if (matched.isNotEmpty) {
        result.add(
          MatchedVolunteer(
            id: v['id'] as String? ?? '',
            name: v['name'] as String? ?? 'Volunteer',
            skills: vSkills,
            distanceKm: (v['distanceKm'] as num?)?.toDouble() ?? 0.0,
            matchedSkills: matched,
          ),
        );
      }
    }

    result.sort((a, b) {
      final d = a.distanceKm.compareTo(b.distanceKm);
      if (d != 0) return d;
      return b.matchedSkills.length.compareTo(a.matchedSkills.length);
    });

    return result.take(5).toList();
  }
}
