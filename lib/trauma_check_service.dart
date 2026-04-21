// trauma_check_service.dart
// CrisisAI — AI Post-Trauma Mental Health Check Engine
//
// This service handles everything except the UI:
//   • TraumaCheckTrigger  — decides WHEN to trigger a check-in
//   • TraumaCheckSession  — models one 3-question Gemini conversation
//   • TraumaCheckEngine   — calls Gemini to generate questions + analysis
//   • TraumaCheckStore    — persists sessions to SharedPreferences
//   • TraumaRiskLevel     — enum for result classification
//
// Google SDG alignment:
//   SDG 3.4 — Promote mental health and well-being
//   SDG 3.d — Strengthen capacity for health risk management
//
// Integration:
//   1. Add import 'trauma_check_service.dart'; to train.dart
//   2. In _MissionStartScreenState._completeMission(), call:
//        TraumaCheckTrigger.onMissionCompleted(context, missionData);
//   3. The trigger evaluates severity and schedules the check-in.
//   4. No other changes needed.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'train.dart';      // GeminiService
import 'home_screen.dart'; // AppData

// ══════════════════════════════════════════════════════════════════════════════
//  ENUMS & DATA MODELS
// ══════════════════════════════════════════════════════════════════════════════

enum TraumaRiskLevel {
  clear,     // No indicators — volunteer is fine
  monitor,   // Mild stress indicators — suggest rest + check back tomorrow
  support,   // Moderate indicators — recommend talking to someone
  urgent,    // Strong indicators — prompt immediate professional contact
}

extension TraumaRiskLevelExt on TraumaRiskLevel {
  String get label => switch (this) {
        TraumaRiskLevel.clear => 'All Good',
        TraumaRiskLevel.monitor => 'Mild Stress',
        TraumaRiskLevel.support => 'Support Recommended',
        TraumaRiskLevel.urgent => 'Urgent Support',
      };

  String get description => switch (this) {
        TraumaRiskLevel.clear =>
          'You seem to be handling this well. Take care of yourself.',
        TraumaRiskLevel.monitor =>
          'Some stress is normal after a tough mission. Rest, eat, and speak to someone you trust.',
        TraumaRiskLevel.support =>
          'What you experienced was difficult. Speaking to a counsellor can really help.',
        TraumaRiskLevel.urgent =>
          'Your responses suggest you may need immediate support. Please reach out today.',
      };

  // Colour hex values that match AppColors
  int get colorHex => switch (this) {
        TraumaRiskLevel.clear => 0xFF1D9E75,
        TraumaRiskLevel.monitor => 0xFFBA7517,
        TraumaRiskLevel.support => 0xFF1D4ED8,
        TraumaRiskLevel.urgent => 0xFFE24B4A,
      };
}

// Severity of the mission that just completed
enum MissionSeverity { low, medium, high, critical }

class CompletedMissionContext {
  final String missionTitle;
  final String missionType;       // 'fire', 'rescue', 'medical', 'combined'
  final MissionSeverity severity;
  final int durationMinutes;
  final int elapsedSeconds;
  final List<String> stepsCompleted;
  final DateTime completedAt;
  final String volunteerName;
  final int volunteerLevel;

  const CompletedMissionContext({
    required this.missionTitle,
    required this.missionType,
    required this.severity,
    required this.durationMinutes,
    required this.elapsedSeconds,
    required this.stepsCompleted,
    required this.completedAt,
    required this.volunteerName,
    required this.volunteerLevel,
  });

  Map<String, dynamic> toJson() => {
        'missionTitle': missionTitle,
        'missionType': missionType,
        'severity': severity.name,
        'durationMinutes': durationMinutes,
        'elapsedSeconds': elapsedSeconds,
        'stepsCompleted': stepsCompleted,
        'completedAt': completedAt.toIso8601String(),
        'volunteerName': volunteerName,
        'volunteerLevel': volunteerLevel,
      };
}

// One answer in the check-in conversation
class TraumaCheckAnswer {
  final String question;
  final String answer;
  final DateTime answeredAt;

  const TraumaCheckAnswer({
    required this.question,
    required this.answer,
    required this.answeredAt,
  });

  Map<String, dynamic> toJson() => {
        'question': question,
        'answer': answer,
        'answeredAt': answeredAt.toIso8601String(),
      };

