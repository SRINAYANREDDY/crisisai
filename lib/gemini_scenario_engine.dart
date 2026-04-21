// gemini_scenario_engine.dart
// Dynamic Gemini-powered training scenario engine.
// Replaces hardcoded training blocks with AI-generated content that adapts to:
//   • The volunteer's current location (city, district, state)
//   • The current season / disaster risk calendar (Tamil Nadu context)
//   • The volunteer's XP level and skill set
//   • The block type (medical, fire, rescue, puzzle, etc.)
//
// Usage:
//   final engine = ScenarioEngine.instance;
//   await engine.init(volunteerProfile, locationService);
//
//   // Generate a scenario for a training block:
//   final scenario = await engine.generateScenario(blockType: 'medical');
//
//   // Generate a dynamic puzzle question:
//   final puzzle = await engine.generatePuzzleQuestion(category: 'flood');
//
//   // Generate a mission debrief after completion:
//   final debrief = await engine.generateDebrief(missionTitle, score, durationMin);

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'consts.dart'; // GeminiKeyManager
import 'location_service.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

/// A fully AI-generated training scenario.
class GeneratedScenario {
  final String title;
  final String department;
  final String location; // Real Tamil Nadu / India location
  final String authorisedPerson;
  final String objective;
  final String missionBrief;
  final List<String> steps;
  final int estimatedDurationMin;
  final int xpReward;
  final String disasterType;
  final String difficulty; // 'beginner' | 'intermediate' | 'advanced'
  final String season; // Season this scenario is relevant to
  final bool isAiGenerated;

  const GeneratedScenario({
    required this.title,
    required this.department,
    required this.location,
    required this.authorisedPerson,
    required this.objective,
    required this.missionBrief,
    required this.steps,
    required this.estimatedDurationMin,
    required this.xpReward,
    required this.disasterType,
    required this.difficulty,
    required this.season,
    this.isAiGenerated = true,
  });

  factory GeneratedScenario.fromJson(Map<String, dynamic> json) {
    return GeneratedScenario(
      title: json['title'] as String? ?? 'Emergency Response Mission',
      department: json['department'] as String? ?? 'NDRF',
      location: json['location'] as String? ?? 'Chennai, Tamil Nadu',
      authorisedPerson:
          json['authorised_person'] as String? ?? 'Training Officer',
      objective:
          json['objective'] as String? ?? 'Complete the assigned rescue task.',
      missionBrief: json['mission_brief'] as String? ?? '',
      steps: List<String>.from(json['steps'] as List? ?? []),
      estimatedDurationMin: (json['duration_min'] as num?)?.toInt() ?? 45,
      xpReward: (json['xp_reward'] as num?)?.toInt() ?? 150,
      disasterType: json['disaster_type'] as String? ?? 'General Emergency',
      difficulty: json['difficulty'] as String? ?? 'intermediate',
      season: json['season'] as String? ?? 'All seasons',
      isAiGenerated: true,
    );
  }
}

/// A fully AI-generated puzzle question.
class GeneratedPuzzleQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String category;
  final String difficulty;
  final bool isAiGenerated;

  const GeneratedPuzzleQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.category,
    required this.difficulty,
    this.isAiGenerated = true,
  });

  factory GeneratedPuzzleQuestion.fromJson(Map<String, dynamic> json) {
    return GeneratedPuzzleQuestion(
      question: json['question'] as String? ?? 'Emergency response question',
      options: List<String>.from(
        json['options'] as List? ?? ['A', 'B', 'C', 'D'],
      ),
      correctIndex: (json['correct_index'] as num?)?.toInt() ?? 0,
      explanation: json['explanation'] as String? ?? '',
      category: json['category'] as String? ?? 'General',
      difficulty: json['difficulty'] as String? ?? 'intermediate',
    );
  }
}

/// Post-mission AI debrief.
class MissionDebrief {
  final String summary;
  final List<String> strengths;
  final List<String> improvements;
  final String nextRecommendedModule;
  final String motivationalMessage;

  const MissionDebrief({
    required this.summary,
    required this.strengths,
    required this.improvements,
    required this.nextRecommendedModule,
    required this.motivationalMessage,
  });

