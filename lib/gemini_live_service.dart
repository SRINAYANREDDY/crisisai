// gemini_live_service.dart
// ---------------------------------------------------------------------------
// Feature 2 — Gemini 2.0 Flash Live API  (real-time voice co-responder)
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'consts.dart';
import 'voice_sos_service.dart'; // SOSTriageResult, MatchedVolunteer

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const String _kLiveApiBase =
    'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

const String _kLiveModel = 'models/gemini-2.0-flash-live-001';

const Map<String, dynamic> _kClientAudioConfig = {
  'sample_rate_hertz': 16000,
  'audio_encoding': 'LINEAR16',
  'channel_count': 1,
};

// ---------------------------------------------------------------------------
// Session state enum
// ---------------------------------------------------------------------------

enum LiveSessionState {
  idle,
  connecting,
  active,
  processing,
  error,
  ended,
}

// ---------------------------------------------------------------------------
// Streamed guidance message from Gemini
// ---------------------------------------------------------------------------

class GuidanceMessage {
  final String text;
  final bool isFinal;
  final DateTime timestamp;

  GuidanceMessage({
    required this.text,
    this.isFinal = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// ---------------------------------------------------------------------------
// GeminiLiveService  (singleton)
// ---------------------------------------------------------------------------

class GeminiLiveService {
  GeminiLiveService._();
  static final GeminiLiveService instance = GeminiLiveService._();

  // ── State notifiers ───────────────────────────────────────────────────────
  final ValueNotifier<LiveSessionState> stateNotifier =
      ValueNotifier(LiveSessionState.idle);
  final ValueNotifier<String> liveTranscript = ValueNotifier('');
  final ValueNotifier<String> aiGuidance = ValueNotifier('');
  final ValueNotifier<double> inputLevel = ValueNotifier(0.0);
  final ValueNotifier<bool> isSpeaking = ValueNotifier(false);

  final List<GuidanceMessage> conversationLog = [];

  // ── Internal ──────────────────────────────────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSubscription;

  // record v5 uses AudioRecorder
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSubscription;

  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;
  bool _sessionSetupDone = false;
  final StringBuffer _partialResponse = StringBuffer();
  Timer? _silenceTimer;

  // Whether TTS is currently speaking — used to gate mic resumption
  bool _isSpeakingNow = false;

  Completer<SOSTriageResult>? _triageCompleter;
  List<Map<String, dynamic>> _nearbyVolunteers = [];

  // ── Initialise ────────────────────────────────────────────────────────────

  Future<bool> initialize() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      debugPrint('[Live] Microphone permission denied');
      return false;
    }
    await _initTts();
    return true;
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.85);
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.95);
    _tts.setStartHandler(() {
      isSpeaking.value = true;
      _isSpeakingNow = true;
    });
    _tts.setCompletionHandler(() {
      isSpeaking.value = false;
      _isSpeakingNow = false;
    });
    _tts.setErrorHandler((msg) {
      isSpeaking.value = false;
      _isSpeakingNow = false;
      debugPrint('[Live] TTS error: $msg');
    });
    _ttsReady = true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // START SESSION
  // ─────────────────────────────────────────────────────────────────────────