  factory TraumaCheckAnswer.fromJson(Map<String, dynamic> j) =>
      TraumaCheckAnswer(
        question: j['question'] as String,
        answer: j['answer'] as String,
        answeredAt: DateTime.parse(j['answeredAt'] as String),
      );
}

// A complete check-in session (persisted to disk)
class TraumaCheckSession {
  final String id;
  final CompletedMissionContext mission;
  final List<TraumaCheckAnswer> answers;
  final TraumaRiskLevel? riskLevel;
  final String? aiSummary;
  final String? aiRecommendation;
  final List<String>? aiNextSteps;
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool isComplete;

  const TraumaCheckSession({
    required this.id,
    required this.mission,
    required this.answers,
    this.riskLevel,
    this.aiSummary,
    this.aiRecommendation,
    this.aiNextSteps,
    required this.startedAt,
    this.completedAt,
    this.isComplete = false,
  });

  TraumaCheckSession copyWith({
    List<TraumaCheckAnswer>? answers,
    TraumaRiskLevel? riskLevel,
    String? aiSummary,
    String? aiRecommendation,
    List<String>? aiNextSteps,
    DateTime? completedAt,
    bool? isComplete,
  }) =>
      TraumaCheckSession(
        id: id,
        mission: mission,
        answers: answers ?? this.answers,
        riskLevel: riskLevel ?? this.riskLevel,
        aiSummary: aiSummary ?? this.aiSummary,
        aiRecommendation: aiRecommendation ?? this.aiRecommendation,
        aiNextSteps: aiNextSteps ?? this.aiNextSteps,
        startedAt: startedAt,
        completedAt: completedAt ?? this.completedAt,
        isComplete: isComplete ?? this.isComplete,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'mission': mission.toJson(),
        'answers': answers.map((a) => a.toJson()).toList(),
        'riskLevel': riskLevel?.name,
        'aiSummary': aiSummary,
        'aiRecommendation': aiRecommendation,
        'aiNextSteps': aiNextSteps,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'isComplete': isComplete,
      };