  factory MissionDebrief.fromJson(Map<String, dynamic> json) {
    return MissionDebrief(
      summary: json['summary'] as String? ?? '',
      strengths: List<String>.from(json['strengths'] as List? ?? []),
      improvements: List<String>.from(json['improvements'] as List? ?? []),
      nextRecommendedModule:
          json['next_recommended_module'] as String? ?? 'Continue training',
      motivationalMessage:
          json['motivational_message'] as String? ?? 'Keep going!',
    );
  }
}

// ─── Tamil Nadu disaster season calendar ─────────────────────────────────────

class _TNSeasonCalendar {
  static String getCurrentSeason() {
    final month = DateTime.now().month;
    if (month >= 6 && month <= 9) return 'Southwest Monsoon';
    if (month >= 10 && month <= 12)
      return 'Northeast Monsoon (high flood risk)';
    if (month >= 3 && month <= 5) return 'Summer (heatwave risk)';
    return 'Dry Season (fire risk)';
  }

  static List<String> getCurrentRisks() {
    final month = DateTime.now().month;
    if (month >= 6 && month <= 9) {
      return ['Flooding', 'Landslides', 'Lightning strikes'];
    }
    if (month >= 10 && month <= 12) {
      return ['Cyclones', 'Coastal flooding', 'Urban floods', 'Drowning'];
    }
    if (month >= 3 && month <= 5) {
      return ['Heat stroke', 'Wildfires', 'Water scarcity', 'Dust storms'];
    }
    return ['Industrial fires', 'Road accidents', 'Structural failures'];
  }

  static String getSeasonalContext() {
    return 'Current season: ${getCurrentSeason()}. '
        'Active risks: ${getCurrentRisks().join(', ')}. '
        'Location: Tamil Nadu, South India.';
  }
}

// ─── Volunteer context builder ────────────────────────────────────────────────

class _VolunteerContext {
  final int level;
  final int xp;
  final List<String> skills;
  final String locality;
  final String difficulty;

  const _VolunteerContext({
    required this.level,
    required this.xp,
    required this.skills,
    required this.locality,
    required this.difficulty,
  });

  static _VolunteerContext fromProfile(
    Map<String, dynamic> profile,
    String locality,
  ) {
    final level = (profile['level'] as num?)?.toInt() ?? 1;
    final xp = (profile['xp'] as num?)?.toInt() ?? 0;
    final skills = List<String>.from(profile['skills'] as List? ?? []);

    String difficulty;
    if (level <= 2) {
      difficulty = 'beginner';
    } else if (level <= 5) {
      difficulty = 'intermediate';
    } else {
      difficulty = 'advanced';
    }

    return _VolunteerContext(
      level: level,
      xp: xp,
      skills: skills,
      locality: locality,
      difficulty: difficulty,
    );
  }