  Future<SOSTriageResult> startSession({
    required List<Map<String, dynamic>> nearbyVolunteers,
  }) async {
    if (stateNotifier.value != LiveSessionState.idle &&
        stateNotifier.value != LiveSessionState.ended &&
        stateNotifier.value != LiveSessionState.error) {
      throw StateError('Session already active');
    }

    _nearbyVolunteers = nearbyVolunteers;
    _triageCompleter = Completer<SOSTriageResult>();
    conversationLog.clear();
    liveTranscript.value = '';
    aiGuidance.value = '';
    _partialResponse.clear();
    _sessionSetupDone = false;

    stateNotifier.value = LiveSessionState.connecting;

    try {
      await _openWebSocket();
      await _startAudioStream();
      stateNotifier.value = LiveSessionState.active;
    } catch (e) {
      stateNotifier.value = LiveSessionState.error;
      _triageCompleter!.completeError(e);
      rethrow;
    }

    return _triageCompleter!.future;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STOP SESSION
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> stopSession() async {
    if (stateNotifier.value == LiveSessionState.idle) return;

    stateNotifier.value = LiveSessionState.processing;
    _silenceTimer?.cancel();

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    // record v5: isRecording() returns Future<bool>
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    try {
      _channel?.sink.add(jsonEncode({
        'client_content': {
          'turn_complete': true,
        },
      }));
    } catch (_) {}

    await Future.delayed(const Duration(seconds: 2));

    await _wsSubscription?.cancel();
    await _channel?.sink.close();
    _channel = null;

    final fullTranscript = liveTranscript.value;
    final fullGuidance =
        conversationLog.where((m) => m.isFinal).map((m) => m.text).join('\n');

    final result = _buildTriageResult(fullTranscript, fullGuidance);
    stateNotifier.value = LiveSessionState.ended;

    if (_triageCompleter != null && !_triageCompleter!.isCompleted) {
      _triageCompleter!.complete(result);
    }
  }

  Future<void> cancelSession() async {
    _silenceTimer?.cancel();
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    await _wsSubscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    stateNotifier.value = LiveSessionState.idle;

    if (_triageCompleter != null && !_triageCompleter!.isCompleted) {
      _triageCompleter!.completeError(CancelledException());
    }
    await _tts.stop();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WEBSOCKET
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _openWebSocket() async {
    final apiKey = GeminiKeyManager.instance.currentKey;
    final uri = Uri.parse('$_kLiveApiBase?key=$apiKey');

    _channel = WebSocketChannel.connect(uri);

    // web_socket_channel v3: .ready is a Future<void>
    await _channel!.ready;

    _wsSubscription = _channel!.stream.listen(
      _handleServerMessage,
      onError: (Object e) {
        debugPrint('[Live] WS error: $e');
        if (stateNotifier.value == LiveSessionState.active) {
          stateNotifier.value = LiveSessionState.error;
        }
      },
      onDone: () {
        debugPrint('[Live] WS closed');
        if (stateNotifier.value == LiveSessionState.active) {
          stopSession();
        }
      },
    );

    _sendSetup();
  }

  void _sendSetup() {
    final setupMsg = {
      'setup': {
        'model': _kLiveModel,
        'generation_config': {
          'response_modalities': ['TEXT'],
          'temperature': 0.2,
          'max_output_tokens': 200,
        },
        'system_instruction': {
          'parts': [
            {'text': _kSystemPrompt},
          ],
        },
        'input_audio_config': _kClientAudioConfig,
      },
    };
    _channel!.sink.add(jsonEncode(setupMsg));
    debugPrint('[Live] Setup sent');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUDIO STREAMING
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startAudioStream() async {
    // record v5 RecordConfig
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    );

    final audioStream = await _recorder.startStream(config);

    _audioSubscription = audioStream.listen(
      (Uint8List chunk) {
        if (chunk.isEmpty) return;
        // Skip sending audio while TTS is speaking to reduce echo
        if (_isSpeakingNow) return;
        inputLevel.value = _estimateLevel(chunk);
        _sendAudioChunk(chunk);
        _resetSilenceTimer();
      },
      onError: (Object e) => debugPrint('[Live] Audio stream error: $e'),
    );
  }

  void _sendAudioChunk(Uint8List pcmBytes) {
    if (_channel == null) return;
    final b64 = base64Encode(pcmBytes);
    final msg = {
      'realtime_input': {
        'media_chunks': [
          {
            'mime_type': 'audio/pcm;rate=16000',
            'data': b64,
          },
        ],
      },
    };
    _channel!.sink.add(jsonEncode(msg));
  }

  double _estimateLevel(Uint8List bytes) {
    if (bytes.length < 2) return 0.0;
    var sum = 0;
    for (int i = 0; i < bytes.length - 1; i += 2) {
      final sample = bytes[i] | (bytes[i + 1] << 8);
      final signed = sample > 32767 ? sample - 65536 : sample;
      sum += signed.abs();
    }
    final avg = sum / (bytes.length / 2);
    return (avg / 32768).clamp(0.0, 1.0);
  }

  // 45-second max session timer
  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 45), () {
      if (stateNotifier.value == LiveSessionState.active) stopSession();
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SERVER MESSAGE HANDLER
  // ─────────────────────────────────────────────────────────────────────────

  void _handleServerMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;

      // Setup confirmation
      if (msg.containsKey('setupComplete')) {
        _sessionSetupDone = true;
        debugPrint('[Live] Setup complete — streaming audio');
        return;
      }

      // Server content (AI response text)
      if (msg.containsKey('serverContent')) {
        final sc = msg['serverContent'] as Map<String, dynamic>;
        final turnComplete = sc['turnComplete'] as bool? ?? false;

        final modelTurn = sc['modelTurn'] as Map<String, dynamic>?;
        if (modelTurn != null) {
          final parts = modelTurn['parts'] as List? ?? [];
          for (final part in parts) {
            final text =
                (part as Map<String, dynamic>)['text'] as String? ?? '';
            if (text.isNotEmpty) {
              _partialResponse.write(text);
              aiGuidance.value = _partialResponse.toString();
            }
          }
        }

        if (turnComplete) {
          final finalText = _partialResponse.toString().trim();
          if (finalText.isNotEmpty) {
            final guidance = GuidanceMessage(text: finalText, isFinal: true);
            conversationLog.add(guidance);
            _speakGuidance(finalText);
            debugPrint('[Live] AI: $finalText');
          }
          _partialResponse.clear();
        }
        return;
      }

      // Input transcription
      if (msg.containsKey('inputTranscription')) {
        final transcription = (msg['inputTranscription']
                as Map<String, dynamic>)['text'] as String? ??
            '';
        if (transcription.isNotEmpty) {
          liveTranscript.value = transcription;
          debugPrint('[Live] Heard: $transcription');
        }
        return;
      }

      // Error from server
      if (msg.containsKey('error')) {
        final errMsg =
            (msg['error'] as Map<String, dynamic>)['message'] as String? ??
                'Unknown error';
        debugPrint('[Live] Server error: $errMsg');

        if (errMsg.toLowerCase().contains('quota') ||
            errMsg.toLowerCase().contains('rate')) {
          final hasNext = GeminiKeyManager.instance.rotateKey();
          if (hasNext) {
            debugPrint('[Live] Key rotated — reconnecting');
            _reconnect();
          }
        }
        return;
      }
    } catch (e) {
      debugPrint('[Live] Message parse error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TTS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _speakGuidance(String text) async {
    if (!_ttsReady || text.isEmpty) return;

    // In record v5 there is no pause()/resume() on an active stream.
    // Instead we gate sending audio chunks via _isSpeakingNow (set in
    // _startAudioStream's listen callback). TTS start/completion handlers
    // toggle _isSpeakingNow so audio is suppressed while Gemini speaks.
    await _tts.speak(text);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // KEY ROTATION RECONNECT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _reconnect() async {
    await _wsSubscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _sessionSetupDone = false;
    try {
      await _openWebSocket();
    } catch (e) {
      stateNotifier.value = LiveSessionState.error;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD TRIAGE RESULT FROM CONVERSATION
  // ─────────────────────────────────────────────────────────────────────────

  SOSTriageResult _buildTriageResult(
    String transcript,
    String guidance,
  ) {
    final combined = '$transcript $guidance'.toLowerCase();

    String incidentType = 'General Emergency';
    int severity = 3;
    List<String> requiredSkills = ['first_aid', 'rescue'];

    if (_has(combined, ['fire', 'smoke', 'flame', 'burn'])) {
      incidentType = 'Fire';
      severity = 4;
      requiredSkills = ['firefighting', 'rescue', 'first_aid'];
    } else if (_has(combined, ['flood', 'drown', 'water', 'submerge'])) {
      incidentType = 'Flood / Drowning';
      severity = 4;
      requiredSkills = ['flood_rescue', 'cpr', 'first_aid'];
    } else if (_has(
        combined, ['heart', 'cpr', 'unconscious', 'collapse', 'chest'])) {
      incidentType = 'Medical — Cardiac';
      severity = 5;
      requiredSkills = ['cpr', 'medical', 'first_aid'];
    } else if (_has(combined, ['accident', 'crash', 'collision', 'vehicle'])) {
      incidentType = 'Road Accident';
      severity = 4;
      requiredSkills = ['rescue', 'trauma', 'first_aid'];
    } else if (_has(
        combined, ['building', 'collapse', 'rubble', 'structure'])) {
      incidentType = 'Structural Collapse';
      severity = 5;
      requiredSkills = ['search_and_rescue', 'structural', 'first_aid'];
    } else if (_has(
        combined, ['chemical', 'gas', 'hazmat', 'spill', 'toxic'])) {
      incidentType = 'Chemical / HAZMAT';
      severity = 5;
      requiredSkills = ['chemical', 'rescue', 'medical'];
    }

    final lines = guidance
        .split(RegExp(r'[.\n]'))
        .map((l) => l.trim())
        .where((l) => l.length > 10)
        .take(5)
        .toList();

    return SOSTriageResult(
      incidentType: incidentType,
      severity: severity,
      requiredSkills: requiredSkills,
      immediateActions: lines.isNotEmpty
          ? lines
          : ['Follow dispatcher instructions', 'Ensure personal safety'],
      matchedVolunteers: _matchVolunteers(requiredSkills),
      rawTranscription: transcript,
      wasOffline: false,
    );
  }

  List<MatchedVolunteer> _matchVolunteers(List<String> requiredSkills) {
    final result = <MatchedVolunteer>[];
    for (final v in _nearbyVolunteers) {
      final vSkills = List<String>.from(v['skills'] as List? ?? []);
      final matched = vSkills.where((s) => requiredSkills.contains(s)).toList();
      if (matched.isNotEmpty) {
        result.add(MatchedVolunteer(
          id: v['id'] as String? ?? '',
          name: v['name'] as String? ?? 'Volunteer',
          skills: vSkills,
          distanceKm: (v['distanceKm'] as num?)?.toDouble() ?? 0.0,
          matchedSkills: matched,
        ));
      }
    }
    result.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return result.take(5).toList();
  }

  bool _has(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  void dispose() {
    cancelSession();
    _tts.stop();
  }
}

// ---------------------------------------------------------------------------
// System prompt — AI co-responder persona
// ---------------------------------------------------------------------------

const String _kSystemPrompt = '''
You are ARIA — an AI emergency co-responder embedded in CrisisAI, a first-responder volunteer app.

A volunteer in the field is speaking to you in real time while responding to an emergency. Your role is to:
1. Identify the incident type from what you hear.
2. Deliver CONCISE, CALM, ACTIONABLE guidance — short sentences, spoken language (no markdown, no lists).
3. Prioritise life safety. Lead with the most critical action first.
4. If you hear something critical (unconscious person, fire spreading, structural instability), interrupt with an immediate instruction.
5. Confirm you are coordinating backup when relevant: "I am alerting nearby volunteers now."
6. Keep each response under 40 words. You will speak again when the situation updates.

IMPORTANT:
- Speak plainly. You are being converted to audio.
- No bullet points. No headers. No markdown.
- Stay in character as a calm, expert emergency AI dispatcher at all times.
- If you cannot hear clearly, say "Please repeat — connection unclear."
''';

// ---------------------------------------------------------------------------
// Custom exception
// ---------------------------------------------------------------------------

class CancelledException implements Exception {
  @override
  String toString() => 'Session was cancelled by user';
}