  factory TraumaCheckSession.fromJson(Map<String, dynamic> j) {
    final mj = j['mission'] as Map<String, dynamic>;
    return TraumaCheckSession(
      id: j['id'] as String,
      mission: CompletedMissionContext(
        missionTitle: mj['missionTitle'] as String,
        missionType: mj['missionType'] as String,
        severity: MissionSeverity.values.firstWhere(
          (e) => e.name == mj['severity'],
          orElse: () => MissionSeverity.medium,
        ),
        durationMinutes: mj['durationMinutes'] as int,
        elapsedSeconds: mj['elapsedSeconds'] as int,
        stepsCompleted: List<String>.from(mj['stepsCompleted'] as List),
        completedAt: DateTime.parse(mj['completedAt'] as String),
        volunteerName: mj['volunteerName'] as String,
        volunteerLevel: mj['volunteerLevel'] as int,
      ),
      answers: (j['answers'] as List)
          .map((a) => TraumaCheckAnswer.fromJson(a as Map<String, dynamic>))
          .toList(),
      riskLevel: j['riskLevel'] != null
          ? TraumaRiskLevel.values.firstWhere(
              (e) => e.name == j['riskLevel'],
              orElse: () => TraumaRiskLevel.clear,
            )
          : null,
      aiSummary: j['aiSummary'] as String?,
      aiRecommendation: j['aiRecommendation'] as String?,
      aiNextSteps: j['aiNextSteps'] != null
          ? List<String>.from(j['aiNextSteps'] as List)
          : null,
      startedAt: DateTime.parse(j['startedAt'] as String),
      completedAt: j['completedAt'] != null
          ? DateTime.parse(j['completedAt'] as String)
          : null,
      isComplete: j['isComplete'] as bool? ?? false,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TRAUMA CHECK ENGINE  — Gemini prompts
// ══════════════════════════════════════════════════════════════════════════════

class TraumaCheckEngine {
  // The 3 questions are generated fresh by Gemini — personalised to the mission.
  // This avoids the "survey" feeling and makes it feel like a real conversation.
  static Future<List<String>> generateQuestions(
    CompletedMissionContext mission,
  ) async {
    final prompt = '''
You are a compassionate mental health support assistant for emergency volunteer responders.

A volunteer just completed a high-severity mission:
- Mission: ${mission.missionTitle}
- Type: ${mission.missionType}
- Duration: ${mission.durationMinutes} minutes
- Volunteer name: ${mission.volunteerName}
- Volunteer level: ${mission.volunteerLevel}
- Steps completed: ${mission.stepsCompleted.join(', ')}

Generate exactly 3 short, warm, conversational check-in questions for this volunteer.
The questions should:
1. Feel like a caring conversation, NOT a clinical survey
2. Be specific to the type of mission (${mission.missionType})
3. Progress from physical/practical (Q1) → emotional (Q2) → support/coping (Q3)
4. Use the volunteer's first name (${mission.volunteerName.split(' ').first})
5. Be open-ended so the volunteer can share as much or as little as they want

Return ONLY a JSON array of 3 strings, nothing else. No preamble, no explanation.
Example format: ["Q1 text", "Q2 text", "Q3 text"]
''';

    try {
      final raw = await GeminiService.generateContent(prompt, 'basic');
      // Strip any markdown code fences if present
      final cleaned = raw
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final decoded = jsonDecode(cleaned) as List;
      final questions = decoded.cast<String>();
      if (questions.length == 3) return questions;
    } catch (e) {
      debugPrint('[TraumaCheckEngine] generateQuestions error: $e');
    }
    // Fallback questions if Gemini fails
    return _fallbackQuestions(mission);
  }

  static List<String> _fallbackQuestions(CompletedMissionContext mission) {
    final name = mission.volunteerName.split(' ').first;
    return switch (mission.missionType) {
      'fire' => [
          '$name, how are you feeling physically right now — any smoke inhalation, soreness, or fatigue?',
          'Fire scenes can be intense. Is there anything from today that\'s staying in your mind or that you keep replaying?',
          'What\'s one thing you\'re going to do to take care of yourself in the next few hours?',
        ],
      'rescue' || 'medical' => [
          '$name, how\'s your body doing — are you eating, hydrated, and resting okay?',
          'Sometimes after helping people in crisis we carry some of their weight. How are you feeling emotionally right now?',
          'Is there someone you\'d feel comfortable talking to about today — a family member, friend, or colleague?',
        ],
      'combined' => [
          '$name, that was a complex multi-agency response. How are you feeling physically and mentally right now?',
          'In big coordinated operations there\'s often a lot of pressure and difficult moments. Is anything from today sitting heavily with you?',
          'What support do you have around you tonight — someone to talk to, or a routine that helps you decompress?',
        ],
      _ => [
          '$name, how are you feeling right now after completing the mission?',
          'Is there anything about what you experienced today that is staying with you?',
          'What\'s your plan to rest and decompress after this?',
        ],
    };
  }

  // After all 3 answers, Gemini analyses for risk and writes a personalised summary.
  static Future<TraumaAnalysisResult> analyseAnswers({
    required CompletedMissionContext mission,
    required List<TraumaCheckAnswer> answers,
  }) async {
    final qa = answers
        .asMap()
        .entries
        .map((e) => 'Q${e.key + 1}: ${e.value.question}\nA${e.key + 1}: ${e.value.answer}')
        .join('\n\n');

    final prompt = '''
You are a clinical mental health screening assistant for emergency first responders.

CONTEXT:
Volunteer: ${mission.volunteerName}, Level ${mission.volunteerLevel}
Mission completed: ${mission.missionTitle} (${mission.missionType}, severity: ${mission.severity.name})
Duration: ${mission.durationMinutes} min

CHECK-IN CONVERSATION:
$qa

Analyse this check-in for signs of acute stress response or post-traumatic indicators.
Watch for: intrusive thoughts, hyperarousal, emotional numbing, dissociation, physical complaints, social withdrawal, substance use mentions, hopelessness, or self-harm indicators.

Return a JSON object with EXACTLY these fields:
{
  "riskLevel": "clear" | "monitor" | "support" | "urgent",
  "riskRationale": "1 sentence internal reasoning (not shown to user)",
  "summary": "2–3 warm sentences summarising what the volunteer expressed, written directly to them in second person",
  "recommendation": "1–2 sentences of specific, actionable guidance appropriate to the risk level",
  "nextSteps": ["step1", "step2", "step3"],
  "flaggedPhrases": ["any phrase that raised concern, or empty array"],
  "requiresImmediateEscalation": true | false
}

IMPORTANT:
- riskLevel "urgent" ONLY if there are clear signs of crisis (self-harm, dissociation, complete emotional breakdown)
- Be compassionate and non-clinical in summary and recommendation — this is a conversation, not a medical report
- nextSteps should be practical and achievable today/tomorrow
- Return ONLY valid JSON, no markdown, no preamble
''';

    try {
      final raw = await GeminiService.generateContent(prompt, 'basic');
      final cleaned = raw
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;

      final riskStr = decoded['riskLevel'] as String? ?? 'clear';
      final risk = TraumaRiskLevel.values.firstWhere(
        (e) => e.name == riskStr,
        orElse: () => TraumaRiskLevel.clear,
      );

      return TraumaAnalysisResult(
        riskLevel: risk,
        summary: decoded['summary'] as String? ?? '',
        recommendation: decoded['recommendation'] as String? ?? '',
        nextSteps: decoded['nextSteps'] != null
            ? List<String>.from(decoded['nextSteps'] as List)
            : [],
        flaggedPhrases: decoded['flaggedPhrases'] != null
            ? List<String>.from(decoded['flaggedPhrases'] as List)
            : [],
        requiresImmediateEscalation:
            decoded['requiresImmediateEscalation'] as bool? ?? false,
        riskRationale: decoded['riskRationale'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('[TraumaCheckEngine] analyseAnswers error: $e');
      return _fallbackAnalysis(answers);
    }
  }

  static TraumaAnalysisResult _fallbackAnalysis(
    List<TraumaCheckAnswer> answers,
  ) {
    // Simple keyword scan as fallback
    final allAnswers =
        answers.map((a) => a.answer.toLowerCase()).join(' ');
    final urgentKeywords = [
      'suicide',
      'kill myself',
      'can\'t go on',
      'end it',
      'hurt myself',
    ];
    final supportKeywords = [
      'nightmare',
      'can\'t sleep',
      'flashback',
      'shaking',
      'crying',
      'scared',
      'alone',
      'nobody',
      'hopeless',
    ];
    final monitorKeywords = [
      'tired',
      'exhausted',
      'sad',
      'difficult',
      'hard',
      'stressed',
      'worried',
    ];

    TraumaRiskLevel risk = TraumaRiskLevel.clear;
    if (urgentKeywords.any((k) => allAnswers.contains(k))) {
      risk = TraumaRiskLevel.urgent;
    } else if (supportKeywords.any((k) => allAnswers.contains(k))) {
      risk = TraumaRiskLevel.support;
    } else if (monitorKeywords.any((k) => allAnswers.contains(k))) {
      risk = TraumaRiskLevel.monitor;
    }

    return TraumaAnalysisResult(
      riskLevel: risk,
      summary:
          'Thank you for taking the time to check in. What you shared matters.',
      recommendation: risk == TraumaRiskLevel.clear
          ? 'You seem to be in a good place. Keep resting and stay connected with people you trust.'
          : 'It sounds like today was tough. Please reach out to someone you trust, or use the resources below.',
      nextSteps: [
        'Get a full night of sleep tonight',
        'Eat a proper meal and stay hydrated',
        'Talk to a friend, family member, or colleague about your day',
      ],
      flaggedPhrases: [],
      requiresImmediateEscalation: risk == TraumaRiskLevel.urgent,
      riskRationale: 'Fallback keyword analysis',
    );
  }
}

class TraumaAnalysisResult {
  final TraumaRiskLevel riskLevel;
  final String summary;
  final String recommendation;
  final List<String> nextSteps;
  final List<String> flaggedPhrases;
  final bool requiresImmediateEscalation;
  final String riskRationale; // internal, not shown to user

  const TraumaAnalysisResult({
    required this.riskLevel,
    required this.summary,
    required this.recommendation,
    required this.nextSteps,
    required this.flaggedPhrases,
    required this.requiresImmediateEscalation,
    required this.riskRationale,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
//  TRAUMA CHECK STORE  — persistence
// ══════════════════════════════════════════════════════════════════════════════

class TraumaCheckStore {
  static const _prefix = 'trauma_session_';
  static const _indexKey = 'trauma_session_index';

  static Future<void> saveSession(TraumaCheckSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix${session.id}',
      jsonEncode(session.toJson()),
    );
    // Update index
    final index = prefs.getStringList(_indexKey) ?? [];
    if (!index.contains(session.id)) {
      index.insert(0, session.id);
      await prefs.setStringList(_indexKey, index);
    }
  }

  static Future<TraumaCheckSession?> loadSession(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$id');
    if (raw == null) return null;
    try {
      return TraumaCheckSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('[TraumaCheckStore] loadSession error: $e');
      return null;
    }
  }

  static Future<List<TraumaCheckSession>> loadAllSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_indexKey) ?? [];
    final sessions = <TraumaCheckSession>[];
    for (final id in index) {
      final s = await loadSession(id);
      if (s != null) sessions.add(s);
    }
    return sessions;
  }

  static Future<List<TraumaCheckSession>> loadCompletedSessions() async {
    final all = await loadAllSessions();
    return all.where((s) => s.isComplete).toList();
  }

  static Future<void> deleteSession(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
    final index = prefs.getStringList(_indexKey) ?? [];
    index.remove(id);
    await prefs.setStringList(_indexKey, index);
  }

  /// Was there already a check-in for a mission with this title today?
  static Future<bool> hasCheckinTodayFor(String missionTitle) async {
    final today = DateTime.now();
    final sessions = await loadAllSessions();
    return sessions.any((s) =>
        s.mission.missionTitle == missionTitle &&
        s.startedAt.year == today.year &&
        s.startedAt.month == today.month &&
        s.startedAt.day == today.day);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TRAUMA CHECK TRIGGER
//  This is the single integration point — call it from _completeMission().
// ══════════════════════════════════════════════════════════════════════════════

class TraumaCheckTrigger {
  /// Maps a drill's blockType + title to a severity level.
  static MissionSeverity _classifySeverity(
    String blockType,
    String title,
    int durationMinutes,
  ) {
    final t = title.toLowerCase();
    // Critical missions
    if (t.contains('cardiac') ||
        t.contains('collapse') ||
        t.contains('mass casualty') ||
        t.contains('earthquake') ||
        t.contains('tsunami') ||
        t.contains('chemical') ||
        t.contains('explosion') ||
        t.contains('burning vehicle') ||
        t.contains('smoke-filled')) {
      return MissionSeverity.critical;
    }
    // High severity
    if (blockType == 'combined' ||
        t.contains('fire') ||
        t.contains('flood') ||
        t.contains('rescue') ||
        t.contains('victim') ||
        t.contains('casualty') ||
        durationMinutes >= 60) {
      return MissionSeverity.high;
    }
    // Medium
    if (blockType == 'rescue' ||
        blockType == 'medical' ||
        durationMinutes >= 30) {
      return MissionSeverity.medium;
    }
    return MissionSeverity.low;
  }

  /// Call this from _MissionStartScreenState._completeMission()
  /// It evaluates severity and launches the check-in sheet when appropriate.
  static Future<void> onMissionCompleted(
    dynamic context, // BuildContext — dynamic to avoid circular import
    DrillScenario drill,
    String blockType,
    int elapsedSeconds,
  ) async {
    final severity = _classifySeverity(
      blockType,
      drill.title,
      drill.durationMin,
    );

    // Only trigger for medium, high, and critical severity
    if (severity == MissionSeverity.low) return;

    // Don't double-trigger for the same mission today
    final alreadyDone =
        await TraumaCheckStore.hasCheckinTodayFor(drill.title);
    if (alreadyDone) return;

    final volunteerName =
        AppData.volunteerProfile['name'] as String? ?? 'Volunteer';
    final volunteerLevel =
        AppData.volunteerProfile['level'] as int? ?? 1;

    final missionContext = CompletedMissionContext(
      missionTitle: drill.title,
      missionType: blockType,
      severity: severity,
      durationMinutes: drill.durationMin,
      elapsedSeconds: elapsedSeconds,
      stepsCompleted: drill.steps,
      completedAt: DateTime.now(),
      volunteerName: volunteerName,
      volunteerLevel: volunteerLevel,
    );

    // Delay slightly so the mission completion UI settles first
    await Future.delayed(const Duration(milliseconds: 1500));

    // Show the check-in sheet — context must still be mounted
    // We use a navigator key approach so this file doesn't need BuildContext
    TraumaCheckPending.set(missionContext);
  }
}

// Simple pending-check singleton so the screen can poll/react
class TraumaCheckPending {
  static CompletedMissionContext? _pending;
  static final List<VoidCallback> _listeners = [];

  static void set(CompletedMissionContext ctx) {
    _pending = ctx;
    for (final l in _listeners) {
      l();
    }
  }

  static CompletedMissionContext? consume() {
    final p = _pending;
    _pending = null;
    return p;
  }

  static bool get hasPending => _pending != null;

  static void addListener(VoidCallback l) => _listeners.add(l);
  static void removeListener(VoidCallback l) => _listeners.remove(l);
}