  String toPromptContext() {
    return 'Volunteer profile: Level $level, $xp XP, '
        'skills: ${skills.isEmpty ? 'none yet' : skills.join(', ')}. '
        'Difficulty: $difficulty. '
        'Location: $locality, Tamil Nadu, India. '
        '${_TNSeasonCalendar.getSeasonalContext()}';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SCENARIO ENGINE — Singleton
// ══════════════════════════════════════════════════════════════════════════════

class ScenarioEngine {
  ScenarioEngine._();
  static final ScenarioEngine instance = ScenarioEngine._();

  static const String _geminiModel = 'gemini-2.0-flash';

  _VolunteerContext? _volunteerCtx;

  // ── Scenario cache: blockType → list of generated scenarios ──────────────
  final Map<String, List<GeneratedScenario>> _scenarioCache = {};

  // ── Puzzle cache: category → list of questions ────────────────────────────
  final Map<String, List<GeneratedPuzzleQuestion>> _puzzleCache = {};

  // ── Init with volunteer profile + location ────────────────────────────────
  void init(Map<String, dynamic> volunteerProfile) {
    final locality = LocationService.instance.shortLocality.isNotEmpty
        ? LocationService.instance.shortLocality
        : 'Chennai';
    _volunteerCtx = _VolunteerContext.fromProfile(volunteerProfile, locality);
    debugPrint(
      '[ScenarioEngine] Initialised for ${_volunteerCtx!.locality}, '
      'level ${_volunteerCtx!.level}, difficulty ${_volunteerCtx!.difficulty}',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Generate a full training scenario for a given block type
  // ─────────────────────────────────────────────────────────────────────────

  Future<GeneratedScenario?> generateScenario({
    required String blockType,
    String? preferredDisasterType,
  }) async {
    final ctx = _volunteerCtx;
    if (ctx == null) {
      debugPrint('[ScenarioEngine] Not initialised — call init() first.');
      return null;
    }

    final seasonalRisks = _TNSeasonCalendar.getCurrentRisks();
    final disasterType =
        preferredDisasterType ??
        seasonalRisks[DateTime.now().second % seasonalRisks.length];

    final systemPrompt =
        '''
You are a disaster response training content generator for the Hero Network app used by NDRF/SDRF volunteers in Tamil Nadu, India.

${ctx.toPromptContext()}

Generate a realistic training scenario for block type: "$blockType".
Focus on disaster: "$disasterType".

Respond ONLY with a single valid JSON object — no markdown, no code fences, no explanation.

JSON schema:
{
  "title": "short scenario title (max 8 words)",
  "department": "NDRF | SDRF | TNFRS | Medical | Police | Multi-Agency",
  "location": "real Tamil Nadu location (city, landmark, district)",
  "authorised_person": "realistic Indian name with rank/title",
  "objective": "one clear measurable objective sentence",
  "mission_brief": "2-3 paragraph mission briefing with emoji headers, include: situation, your role, equipment needed, location details, completion proof requirement",
  "steps": ["6 clear imperative action steps"],
  "duration_min": integer (30-120),
  "xp_reward": integer (100-400),
  "disaster_type": "$disasterType",
  "difficulty": "${ctx.difficulty}",
  "season": "${_TNSeasonCalendar.getCurrentSeason()}"
}

Rules:
- Use real Tamil Nadu locations (Chennai districts, Ranipet, Vellore, Coimbatore, Madurai etc.)
- Scenarios must be specific and plausible for Indian NDRF/SDRF training
- Steps must be actionable and safety-conscious
- Mission brief must feel authentic to Indian emergency services culture
- For beginner: focus on basic skills and supervised exercises
- For intermediate: multi-step operations with some independent decision-making  
- For advanced: complex multi-victim, multi-agency scenarios
''';

    final result = await _callGeminiWithRotation(systemPrompt);
    if (result == null)
      return _getFallbackScenario(blockType, disasterType, ctx);

    try {
      final json = jsonDecode(result) as Map<String, dynamic>;
      final scenario = GeneratedScenario.fromJson(json);
      _scenarioCache.putIfAbsent(blockType, () => []).add(scenario);
      return scenario;
    } catch (e) {
      debugPrint('[ScenarioEngine] JSON parse error: $e');
      return _getFallbackScenario(blockType, disasterType, ctx);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Generate a batch of scenarios for a training block (pre-warm)
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<GeneratedScenario>> generateScenarioBatch({
    required String blockType,
    int count = 3,
  }) async {
    final results = <GeneratedScenario>[];
    final risks = _TNSeasonCalendar.getCurrentRisks();

    for (int i = 0; i < count; i++) {
      final disaster = risks[i % risks.length];
      final scenario = await generateScenario(
        blockType: blockType,
        preferredDisasterType: disaster,
      );
      if (scenario != null) {
        results.add(scenario);
      }
      // Small delay between calls to avoid quota burst
      if (i < count - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return results;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Generate a dynamic puzzle question
  // ─────────────────────────────────────────────────────────────────────────

  Future<GeneratedPuzzleQuestion?> generatePuzzleQuestion({
    String? category,
    List<String>? alreadyAsked,
  }) async {
    final ctx = _volunteerCtx;
    if (ctx == null) return null;

    final risks = _TNSeasonCalendar.getCurrentRisks();
    final cat = category ?? risks[DateTime.now().millisecond % risks.length];

    final avoidStr = (alreadyAsked?.isNotEmpty == true)
        ? 'Do NOT repeat these questions: ${alreadyAsked!.take(5).join(' | ')}'
        : '';

    final systemPrompt =
        '''
You are a disaster response training quiz generator for Tamil Nadu, India volunteers.

${ctx.toPromptContext()}
Category: "$cat"
$avoidStr

Generate ONE unique multiple-choice question at ${ctx.difficulty} level.
The question must test practical emergency decision-making, not just theory.
Make it specific to Indian/Tamil Nadu disaster scenarios where relevant.

Respond ONLY with a single valid JSON object — no markdown, no code fences.

JSON schema:
{
  "question": "the question text (max 2 sentences)",
  "options": ["option A", "option B", "option C", "option D"],
  "correct_index": integer (0-3),
  "explanation": "1-2 sentence explanation of why the answer is correct and the others are wrong",
  "category": "$cat",
  "difficulty": "${ctx.difficulty}"
}

Rules:
- Options must be plausible — wrong options should be common mistakes, not obviously absurd
- Explanation must reference the correct protocol or reason
- For beginner: basic protocols and universal rules
- For intermediate: nuanced decisions with trade-offs
- For advanced: multi-victim, time-pressured scenarios with protocol conflicts
''';

    final result = await _callGeminiWithRotation(systemPrompt);
    if (result == null) return _getFallbackPuzzle(cat, ctx.difficulty);

    try {
      final json = jsonDecode(result) as Map<String, dynamic>;
      final puzzle = GeneratedPuzzleQuestion.fromJson(json);
      _puzzleCache.putIfAbsent(cat, () => []).add(puzzle);
      return puzzle;
    } catch (e) {
      debugPrint('[ScenarioEngine] Puzzle parse error: $e');
      return _getFallbackPuzzle(cat, ctx.difficulty);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Generate a personalised mission debrief after completion
  // ─────────────────────────────────────────────────────────────────────────

  Future<MissionDebrief?> generateDebrief({
    required String missionTitle,
    required int score, // 0–100
    required int durationMin,
    String? blockType,
  }) async {
    final ctx = _volunteerCtx;
    if (ctx == null) return null;

    final systemPrompt =
        '''
You are a disaster response training mentor for Hero Network (NDRF/SDRF volunteer app), Tamil Nadu, India.

A volunteer just completed a training mission.

Volunteer: Level ${ctx.level}, ${ctx.xp} XP, skills: ${ctx.skills.join(', ')}.
Mission: "$missionTitle"
Score: $score/100
Time taken: $durationMin minutes
Block type: ${blockType ?? 'general'}

Write a brief, personalised debrief. Be encouraging but honest.

Respond ONLY with a single valid JSON object — no markdown, no code fences.

JSON schema:
{
  "summary": "2 sentence overview of performance",
  "strengths": ["2-3 specific things they did well based on score and mission type"],
  "improvements": ["1-2 specific areas to work on"],
  "next_recommended_module": "name of the most logical next training module",
  "motivational_message": "1 short motivational sentence personalised to their level"
}
''';

    final result = await _callGeminiWithRotation(systemPrompt);
    if (result == null) return _getFallbackDebrief(missionTitle, score);

    try {
      final json = jsonDecode(result) as Map<String, dynamic>;
      return MissionDebrief.fromJson(json);
    } catch (e) {
      debugPrint('[ScenarioEngine] Debrief parse error: $e');
      return _getFallbackDebrief(missionTitle, score);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Adaptive training prompt for GeminiChatScreen
  //  (replaces the static _getPromptForTopic in train.dart)
  // ─────────────────────────────────────────────────────────────────────────

  String buildAdaptivePrompt(String topic, String blockType) {
    final ctx = _volunteerCtx;
    final seasonCtx = _TNSeasonCalendar.getSeasonalContext();
    final locality = ctx?.locality ?? 'Tamil Nadu';
    final difficulty = ctx?.difficulty ?? 'intermediate';
    final skills = ctx?.skills.isNotEmpty == true
        ? ctx!.skills.join(', ')
        : 'none declared';

    return '''
You are an expert disaster response trainer for the Hero Network app (Tamil Nadu, India).

Volunteer context:
- Location: $locality
- Skill level: $difficulty
- Existing skills: $skills
- $seasonCtx

Generate comprehensive, personalised training content for: "$topic"
Training module type: $blockType

Structure your response with:
1. **Why This Matters Now** — connect to current seasonal risk in Tamil Nadu
2. **Key Concepts** — level-appropriate for a $difficulty volunteer
3. **Step-by-Step Protocol** — practical, numbered, actionable
4. **India-Specific Notes** — relevant laws, contact numbers (108, 112, 1070), organisations (NDRF, SDRF, TNFRS)
5. **Common Mistakes** — what untrained responders get wrong
6. **Quick Reference** — 3-bullet cheat sheet to remember in the field

Keep language clear, direct, and practical. Reference real Tamil Nadu locations and scenarios where helpful.
''';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Cached scenario getter (returns from cache or generates)
  // ─────────────────────────────────────────────────────────────────────────

  GeneratedScenario? getCachedScenario(String blockType) {
    final cached = _scenarioCache[blockType];
    if (cached == null || cached.isEmpty) return null;
    // Return a random cached scenario
    cached.shuffle();
    return cached.first;
  }

  List<GeneratedPuzzleQuestion> getCachedPuzzles(String category) {
    return _puzzleCache[category] ?? [];
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Gemini API call with key rotation
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> _callGeminiWithRotation(String prompt) async {
    final manager = GeminiKeyManager.instance;
    final totalKeys = manager.totalKeys;

    for (int attempt = 0; attempt < totalKeys; attempt++) {
      try {
        final result = await _callGemini(prompt);
        if (result != null) return result;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('quota') ||
            msg.contains('429') ||
            msg.contains('503')) {
          debugPrint(
            '[ScenarioEngine] Key #${manager.currentIndex} quota — rotating.',
          );
          final hasNext = manager.rotateKey();
          if (!hasNext) break;
          await Future.delayed(const Duration(milliseconds: 400));
          continue;
        }
        debugPrint('[ScenarioEngine] Gemini error: $e');
        break;
      }
    }
    return null;
  }

  Future<String?> _callGemini(String prompt) async {
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.8,
        'maxOutputTokens': 1024,
        'topP': 0.9,
      },
    });

    final endpoint = GeminiKeyManager.instance.endpoint(_geminiModel);

    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode == 429 || response.statusCode == 503) {
      throw Exception('quota:${response.statusCode}');
    }
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final errorMsg = (decoded['error']?['message'] as String? ?? '')
        .toLowerCase();
    if (errorMsg.contains('quota') || errorMsg.contains('rate')) {
      throw Exception('quota:embed');
    }

    final text =
        (decoded['candidates'] as List?)
                ?.firstOrNull?['content']?['parts']
                ?.firstOrNull?['text']
            as String? ??
        '';

    // Strip any accidental markdown fences
    return text.replaceAll(RegExp(r'```json|```'), '').trim();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Fallbacks (offline / API failure)
  // ─────────────────────────────────────────────────────────────────────────

  GeneratedScenario _getFallbackScenario(
    String blockType,
    String disasterType,
    _VolunteerContext ctx,
  ) {
    final season = _TNSeasonCalendar.getCurrentSeason();
    return GeneratedScenario(
      title: '$disasterType Response — ${ctx.locality}',
      department: 'NDRF / SDRF',
      location: '${ctx.locality}, Tamil Nadu',
      authorisedPerson: 'Training Officer K. Suresh',
      objective:
          'Complete the $disasterType response protocol as a $blockType responder.',
      missionBrief:
          '🚨 MISSION BRIEF\n\nA $disasterType incident has been reported near ${ctx.locality}. '
          'You are assigned as a $blockType response volunteer.\n\n'
          'Your mission: Follow the standard $blockType response protocol, '
          'ensure victim safety, and coordinate with the authorised officer.\n\n'
          '📍 Report to your nearest NDRF/SDRF station.\n'
          '👮 Supervisor: Training Officer K. Suresh\n\n'
          'Submit a photo at the training site as completion proof.',
      steps: [
        'Receive briefing from supervising officer',
        'Don required personal protective equipment',
        'Assess the scene for hazards before proceeding',
        'Execute the primary $blockType response protocol',
        'Document all actions in the mission log',
        'Debrief with officer and complete post-mission report',
      ],
      estimatedDurationMin: 45,
      xpReward: 150,
      disasterType: disasterType,
      difficulty: ctx.difficulty,
      season: season,
      isAiGenerated: false,
    );
  }

  GeneratedPuzzleQuestion _getFallbackPuzzle(
    String category,
    String difficulty,
  ) {
    return const GeneratedPuzzleQuestion(
      question:
          'You arrive at a disaster scene. What is the FIRST thing you should do?',
      options: [
        'Begin treating the nearest victim',
        'Ensure your own safety and assess the scene',
        'Call the media for coverage',
        'Wait for others to arrive',
      ],
      correctIndex: 1,
      explanation:
          'Scene safety is always first. An injured responder becomes another casualty, '
          'reducing the team\'s capacity to help victims.',
      category: 'General',
      difficulty: 'beginner',
      isAiGenerated: false,
    );
  }

  MissionDebrief _getFallbackDebrief(String missionTitle, int score) {
    final emoji = score >= 80
        ? '🌟'
        : score >= 60
        ? '💪'
        : '📚';
    return MissionDebrief(
      summary:
          '$emoji You completed "$missionTitle" with a score of $score/100. '
          '${score >= 80 ? 'Excellent execution of the protocol.' : 'There is room to sharpen your technique.'}',
      strengths: [
        'You completed the mission and earned XP',
        score >= 70
            ? 'Good grasp of the core response steps'
            : 'You identified the mission objective correctly',
      ],
      improvements: [
        score < 80 ? 'Review the step-by-step protocol for this module' : '',
        score < 60 ? 'Practice this scenario again before advancing' : '',
      ].where((s) => s.isNotEmpty).toList(),
      nextRecommendedModule: 'Continue to the next mission in this block',
      motivationalMessage: 'Every mission makes you more prepared. Keep going!',
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SCENARIO CARD WIDGET — drop-in replacement for hardcoded DrillScenario cards
// ══════════════════════════════════════════════════════════════════════════════

class GeneratedScenarioCard extends StatelessWidget {
  final GeneratedScenario scenario;
  final VoidCallback? onStart;
  final Color accentColor;

  const GeneratedScenarioCard({
    super.key,
    required this.scenario,
    this.onStart,
    this.accentColor = const Color(0xFF1D4ED8),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (scenario.isAiGenerated) ...[
                            const Icon(
                              Icons.auto_awesome_rounded,
                              size: 12,
                              color: Color(0xFF6A3FA0),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'AI Generated',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF6A3FA0),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              scenario.difficulty.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                color: accentColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        scenario.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        scenario.department,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '+${scenario.xpReward} XP',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1D9E75),
                      ),
                    ),
                    Text(
                      '${scenario.estimatedDurationMin} min',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B6B6B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Metadata row
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 14,
                      color: Color(0xFF6B6B6B),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        scenario.location,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.wb_sunny_rounded,
                      size: 14,
                      color: Color(0xFFBA7517),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        scenario.season,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFBA7517),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCEBEB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        scenario.disasterType,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFE24B4A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Objective
                Text(
                  'Objective',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  scenario.objective,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4A4A4A),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),

                // Steps preview
                Text(
                  'Steps (${scenario.steps.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 6),
                ...scenario.steps
                    .take(3)
                    .toList()
                    .asMap()
                    .entries
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${e.key + 1}',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: accentColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                e.value,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF4A4A4A),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (scenario.steps.length > 3)
                  Text(
                    '+ ${scenario.steps.length - 3} more steps...',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B6B6B),
                    ),
                  ),

                const SizedBox(height: 16),

                // Start button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Start Mission'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DEBRIEF SHEET — shows after mission completion
// ══════════════════════════════════════════════════════════════════════════════

class MissionDebriefSheet extends StatelessWidget {
  final MissionDebrief debrief;
  final int score;
  final VoidCallback? onContinue;

  const MissionDebriefSheet({
    super.key,
    required this.debrief,
    required this.score,
    this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final scoreColor = score >= 80
        ? const Color(0xFF1D9E75)
        : score >= 60
        ? const Color(0xFFBA7517)
        : const Color(0xFFE24B4A);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score header
          Center(
            child: Column(
              children: [
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    color: scoreColor,
                  ),
                ),
                Text(
                  'out of 100',
                  style: TextStyle(
                    fontSize: 14,
                    color: scoreColor.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // AI badge
          Row(
            children: const [
              Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: Color(0xFF6A3FA0),
              ),
              SizedBox(width: 4),
              Text(
                'Gemini AI Debrief',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6A3FA0),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            debrief.summary,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1A1A1A),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),

          if (debrief.strengths.isNotEmpty) ...[
            const Text(
              'What you did well',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D9E75),
              ),
            ),
            const SizedBox(height: 6),
            ...debrief.strengths.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: Color(0xFF1D9E75),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4A4A4A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (debrief.improvements.isNotEmpty) ...[
            const Text(
              'Areas to improve',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFBA7517),
              ),
            ),
            const SizedBox(height: 6),
            ...debrief.improvements.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.arrow_upward_rounded,
                      size: 14,
                      color: Color(0xFFBA7517),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4A4A4A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb_rounded,
                  color: Color(0xFF1D4ED8),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Next recommended',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF1D4ED8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        debrief.nextRecommendedModule,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Text(
            debrief.motivationalMessage,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B6B6B),
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onContinue ?? () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D4ED8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Continue Training',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
