import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'consts.dart';
import 'trauma_check_service.dart'; // Feature 2 — post-mission trauma check trigger

// ─────────────────────────────────────────────
// GEMINI SERVICE WITH CACHING
// ─────────────────────────────────────────────

class GeminiService {
  static final Map<String, String> _memoryCache = {};
  static SharedPreferences? _prefs;

  // Primary and fallback model names (key is appended by GeminiKeyManager)
  static const _primaryModel = 'gemini-2.0-flash';
  static const _fallbackModel = 'gemini-1.5-flash';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final cachedKeys = _prefs?.getKeys() ?? {};
    for (var key in cachedKeys) {
      if (key.startsWith('gemini_')) {
        final cachedResponse = _prefs!.getString(key);
        if (cachedResponse != null) _memoryCache[key] = cachedResponse;
      }
    }
  }

  static Future<String> generateContent(String topic, String type) async {
    try {
      final safeLen = topic.length > 80 ? 80 : topic.length;
      final cacheKey =
          'gemini_${type}_${topic.replaceAll(' ', '_').replaceAll('\n', '_').substring(0, safeLen)}';
      if (_memoryCache.containsKey(cacheKey)) return _memoryCache[cacheKey]!;
      final diskCached = _prefs?.getString(cacheKey);
      if (diskCached != null && diskCached.isNotEmpty) {
        _memoryCache[cacheKey] = diskCached;
        return diskCached;
      }
      final prompt = _getPromptForTopic(topic, type);
      if (prompt.isEmpty) return 'Error: Prompt is empty';

      // Try every available API key before giving up
      final result = await _callWithKeyRotation(prompt);

      if (result != null &&
          result.isNotEmpty &&
          !result.startsWith('API Error') &&
          !result.startsWith('Error:')) {
        _memoryCache[cacheKey] = result;
        await _prefs?.setString(cacheKey, result);
        return result;
      }
      // All keys exhausted — route to offline protocol database
      if (result == null || result.isEmpty) {
        return _getOfflineProtocolResponse(topic);
      }
      return result;
    } on TimeoutException {
      return 'Error: Request timed out. Please check your internet connection and try again.';
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('SocketException') ||
          msg.contains('Connection refused') ||
          msg.contains('Network is unreachable')) {
        return 'Error: No internet connection. Please check your network and try again.';
      }
      if (msg.contains('HandshakeException') || msg.contains('CERTIFICATE')) {
        return 'Error: SSL/TLS connection failed. Please check your network settings.';
      }
      return 'Error: $msg';
    }
  }

  /// Tries primary then fallback model on each key in sequence.
  /// Rotates key on quota/rate-limit. Returns null only when truly exhausted.
  static Future<String?> _callWithKeyRotation(String prompt) async {
    final manager = GeminiKeyManager.instance;
    final totalKeys = manager.totalKeys;

    for (int attempt = 0; attempt < totalKeys; attempt++) {
      // Try primary model first
      String? result = await _callGeminiApi(_primaryModel, prompt);

      // null = model not found / network issue — try fallback model immediately
      if (result == null) {
        result = await _callGeminiApi(_fallbackModel, prompt);
      }

      // Quota on primary — try fallback with same key
      if (result == _kQuotaSignal) {
        result = await _callGeminiApi(_fallbackModel, prompt);
      }

      // Still quota after both models — rotate to next key
      if (result == _kQuotaSignal) {
        debugPrint(
          '[GeminiService] Key #${manager.currentIndex} quota — rotating.',
        );
        final hasNext = manager.rotateKey();
        if (!hasNext) break;
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }

      // Got a real result (good response or an API error string)
      if (result != null && result.isNotEmpty) return result;

      // Both models returned null — rotate key and try again
      debugPrint(
        '[GeminiService] Key #${manager.currentIndex} null — rotating.',
      );
      final hasNext = manager.rotateKey();
      if (!hasNext) break;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    return null; // fully exhausted — caller routes to offline protocols
  }

  // Sentinel value returned internally when a 429/quota response is received.
  static const _kQuotaSignal = '__QUOTA_EXCEEDED__';

  static Future<String?> _callGeminiApi(String model, String prompt) async {
    try {
      final key = GeminiKeyManager.instance.currentKey;
      final uri = Uri.parse('$_baseUrl/$model:generateContent?key=$key');
      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 1024},
        'safetySettings': [
          {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_NONE'},
          {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_NONE'},
          {
            'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
            'threshold': 'BLOCK_NONE',
          },
          {
            'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
            'threshold': 'BLOCK_NONE',
          },
        ],
      });

      final response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Check for quota error embedded in a 200 body
        final errorMsg = (data['error']?['message'] as String? ?? '')
            .toLowerCase();
        if (errorMsg.contains('quota') || errorMsg.contains('rate')) {
          return _kQuotaSignal;
        }
        final finishReason = data['candidates']?[0]?['finishReason'] as String?;
        if (finishReason == 'SAFETY') {
          return 'Content was blocked by safety filters. Please rephrase your question.';
        }
        final text =
            data['candidates']?[0]?['content']?['parts']?[0]?['text']
                as String?;
        return text;
      } else if (response.statusCode == 429 || response.statusCode == 503) {
        return _kQuotaSignal; // signal rotation
      } else if (response.statusCode == 400) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final msg = data['error']?['message'] as String? ?? 'Bad request';
          return 'API Error: $msg';
        } catch (_) {
          return 'API Error (400): Bad request. Check your API key.';
        }
      } else if (response.statusCode == 403) {
        return 'API Error (403): Access denied. Your API key may be invalid or restricted.';
      } else if (response.statusCode == 404) {
        return null; // model not found — let caller try fallback model
      } else {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final msg = data['error']?['message'] as String? ?? response.body;
          return 'API Error (${response.statusCode}): $msg';
        } catch (_) {
          return 'API Error (${response.statusCode}): ${response.body}';
        }
      }
    } on TimeoutException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// Called when all API keys are exhausted. Delegates to the offline
  /// protocol database so the user still gets a useful response.
  static String _getOfflineProtocolResponse(String topic) {
    // Import-free inline fallback — matches OfflineProtocolDB keyword logic
    final t = topic.toLowerCase();
    if (_hasWord(t, [
      'cpr',
      'cardiac',
      'heart',
      'chest compression',
      'no pulse',
    ])) {
      return _offlineProtocol('🔴 CPR — Cardiac Arrest', [
        'Call 108 immediately.',
        'Place heel of hand on centre of chest.',
        'Compress hard and fast — 5 cm deep, 100–120/min.',
        'Give 30 compressions then 2 rescue breaths.',
        'Continue until ambulance arrives.',
      ]);
    }
    if (_hasWord(t, ['flood', 'drowning', 'water rescue', 'submerged'])) {
      return _offlineProtocol('🔴 Flood / Drowning Response', [
        'Do NOT enter water unless trained.',
        'Throw rope or float; reach with a stick.',
        'Once on land: check breathing, start CPR if needed.',
        'Remove wet clothes; watch for hypothermia.',
        'Call 108 — secondary drowning can occur hours later.',
      ]);
    }
    if (_hasWord(t, ['fire', 'burn', 'smoke', 'flame', 'blaze'])) {
      return _offlineProtocol('🟠 Fire & Burns', [
        'Evacuate immediately — life over property.',
        'Stay low if smoke present; do NOT use elevators.',
        'Call 101 (fire) from outside.',
        'Cool burns under running water for 20 minutes.',
        'Do NOT apply ice, butter, or toothpaste.',
      ]);
    }
    if (_hasWord(t, ['earthquake', 'tremor', 'quake', 'rubble', 'collapse'])) {
      return _offlineProtocol('🔴 Earthquake Response', [
        'DROP, COVER, HOLD ON during shaking.',
        'Stay away from windows and outer walls.',
        'After shaking: expect aftershocks — move to open area.',
        'Check for gas leaks; do NOT use open flames.',
        'Call 112 for NDRF assistance.',
      ]);
    }
    if (_hasWord(t, ['bleeding', 'wound', 'cut', 'laceration', 'hemorrhage'])) {
      return _offlineProtocol('🔴 Severe Bleeding', [
        'Apply firm direct pressure with clean cloth.',
        'Do NOT remove soaked material — add more on top.',
        'Elevate wound above heart level.',
        'Use tourniquet for uncontrolled limb bleeding — 5 cm above wound.',
        'Note time of tourniquet; call 108.',
      ]);
    }
    if (_hasWord(t, ['choking', 'heimlich', 'airway', 'cannot breathe'])) {
      return _offlineProtocol('🔴 Choking — Airway Obstruction', [
        'If they can cough — encourage coughing.',
        'Give 5 firm back blows between shoulder blades.',
        'Follow with 5 sharp upward abdominal thrusts (Heimlich).',
        'Alternate back blows and thrusts until clear.',
        'If unconscious: start CPR; call 108.',
      ]);
    }
    if (_hasWord(t, ['snake', 'venom', 'bite', 'cobra', 'viper', 'krait'])) {
      return _offlineProtocol('🟠 Snakebite First Aid', [
        'Keep victim still — movement spreads venom.',
        'Immobilise bitten limb BELOW heart level.',
        'Do NOT cut, suck, or apply tourniquet.',
        'Mark swelling edge with pen; note the time.',
        'Call 108 — anti-venom at all government hospitals.',
      ]);
    }
    if (_hasWord(t, [
      'heat stroke',
      'sunstroke',
      'overheating',
      'hyperthermia',
    ])) {
      return _offlineProtocol('🟠 Heat Stroke', [
        'Move victim to shade or cool area immediately.',
        'Cool rapidly — wet cloth, fanning, ice on neck/armpits.',
        'If conscious: give cool water slowly.',
        'If unconscious: recovery position; do NOT give fluids.',
        'Call 108 — heat stroke is life-threatening.',
      ]);
    }
    // Generic fallback
    return '''🟡 **Emergency Guidance — Offline Mode**

No internet available. Follow universal first response steps:

**IMMEDIATE ACTIONS:**
1. Ensure your own safety first.
2. Call 112 (all emergencies) or 108 (ambulance).
3. Do not move victim unless in immediate danger.
4. Keep victim warm, calm, and conscious.
5. Stay on the line with emergency services.

**Emergency Numbers (India):**
• 112 — All emergencies  •  108 — Ambulance
• 101 — Fire brigade     •  100 — Police
• 1070 — TN Disaster Helpline  •  1078 — NDRF

_Reconnect to internet for full AI guidance._''';
  }

  static bool _hasWord(String text, List<String> words) =>
      words.any((w) => text.contains(w));

  static String _offlineProtocol(String title, List<String> steps) {
    final buf = StringBuffer('**$title**\n\n**IMMEDIATE STEPS:**\n');
    for (int i = 0; i < steps.length; i++) {
      buf.writeln('${i + 1}. ${steps[i]}');
    }
    buf.writeln('\n_Emergency: 112 · 108 · 101 · 100_');
    buf.writeln('_Offline protocol — reconnect for full AI guidance._');
    return buf.toString();
  }

  static String _getPromptForTopic(String topic, String type) {
    switch (type) {
      case 'basic':
        return 'Provide comprehensive training content for Emergency Disaster Response volunteers about "$topic". Include: 1) Definition and importance, 2) Key concepts, 3) Real-world applications in India, 4) Step-by-step guide, 5) Common mistakes to avoid. Format as clear sections with bullet points. Keep it practical and actionable.';
      case 'survival':
        return 'Create detailed survival training content for "$topic" in disaster scenarios. Include: 1) Why this skill is critical, 2) Equipment needed, 3) Step-by-step instructions, 4) Safety precautions, 5) Common mistakes, 6) Tips for different conditions. Use real examples from Indian disaster events.';
      case 'medical':
        return 'Provide medical training content for "$topic" for disaster response. Include: 1) When and why this is needed, 2) Proper technique with steps, 3) Equipment required, 4) Warning signs to watch for, 5) What to do next, 6) Common errors.';
      case 'fire':
        return 'Create fire safety and rescue training content for "$topic". Include: 1) Fire classification and behavior, 2) Safety protocols, 3) Equipment and tools, 4) Step-by-step procedures, 5) Hazard identification, 6) Emergency exit procedures.';
      case 'rescue':
        return 'Provide comprehensive rescue operation training for "$topic". Include: 1) Scenario assessment, 2) Pre-rescue safety checks, 3) Equipment setup, 4) Step-by-step rescue procedure, 5) Victim handling, 6) Post-rescue care.';
      case 'puzzle':
        return 'Explain the reasoning and correct answer for the emergency response puzzle: "$topic". Include: 1) Why this scenario is important, 2) The correct action and why, 3) What happens if you do the wrong thing, 4) Related protocols, 5) How to remember this in an emergency.';
      case 'drill':
        return 'Provide comprehensive training for the emergency drill: "$topic". Include: 1) Drill objectives, 2) Roles and responsibilities, 3) Equipment needed, 4) Step-by-step execution, 5) Safety measures, 6) How to evaluate success, 7) Common challenges.';
      case 'combined':
        return 'Explain the multi-agency disaster response for: "$topic". Include: 1) Scenario overview, 2) Roles of each agency (Fire, Police, Medical, NDRF), 3) Coordination points, 4) Timeline and priorities, 5) Critical decision points, 6) Post-incident review.';
      default:
        return 'Provide comprehensive emergency disaster response training content about "$topic". Include practical, actionable information with examples relevant to Indian disaster scenarios.';
    }
  }
}

// ─────────────────────────────────────────────
// GEMINI CHAT SCREEN
// ─────────────────────────────────────────────

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class GeminiChatScreen extends StatefulWidget {
  final String title;
  final String topic;
  final Color color;
  final String blockType;

  const GeminiChatScreen({
    super.key,
    required this.title,
    required this.topic,
    required this.color,
    required this.blockType,
  });

  @override
  State<GeminiChatScreen> createState() => _GeminiChatScreenState();
}

class _GeminiChatScreenState extends State<GeminiChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadInitialContent();
  }

  void _loadInitialContent() async {
    setState(() => _isLoading = true);
    final content = await GeminiService.generateContent(
      widget.topic,
      widget.blockType,
    );
    if (mounted) {
      setState(() {
        _messages.add(
          ChatMessage(text: content, isUser: false, timestamp: DateTime.now()),
        );
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _sendMessage() async {
    if (_messageController.text.isEmpty) return;
    final userMessage = _messageController.text;
    _messageController.clear();
    setState(() {
      _messages.add(
        ChatMessage(text: userMessage, isUser: true, timestamp: DateTime.now()),
      );
      _isLoading = true;
    });
    _scrollToBottom();
    final response = await GeminiService.generateContent(
      '$userMessage\n\nContext: This is about ${widget.topic}',
      widget.blockType,
    );
    if (mounted) {
      setState(() {
        _messages.add(
          ChatMessage(text: response, isUser: false, timestamp: DateTime.now()),
        );
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2EDE8),
      appBar: AppBar(
        backgroundColor: widget.color,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            Text(
              'Powered by Gemini AI',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      color: widget.color,
                      strokeWidth: 3,
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _ChatBubble(
                      message: _messages[index],
                      color: widget.color,
                    ),
                  ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: widget.color,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Getting response...',
                    style: TextStyle(fontSize: 12, color: widget.color),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Ask anything about ${widget.topic}...',
                      hintStyle: const TextStyle(color: Color(0xFFB0ACA6)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Color(0xFFE8E4DF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: widget.color, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isLoading ? null : _sendMessage,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _isLoading
                          ? const Color(0xFFD0CCC6)
                          : widget.color,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
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

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final Color color;
  const _ChatBubble({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: message.isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser ? color : const Color(0xFFEAE6E0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(
                message.text,
                style: TextStyle(
                  color: message.isUser
                      ? Colors.white
                      : const Color(0xFF1A1A1A),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ENUMS & DATA MODELS
// ─────────────────────────────────────────────

enum BlockStatus { locked, inProgress, completed }

enum BlockTier { bronze, silver, gold, army }

class TrainingBlock {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;
  final Color lightColor;
  final int xpReward;
  final int level;
  final BlockStatus status;
  final double progress;
  final List<TrainingMission> missions;
  final bool isArmy;
  final BlockTier tier;
  final String blockType;

  const TrainingBlock({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
    required this.lightColor,
    required this.xpReward,
    required this.level,
    required this.status,
    this.progress = 0.0,
    this.missions = const [],
    this.isArmy = false,
    this.tier = BlockTier.bronze,
    this.blockType = 'basic',
  });
}

class TrainingMission {
  final String title;
  final String type;
  final int xp;
  final int durationMin;
  final bool completed;
  final String? score;

  const TrainingMission({
    required this.title,
    required this.type,
    required this.xp,
    required this.durationMin,
    this.completed = false,
    this.score,
  });
}

class PuzzleQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const PuzzleQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

class DrillScenario {
  final String title;
  final String department;
  final String location;
  final String authorisedPerson;
  final String objective;
  final List<String> steps;
  final int durationMin;
  final String missionBrief;

  const DrillScenario({
    required this.title,
    required this.department,
    required this.location,
    required this.authorisedPerson,
    required this.objective,
    required this.steps,
    required this.durationMin,
    this.missionBrief = '',
  });
}

// ─────────────────────────────────────────────
// PUZZLE DATA
// ─────────────────────────────────────────────

const List<PuzzleQuestion> survivalPuzzles = [
  PuzzleQuestion(
    question:
        'A flood is rising fast. You are on the ground floor. What is the FIRST thing you should do?',
    options: [
      'Collect valuables',
      'Move to the highest floor immediately',
      'Call for help from the window',
      'Switch off electricity at mains',
    ],
    correctIndex: 3,
    explanation:
        'Always switch off electricity first to prevent electrocution, then move upward.',
  ),
  PuzzleQuestion(
    question:
        'You find an unconscious person during a fire. They are breathing. What do you do?',
    options: [
      'Leave them and exit',
      'Put them in recovery position and shout for help',
      'Splash water on face',
      'Perform CPR immediately',
    ],
    correctIndex: 1,
    explanation:
        'A breathing unconscious person needs recovery position. CPR is for non-breathing victims.',
  ),
  PuzzleQuestion(
    question: 'During an earthquake, you are indoors. The safest action is?',
    options: [
      'Run outside immediately',
      'Stand near windows',
      'Drop, cover, hold under a sturdy table',
      'Go to the elevator',
    ],
    correctIndex: 2,
    explanation:
        'Drop-Cover-Hold is the globally recommended protocol during an earthquake.',
  ),
  PuzzleQuestion(
    question:
        'Your water supply is contaminated after a disaster. You should drink?',
    options: [
      'River water directly',
      'Boiled or chemically treated water',
      'Soft drinks only',
      'Rainwater without treatment',
    ],
    correctIndex: 1,
    explanation:
        'Boiling or chemical treatment (chlorine/iodine tablets) makes water safe to drink.',
  ),
  PuzzleQuestion(
    question:
        'Which color triage tag indicates a victim who needs IMMEDIATE life-saving treatment?',
    options: ['Green', 'Yellow', 'Red', 'Black'],
    correctIndex: 2,
    explanation:
        'Red = Immediate. Yellow = Delayed. Green = Minor. Black = Deceased/Unsalvageable.',
  ),
  PuzzleQuestion(
    question: 'During a building evacuation, you should use?',
    options: [
      'Elevator for speed',
      'Staircase only',
      'Windows if ground floor is blocked',
      'Wait for rescue in your room',
    ],
    correctIndex: 1,
    explanation:
        'Always use stairs. Elevators may fail, trap you, or open at fire floors.',
  ),
  PuzzleQuestion(
    question: 'The universal distress signal using sound is?',
    options: [
      '4 short blasts',
      '2 long blasts',
      'SOS: 3 short + 3 long + 3 short',
      'Continuous horn',
    ],
    correctIndex: 2,
    explanation:
        'SOS (• • • — — — • • •) is the internationally recognized distress signal.',
  ),
  PuzzleQuestion(
    question:
        'A victim has a deep cut on their arm and is bleeding heavily. First action?',
    options: [
      'Apply tourniquet immediately',
      'Apply direct pressure with clean cloth',
      'Pour antiseptic directly',
      'Elevate arm and wait',
    ],
    correctIndex: 1,
    explanation:
        'Direct pressure is the first step. Tourniquet is a last resort for limb-threatening bleeding.',
  ),
  PuzzleQuestion(
    question: 'During a gas leak in a building, you should NOT?',
    options: [
      'Open windows and doors',
      'Switch on lights or use phone inside',
      'Evacuate immediately',
      'Alert neighbors',
    ],
    correctIndex: 1,
    explanation:
        'Any spark — including switching on lights or using phones — can ignite leaked gas.',
  ),
  PuzzleQuestion(
    question: 'Identify the correct order for basic life support?',
    options: [
      'Airway → Breathing → Circulation',
      'Circulation → Airway → Breathing',
      'Breathing → Circulation → Airway',
      'Airway → Circulation → Breathing',
    ],
    correctIndex: 0,
    explanation:
        'ABC: Airway first, then Breathing, then Circulation — the standard BLS protocol.',
  ),
];

// ─────────────────────────────────────────────
// DRILL DATA
// ─────────────────────────────────────────────

const List<DrillScenario> fireDrills = [
  DrillScenario(
    title: 'Kitchen Fire Containment',
    department: 'Fire & Rescue Services',
    location: 'Chennai Fire Station, Anna Nagar',
    authorisedPerson: 'Fire Officer R. Venkatesh',
    objective:
        'Contain a Class B fire using CO2 extinguisher without spreading flames.',
    missionBrief:
        '🔥 MISSION BRIEF\n\nA kitchen fire has broken out at a residential building. The cooking oil has caught fire and is spreading to the surrounding cabinets.\n\nYour mission: Use the correct fire extinguisher to contain the blaze before it spreads. Remember — water will make a cooking oil fire WORSE.\n\n⚠️ Equipment: CO2 Extinguisher, PPE kit\n📍 Report to: Chennai Fire Station, Anna Nagar\n👮 Supervisor: Fire Officer R. Venkatesh\n\nWhen done, photograph yourself with the fire officer at the station and submit as proof of completion.',
    steps: [
      'Don PPE — helmet, gloves, boots',
      'Identify fire class (cooking oil = Class B)',
      'Grab CO2 extinguisher',
      'PASS: Pull pin, Aim at base, Squeeze handle, Sweep side to side',
      'Do not use water on oil fire',
      'Alert others and assist evacuation',
    ],
    durationMin: 30,
  ),
  DrillScenario(
    title: 'High-Rise Evacuation Lead',
    department: 'Fire & Rescue Services',
    location: 'TNFRS Training Ground, Egmore',
    authorisedPerson: 'Senior Officer P. Meena',
    objective:
        'Lead 20 occupants from 8th floor to assembly point within 4 minutes.',
    missionBrief:
        '🏢 MISSION BRIEF\n\nFire has been reported on the 3rd floor of a multi-storey building. You are assigned as the Floor Warden for the 8th floor with 20 occupants under your responsibility.\n\nYour mission: Safely evacuate all 20 occupants to the designated assembly point within 4 minutes, assisting differently-abled persons.\n\n⚠️ Equipment: Floor warden vest, headcount sheet, walkie-talkie\n📍 Report to: TNFRS Training Ground, Egmore\n👮 Supervisor: Senior Officer P. Meena\n\nSubmit a photo with all evacuees at the assembly point as completion proof.',
    steps: [
      'Sound alarm on your floor',
      'Check doors for heat before opening',
      'Direct people to nearest stairwell',
      'Count occupants at each landing',
      'Assist differently-abled persons',
      'Report headcount at assembly point',
    ],
    durationMin: 40,
  ),
  DrillScenario(
    title: 'Hose Operation at Live Site',
    department: 'Fire & Rescue Services',
    location: 'Tambaram Fire Station',
    authorisedPerson: 'Sub-Officer K. Rajan',
    objective:
        'Operate a 65mm delivery hose to extinguish a controlled live fire.',
    missionBrief:
        '🚒 MISSION BRIEF\n\nA controlled live fire exercise is set up at Tambaram Fire Station. You will operate a 65mm delivery hose connected to the station hydrant.\n\nYour mission: Properly connect, deploy, and operate the hose to extinguish the controlled fire — aiming at the BASE, not the flames.\n\n⚠️ Equipment: 65mm delivery hose, coupling wrench, boots\n📍 Report to: Tambaram Fire Station\n👮 Supervisor: Sub-Officer K. Rajan\n\nSubmit a photo operating the hose under supervision as completion proof.',
    steps: [
      'Unroll hose without kinks',
      'Connect to hydrant coupling',
      'Signal to open valve slowly',
      'Grip hose with both hands, crouch low',
      'Aim at base of fire, not the flames',
      'Signal cut-off when fire is out',
    ],
    durationMin: 45,
  ),
  DrillScenario(
    title: 'Search & Rescue in Smoke-Filled Corridor',
    department: 'Fire & Rescue Services',
    location: 'Mock Structure, Guindy',
    authorisedPerson: 'Fire Officer S. Dharani',
    objective:
        'Navigate smoke-filled corridors using a guideline rope and locate a dummy victim.',
    missionBrief:
        '🌫️ MISSION BRIEF\n\nA victim is trapped inside a smoke-filled mock structure at Guindy. Visibility is near zero. You must enter with SCBA and locate the victim using the wall-touch method.\n\nYour mission: Navigate through the smoke corridor, locate the dummy victim, and tag them — then safely withdraw following the guideline rope.\n\n⚠️ Equipment: SCBA, guideline rope, triage tags\n📍 Report to: Mock Structure, Guindy\n👮 Supervisor: Fire Officer S. Dharani\n\nSubmit a photo with the tagged dummy and your supervisor as completion proof.',
    steps: [
      'Don SCBA and check air level',
      'Attach guideline rope at entry',
      'Crawl below smoke level',
      'Navigate using wall-touch method',
      'Locate and tag dummy with triage marker',
      'Withdraw following guideline rope',
    ],
    durationMin: 50,
  ),
  DrillScenario(
    title: 'Electrical Fire Safety Protocol',
    department: 'Fire & Rescue Services',
    location: 'TNEB Training Centre, Royapuram',
    authorisedPerson: 'Chief Electrical Officer M. Suresh',
    objective:
        'Handle Class C (electrical) fire and de-energise source safely.',
    missionBrief:
        '⚡ MISSION BRIEF\n\nAn electrical fire has erupted from a switchboard panel in a simulated industrial setting. Water is NOT an option.\n\nYour mission: Identify the correct extinguisher for Class C fire, isolate the main circuit breaker, and safely suppress the fire without causing electrocution risk.\n\n⚠️ Equipment: Dry powder extinguisher, insulated gloves\n📍 Report to: TNEB Training Centre, Royapuram\n👮 Supervisor: Chief Electrical Officer M. Suresh\n\nSubmit a photo at the de-energised panel board as completion proof.',
    steps: [
      'Do NOT use water on electrical fire',
      'Locate and isolate main circuit breaker',
      'Use dry powder extinguisher',
      'Maintain safe standoff distance',
      'Prevent others from re-energising',
      'Document panel board status',
    ],
    durationMin: 35,
  ),
  DrillScenario(
    title: 'Casualty Extraction from Burning Vehicle',
    department: 'Fire & Rescue Services',
    location: 'SDRF Training Facility, Poonamallee',
    authorisedPerson: 'Senior Rescue Officer V. Priya',
    objective:
        'Extract an immobilised casualty from a simulated burning vehicle safely.',
    missionBrief:
        '🚗 MISSION BRIEF\n\nA road accident has resulted in a vehicle fire with an immobilised occupant. The fire is spreading and extraction must happen in under 3 minutes.\n\nYour mission: Stabilise the vehicle, break access, apply neck collar, and extract the casualty using spine board — safely moving them 30m from the vehicle.\n\n⚠️ Equipment: Centre punch, neck collar, long spine board, chocks\n📍 Report to: SDRF Training Facility, Poonamallee\n👮 Supervisor: Senior Rescue Officer V. Priya\n\nSubmit a photo of the completed extraction exercise as proof.',
    steps: [
      'Park rescue vehicle upwind of fire',
      'Stabilise the casualty vehicle using chocks',
      'Break glass using centre punch',
      'Apply neck collar before extraction',
      'Use long spine board for extraction',
      'Move casualty 30m from vehicle before treatment',
    ],
    durationMin: 60,
  ),
  DrillScenario(
    title: 'Mass Evacuation Coordination Drill',
    department: 'Fire & Rescue Services',
    location: 'Rajiv Gandhi Government Hospital, Omandurar',
    authorisedPerson: 'Hospital Safety Officer Dr. S. Kavitha',
    objective:
        'Coordinate evacuation of 50+ hospital patients including bedridden persons.',
    missionBrief:
        '🏥 MISSION BRIEF\n\nFire alarm triggered at Rajiv Gandhi Hospital. You must coordinate the full evacuation of 50+ patients including bedridden and mobility-impaired individuals.\n\nYour mission: Assign team roles, manage floor-by-floor clearance, use evacuation chairs for mobility-impaired — and establish a triage post at the assembly point.\n\n⚠️ Equipment: Evacuation chairs, ward lists, walkie-talkie\n📍 Report to: Rajiv Gandhi Hospital, Omandurar\n👮 Supervisor: Dr. S. Kavitha\n\nSubmit a photo at the triage post with evacuation team as completion proof.',
    steps: [
      'Activate hospital fire alarm',
      'Assign team roles: sweeper, guide, assembly warden',
      'Use evacuation chairs for mobility-impaired',
      'Clear all wards floor-by-floor starting from fire floor',
      'Do NOT use lifts for patients',
      'Establish triage post at assembly point',
    ],
    durationMin: 70,
  ),
];

const List<DrillScenario> rescueDrills = [
  DrillScenario(
    title: 'Flood Water Rescue with Boat',
    department: 'NDRF / SDRF',
    location: 'NDRF Regional Centre, Chennai',
    authorisedPerson: 'NDRF Inspector G. Arun',
    objective:
        'Navigate an inflatable rescue boat in fast-moving water and extract 3 victims.',
    missionBrief:
        '🚤 MISSION BRIEF\n\nFloodwaters have isolated three residents on rooftops near the Adyar River basin. An inflatable rescue boat must be deployed immediately.\n\nYour mission: Don PFD, launch the boat upstream, approach victims safely from the downstream side, and transport all three to elevated ground.\n\n⚠️ Equipment: Inflatable rescue boat, PFD, helmet, rescue rope\n📍 Report to: NDRF Regional Centre, Chennai\n👮 Supervisor: NDRF Inspector G. Arun\n\nSubmit a photo on the boat with your supervisor as completion proof.',
    steps: [
      'Don PFD and helmet',
      'Launch boat upstream of victim',
      'Approach victim from downstream side',
      'Throw rescue rope if within 10m',
      'Pull victim over bow — never the side',
      'Transport to safe elevated ground',
    ],
    durationMin: 60,
  ),
  DrillScenario(
    title: 'Rope Rescue from Height',
    department: 'NDRF / SDRF',
    location: 'SDRF Training Tower, Ambattur',
    authorisedPerson: 'Rope Rescue Specialist R. Devi',
    objective:
        'Perform a two-person rope rescue from a simulated 4th floor window.',
    missionBrief:
        '🏗️ MISSION BRIEF\n\nA victim is trapped on the 4th floor of a building with no staircase access. You and a partner must execute a two-person rope rescue.\n\nYour mission: Set the anchor point, don harnesses, attach the victim in an improvised seat harness, and rappel in tandem to the ground with ground crew support.\n\n⚠️ Equipment: Harness, belay device, ropes, carabiners\n📍 Report to: SDRF Training Tower, Ambattur\n👮 Supervisor: Rope Rescue Specialist R. Devi\n\nSubmit a photo mid-rappel with supervisor below as completion proof.',
    steps: [
      'Set anchor point — belay device + backup',
      'Don harness and check buckle threefold',
      'Attach casualty in improvised seat harness',
      'Rappel in tandem controlling descent rate',
      'Signal ground crew for lower-off assist',
      'Document rescue in log sheet',
    ],
    durationMin: 90,
  ),
  DrillScenario(
    title: 'Collapsed Structure Victim Search',
    department: 'Urban Search & Rescue',
    location: 'Mock Rubble Site, Porur',
    authorisedPerson: 'USAR Team Leader N. Balaji',
    objective:
        'Use search dogs and listening devices to locate 2 victims in collapsed structure.',
    missionBrief:
        '🏚️ MISSION BRIEF\n\nA building has partially collapsed after an earthquake. Two victims are believed to be trapped in void spaces within the rubble.\n\nYour mission: Establish a search grid, deploy canine and acoustic teams, mark confirmed victim locations, and safely extricate using a manual lifting frame.\n\n⚠️ Equipment: Acoustic listening device, spray paint, manual lifting frame\n📍 Report to: Mock Rubble Site, Porur\n👮 Supervisor: USAR Team Leader N. Balaji\n\nSubmit a photo at a marked victim location as completion proof.',
    steps: [
      'Establish search grid on structure map',
      'Deploy canine search team first',
      'Use acoustic listening device in voids',
      'Mark confirmed locations with spray paint',
      'Stabilise debris before tunnelling',
      'Extricate victim using manual lifting frame',
    ],
    durationMin: 120,
  ),
  DrillScenario(
    title: 'Swiftwater Swimmer Rescue',
    department: 'State Disaster Response Force',
    location: 'Chembarambakkam Reservoir, Chennai',
    authorisedPerson: 'Swiftwater Rescue Trainer P. Sathish',
    objective:
        'Swim across a current and assist a panicking victim to shore using contact rescue.',
    missionBrief:
        '🌊 MISSION BRIEF\n\nA panicking victim has been swept into a fast-moving current at the Chembarambakkam Reservoir edge. Throw rope rescue is not possible.\n\nYour mission: Enter the water at 45°, approach from behind, apply cross-chest carry, and use the current angle to bring the victim to the shore eddy safely.\n\n⚠️ Equipment: PFD, wetsuit, rescue fins\n📍 Report to: Chembarambakkam Reservoir, West Chennai\n👮 Supervisor: Trainer P. Sathish\n\nSubmit a photo with trainer at the water\'s edge as completion proof.',
    steps: [
      'Assess current speed and hazards',
      'Enter water at 45° angle upstream',
      'Approach victim from behind to avoid being grabbed',
      'Apply cross-chest carry',
      'Angle body to use current for shore assistance',
      'Exit water at pre-selected calm eddy',
    ],
    durationMin: 75,
  ),
  DrillScenario(
    title: 'Mass Casualty Triage Setup',
    department: 'NDRF Medical Division',
    location: 'Govt Medical College, Omandurar',
    authorisedPerson: 'Dr. M. Vijayalakshmi',
    objective:
        'Set up a field triage post for 30 casualties using START protocol within 15 minutes.',
    missionBrief:
        '🏥 MISSION BRIEF\n\nAn earthquake has produced 30 casualties at a collapsed market. A field triage post must be operational within 15 minutes using the START protocol.\n\nYour mission: Mark triage zones, assign medics, apply START (Breathing → Circulation → Mental Status), and tag all patients by priority colour.\n\n⚠️ Equipment: Triage tags (Red/Yellow/Green/Black), coloured tape, casualty register\n📍 Report to: Govt Medical College, Omandurar\n👮 Supervisor: Dr. M. Vijayalakshmi\n\nSubmit a photo of the completed triage setup as proof.',
    steps: [
      'Mark four triage zones using coloured tape',
      'Assign one medic per zone',
      'Apply START: Breathing → Circulation → Mental Status',
      'Tag each patient Red/Yellow/Green/Black',
      'Direct ambulances by priority',
      'Document all tags in casualty register',
    ],
    durationMin: 90,
  ),
  DrillScenario(
    title: 'Night Search Operation with Torchlight Grid',
    department: 'NDRF / Police',
    location: 'Thiruvanmiyur Beach, Chennai',
    authorisedPerson: 'Police Inspector T. Ragavan',
    objective:
        'Conduct a night-time beach search for missing persons using grid formation.',
    missionBrief:
        '🌙 MISSION BRIEF\n\nA fisherman is reported missing after a storm at Thiruvanmiyur Beach. A night search must be conducted using the grid formation technique.\n\nYour mission: Brief team on missing person description, divide the beach into 50m grid sectors, maintain 5m spacing, and communicate via whistle codes.\n\n⚠️ Equipment: Torches, whistle, sector map\n📍 Report to: Thiruvanmiyur Beach, Chennai\n👮 Supervisor: Inspector T. Ragavan\n\nSubmit a photo of your team in grid formation at the beach as proof.',
    steps: [
      'Brief team on missing person description',
      'Divide beach into 50m grid sectors',
      'Maintain 5m spacing between searchers',
      'Call "CHECK" every 100m for headcount',
      'Use whistle codes: 1 = stop, 3 = found',
      'Report findings to incident commander immediately',
    ],
    durationMin: 80,
  ),
  DrillScenario(
    title: 'Chemical Spill Rescue Protocol',
    department: 'NDRF HazMat Unit',
    location: 'Industrial Zone, Manali',
    authorisedPerson: 'HazMat Officer K. Selvam',
    objective:
        'Extract a victim from a chemical spill zone while avoiding contamination.',
    missionBrief:
        '☣️ MISSION BRIEF\n\nA chemical tanker has ruptured at the Manali Industrial Zone. One worker is unconscious inside the hot zone. You must extract them without direct skin contact.\n\nYour mission: Don Level B PPE, establish hot/warm/cold zones, enter in pairs, extract the victim without contamination, and conduct full decontamination before exiting.\n\n⚠️ Equipment: Level B PPE, full-face respirator, decon shower\n📍 Report to: Industrial Zone, Manali\n👮 Supervisor: HazMat Officer K. Selvam\n\nSubmit a photo in full PPE with supervisor as completion proof.',
    steps: [
      'Don Level B PPE — full-face respirator + chemical suit',
      'Establish hot/warm/cold zones with barrier tape',
      'Decontamination station set up in warm zone',
      'Enter hot zone in pair, never alone',
      'Extract victim without direct contact',
      'Conduct full decon before exiting warm zone',
    ],
    durationMin: 100,
  ),
];

const List<DrillScenario> medicalDrills = [
  DrillScenario(
    title: 'Adult CPR Certification',
    department: 'Medical & Health Services',
    location: 'Apollo Hospital, Greams Road',
    authorisedPerson: 'Dr. A. Subramanian (MBBS, MD)',
    objective:
        'Perform continuous chest compressions and rescue breaths for 2 minutes on a manikin.',
    missionBrief:
        '❤️ MISSION BRIEF\n\nA patient has collapsed with no pulse and is not breathing. You are the first responder at the scene before the ambulance arrives.\n\nYour mission: Perform 2 continuous minutes of adult CPR (30:2 cycle at 100-120 compressions/min) on a certified manikin under medical supervision.\n\n⚠️ Equipment: CPR manikin, AED trainer, gloves\n📍 Report to: Apollo Hospital, Greams Road\n👮 Supervisor: Dr. A. Subramanian\n\nSubmit a photo performing CPR with the doctor as completion proof.',
    steps: [
      'Check scene safety and call for help',
      'Check responsiveness — tap and shout',
      'Call 108 or delegate someone to call',
      'Begin 30 chest compressions at 100-120/min',
      'Open airway — head-tilt chin-lift',
      'Give 2 rescue breaths, each 1 second',
      'Continue 30:2 cycle until AED arrives',
    ],
    durationMin: 90,
  ),
  DrillScenario(
    title: 'Wound Care & Bandaging',
    department: 'Medical & Health Services',
    location: 'Primary Health Centre, Villivakkam',
    authorisedPerson: 'Nurse In-charge Sister Meenakshi',
    objective:
        'Clean, dress, and bandage three types of wounds correctly without contamination.',
    missionBrief:
        '🩹 MISSION BRIEF\n\nDisaster aftermath has produced multiple walking wounded with cuts and abrasions. Proper wound care is critical to prevent infection.\n\nYour mission: Clean, dress, and apply correct bandages to three wound types — abrasion, laceration, and puncture — without contamination at a supervised PHC.\n\n⚠️ Equipment: Saline, sterile dressings, roller bandages, forceps\n📍 Report to: PHC Villivakkam\n👮 Supervisor: Sister Meenakshi\n\nSubmit a photo with completed bandage work and supervisor as proof.',
    steps: [
      'Wash hands or don gloves',
      'Irrigate wound with clean saline',
      'Remove visible debris using sterile forceps',
      'Apply non-stick dressing pad',
      'Secure with roller bandage using figure-8 technique',
      'Check distal circulation after bandaging',
    ],
    durationMin: 45,
  ),
  DrillScenario(
    title: 'Choking & Heimlich Maneuver',
    department: 'Medical & Health Services',
    location: 'GH Chennai, Park Town',
    authorisedPerson: 'Emergency Dr. P. Ramesh',
    objective:
        'Identify choking and perform Heimlich maneuver on adult and infant manikins.',
    missionBrief:
        '🫁 MISSION BRIEF\n\nA disaster relief camp is distributing food when a volunteer begins choking. You are the only first responder nearby.\n\nYour mission: Identify choking signs, correctly perform the Heimlich maneuver on adult and infant manikins under emergency doctor supervision.\n\n⚠️ Equipment: Adult + infant choking manikins\n📍 Report to: GH Chennai, Park Town\n👮 Supervisor: Dr. P. Ramesh\n\nSubmit a photo performing the maneuver on the manikin as completion proof.',
    steps: [
      'Ask "Are you choking?" — if no response, act',
      'For adult: give 5 back blows between shoulder blades',
      'Follow with 5 abdominal thrusts',
      'Repeat until object expelled or person collapses',
      'For infant: face-down 5 back blows + 5 chest thrusts',
      'After object removed, check airway before leaving',
    ],
    durationMin: 40,
  ),
  DrillScenario(
    title: 'AED Usage in Cardiac Arrest',
    department: 'Medical & Health Services',
    location: 'MIOT International, Manapakkam',
    authorisedPerson: 'Cardiologist Dr. N. Anand',
    objective:
        'Operate an AED on an unconscious cardiac arrest victim within 3 minutes of collapse.',
    missionBrief:
        '⚡ MISSION BRIEF\n\nAn earthquake survivor has gone into cardiac arrest at the rescue perimeter. An AED is available. The cardiologist is guiding remotely by radio.\n\nYour mission: Begin CPR immediately, retrieve and operate the AED, attach pads correctly, and deliver shock within 3 minutes of collapse time.\n\n⚠️ Equipment: AED trainer unit, CPR manikin with ECG\n📍 Report to: MIOT International, Manapakkam\n👮 Supervisor: Dr. N. Anand\n\nSubmit a photo with the AED pads attached correctly as completion proof.',
    steps: [
      'Confirm unconsciousness and no breathing',
      'Start CPR while assistant retrieves AED',
      'Turn on AED — follow voice prompts',
      'Attach pads: upper right chest + lower left rib',
      'Clear patient — press analyse',
      'Deliver shock if advised, resume CPR immediately',
    ],
    durationMin: 60,
  ),
  DrillScenario(
    title: 'Fracture Splinting & Immobilisation',
    department: 'Medical & Health Services',
    location: 'Govt Orthopaedic Hospital, Kilpauk',
    authorisedPerson: 'Orthopaedic Surgeon Dr. T. Vijay',
    objective:
        'Immobilise a suspected lower leg fracture using improvised and SAM splints.',
    missionBrief:
        '🦴 MISSION BRIEF\n\nA flood victim has a suspected tibia fracture. There are no ambulances available for 30 minutes. You must immobilise the fracture to prevent further injury.\n\nYour mission: Control any bleeding, pad bony prominences, apply SAM splint along the bone length, and check CMS (Circulation, Movement, Sensation) post-splinting.\n\n⚠️ Equipment: SAM splints, triangular bandages, padding\n📍 Report to: Govt Orthopaedic Hospital, Kilpauk\n👮 Supervisor: Dr. T. Vijay\n\nSubmit a photo of the completed splint with doctor as proof.',
    steps: [
      'Do not try to realign bone',
      'Control any bleeding with gentle pressure',
      'Pad all bony prominences before splinting',
      'Position SAM splint along bone length',
      'Secure with triangular bandage ties above and below fracture',
      'Check CMS: Circulation, Movement, Sensation after splinting',
    ],
    durationMin: 50,
  ),
];

const List<DrillScenario> combinedDrills = [
  DrillScenario(
    title: 'Multi-Storey Building Collapse — Integrated Response',
    department: 'Fire + NDRF + Medical + Police',
    location: 'Mock Site, Porur Industrial Area',
    authorisedPerson: 'Incident Commander Col. (Retd) S. Murugesh',
    objective:
        'All departments respond, rescue trapped victims, treat casualties, and restore order within 60 minutes.',
    missionBrief:
        '🏗️ COMBINED MISSION BRIEF\n\nA 6-storey building has partially collapsed in Porur Industrial Area. Reports suggest 12 people are trapped, 3 with critical injuries. Gas leak on floor 2.\n\n🔴 YOUR ROLE: You are part of the integrated response team. Coordinate with Fire (gas leak), NDRF (extraction), and Medical (triage) under Incident Commander Col. Murugesh.\n\n⏰ Time limit: 60 minutes to restore order\n📍 Report to: Mock Site, Porur Industrial Area\n👮 Commander: Col. (Retd) S. Murugesh\n\nAll departments use a COMMON radio channel. Photograph the final inter-agency debrief as completion proof.',
    steps: [
      'Police: secure perimeter and manage crowd',
      'Fire: control gas leak and structural fire',
      'NDRF: locate and extricate trapped persons',
      'Medical: set up triage post at safe distance',
      'All: use common radio channel for coordination',
      'Incident commander logs timeline and resource use',
    ],
    durationMin: 120,
  ),
  DrillScenario(
    title: 'Cyclone Landfall Evacuation Drill',
    department: 'SDRF + Police + Revenue + Medical',
    location: 'Marina Beach Coastal Zone, Chennai',
    authorisedPerson: 'District Collector Representative',
    objective:
        'Evacuate coastal village of 200 simulated residents to cyclone shelter in 90 minutes.',
    missionBrief:
        '🌀 COMBINED MISSION BRIEF\n\nCyclone Vayu is making landfall in 90 minutes with 160 km/h winds. A coastal village of 200 residents near Marina Beach must be fully evacuated.\n\n🔴 YOUR ROLE: You are part of the multi-agency evacuation team. Revenue identifies high-risk households, Police leads the convoy, SDRF handles reluctant residents, Medical stations ambulances at shelters.\n\n⏰ Time limit: 90 minutes\n📍 Start point: Marina Beach Coastal Zone\n👮 Supervisor: District Collector Representative\n\nSubmit a group photo at the shelter with all agency representatives as proof.',
    steps: [
      'Revenue: identify high-risk households on map',
      'Police: lead road convoy of buses',
      'SDRF: handle reluctant/mobility-impaired residents',
      'Medical: station ambulance at each shelter',
      'All departments check-in at shelter with count',
      'Conduct post-drill debrief and identify gaps',
    ],
    durationMin: 90,
  ),
  DrillScenario(
    title: 'Industrial Chemical Explosion Response',
    department: 'Fire HazMat + NDRF + Medical + Police',
    location: 'Manali Industrial Corridor',
    authorisedPerson: 'Fire Officer HazMat Division, TNFRS',
    objective:
        'Simultaneously manage fire, chemical hazard, mass casualties and public panic.',
    missionBrief:
        '☣️ COMBINED MISSION BRIEF\n\nAn explosion at a chemical plant in the Manali Corridor has resulted in multiple secondary fires, a chlorine spill, and 15 casualties. Public panic is escalating.\n\n🔴 YOUR ROLE: Integrated HazMat + rescue operation. Police blocks roads (500m exclusion), Fire suppresses secondary fires, HazMat neutralises the spill, NDRF searches for trapped workers, Medical runs decontamination showers.\n\n📡 Media liaison releases verified updates every 30 minutes.\n📍 Report to: Manali Industrial Corridor\n\nSubmit a photo of the decon shower setup as completion proof.',
    steps: [
      'Police: block access roads and establish 500m exclusion zone',
      'Fire: extinguish secondary fires, prevent spread to adjacent tanks',
      'HazMat team: identify chemical, neutralise spill',
      'NDRF: search building for trapped workers',
      'Medical: set up decon shower + 3-zone triage',
      'Media liaison officer: release verified info every 30 minutes',
    ],
    durationMin: 150,
  ),
  DrillScenario(
    title: 'Flood Relief — Search, Rescue & Medical Aid',
    department: 'NDRF + SDRF + Medical + Volunteers',
    location: 'Flood-Simulated Zone, Adyar River Bank',
    authorisedPerson: 'NDRF Team Commander Lt. R. Krishnan',
    objective:
        'Locate, rescue, and medically stabilise 10 flood victims across 5 locations within 2 hours.',
    missionBrief:
        '🌊 COMBINED MISSION BRIEF\n\nHeavy rains have caused the Adyar River to overflow, isolating 10 residents across 5 clusters near the bank. Boat and aerial mapping are required.\n\n🔴 YOUR ROLE: Multi-team flood rescue. Aerial mapping identifies clusters, boat teams deploy in pairs, volunteers receive evacuees at the shore, Medical triages and refers critical cases, Relief team distributes supplies.\n\n⏰ Time limit: 2 hours\n📍 Report to: Adyar River Bank Simulation Zone\n👮 Commander: Lt. R. Krishnan\n\nSubmit a photo of shore rescue operations as completion proof.',
    steps: [
      'Aerial mapping team identifies isolated clusters',
      'Boat teams deploy in pairs to each cluster',
      'Volunteers receive victims at shore landing point',
      'Medical team: triage, treat, refer critical cases',
      'Relief team: provide food, water, warm clothing',
      'Document all rescued persons with ID details',
    ],
    durationMin: 120,
  ),
  DrillScenario(
    title: 'Earthquake Aftermath — Full City Simulation',
    department: 'All Emergency Services + Army',
    location: 'NDMA Training Campus, Delhi (Simulation)',
    authorisedPerson: 'National Crisis Management Trainer',
    objective:
        'Simulate 72-hour response to a magnitude 7.0 earthquake with 500 simulated casualties.',
    missionBrief:
        '🌍 COMBINED MISSION BRIEF\n\nA magnitude 7.0 earthquake has struck, leaving 500 simulated casualties, multiple collapsed structures, and disrupted power/water supply across the city.\n\n🔴 YOUR ROLE: You are part of the 72-hour response team rotating across all services. Hours 0-6: Search & rescue. Hours 6-24: Field hospitals. Hours 24-48: Restore utilities. Hours 48-72: Displaced population management.\n\n📍 Report to: NDMA Training Campus\n👮 Supervisor: National Crisis Management Trainer\n\nSubmit a photo from the after-action review meeting as completion proof.',
    steps: [
      'Hour 0-6: Search & rescue from collapsed structures',
      'Hour 6-24: Set up 3 field hospitals with 50-bed capacity each',
      'Hour 24-48: Restore water/power to critical facilities',
      'Hour 48-72: Manage displaced population in camps',
      'Continuous: inter-agency communication via EOC',
      'Final: after action review with all department heads',
    ],
    durationMin: 180,
  ),
  DrillScenario(
    title: 'Mass Casualty Incident — Stadium Event',
    department: 'Police + Medical + Fire + SDRF',
    location: 'CMBT Stadium, Arumbakkam',
    authorisedPerson: 'Event Safety Director + DCP Operations',
    objective:
        'Manage crowd stampede with 100 simulated casualties including cardiac arrests.',
    missionBrief:
        '🏟️ COMBINED MISSION BRIEF\n\nA crowd stampede at CMBT Stadium has resulted in 100 simulated casualties, including several cardiac arrests. The crowd is still panicking and exits are partially blocked.\n\n🔴 YOUR ROLE: Multi-agency crowd management and medical response. Police activates crowd control, Fire ensures exits are clear, Medical teams positioned at 4 corners, SDRF guides crowd to safe zones, helicopter LZ marked on pitch.\n\n📍 Report to: CMBT Stadium, Arumbakkam\n👮 Supervisors: Event Safety Director + DCP Operations\n\nSubmit a photo of the triage post inside the stadium as completion proof.',
    steps: [
      'Police: activate crowd control — close entry gates, open exits',
      'Fire: ensure all emergency exits are unobstructed',
      'Medical teams pre-positioned at 4 corners of ground',
      'SDRF volunteers guide crowd to safe zones in calm voice',
      'Triage post inside stadium — no external transfer until stable',
      'Helicopter landing zone marked on pitch for critical cases',
    ],
    durationMin: 90,
  ),
  DrillScenario(
    title: 'Tsunami Early Warning Response Drill',
    department: 'Coast Guard + NDRF + Police + Medical',
    location: 'East Coast Road, Mahabalipuram',
    authorisedPerson: 'District Emergency Operations Centre',
    objective:
        'Evacuate entire coastal belt 5km inland within 20 minutes of warning siren.',
    missionBrief:
        '🌊 COMBINED MISSION BRIEF\n\nINCOIS has issued a tsunami warning for the Tamil Nadu coast. The entire coastal belt up to 5km must be evacuated within 20 minutes of the siren activation.\n\n🔴 YOUR ROLE: Coast Guard recalls fishing boats, Police activates PA systems, NDRF deploys to vulnerable pockets, all roads converted to one-way outbound, Medical mobile units follow the convoy.\n\n⏰ Time limit: 20 minutes evacuation\n📍 Report to: East Coast Road, Mahabalipuram\n👮 Supervisor: District EOC\n\nSubmit a photo at the inland checkpoint with evacuation count as completion proof.',
    steps: [
      'INCOIS issues tsunami alert — siren activation',
      'Police: activate vehicle-mounted PA system',
      'Coast Guard: recall all fishing boats by radio',
      'NDRF: deploy to known vulnerable pockets',
      'All roads converted to one-way outbound flow',
      'Inland checkpoints account for incoming evacuees',
      'Medical: mobile units follow evacuation convoy',
    ],
    durationMin: 60,
  ),
];

// ─────────────────────────────────────────────
// TRAINING BLOCKS DATA — ALL UNLOCKED
// ─────────────────────────────────────────────

final List<TrainingBlock> trainingBlocks = [
  TrainingBlock(
    id: 'army',
    title: 'ARMY CORPS',
    subtitle: 'Elite Volunteer Force',
    description:
        'Reserved for heroes who complete all levels AND have participated in a real rescue operation.',
    icon: Icons.military_tech_rounded,
    color: const Color(0xFF1A1A2E),
    lightColor: const Color(0xFF2D2D4A),
    xpReward: 5000,
    level: 9,
    status: BlockStatus.inProgress,
    progress: 0.1,
    isArmy: true,
    tier: BlockTier.army,
    blockType: 'army',
    missions: [],
  ),
  TrainingBlock(
    id: 'combined_drills',
    title: 'COMBINED DRILLS',
    subtitle: 'Gold Level · All Departments',
    description:
        'Multi-agency crisis drills. All departments — fire, rescue, medical — work as one.',
    icon: Icons.hub_rounded,
    color: const Color(0xFFC79000),
    lightColor: const Color(0xFFFFFDE7),
    xpReward: 2000,
    level: 8,
    status: BlockStatus.inProgress,
    progress: 0.0,
    tier: BlockTier.gold,
    blockType: 'combined',
  ),
  TrainingBlock(
    id: 'drill',
    title: 'DEPARTMENT DRILLS',
    subtitle: 'Silver Level · On-Ground Practice',
    description:
        'Choose a department — Fire, Medical, or Rescue — then train at real govt facilities.',
    icon: Icons.directions_run_rounded,
    color: const Color(0xFF607D8B),
    lightColor: const Color(0xFFECEFF1),
    xpReward: 1200,
    level: 7,
    status: BlockStatus.inProgress,
    progress: 0.1,
    tier: BlockTier.silver,
    blockType: 'drill',
  ),
  TrainingBlock(
    id: 'rescue',
    title: 'RESCUE TEAM',
    subtitle: 'Silver Level · Disaster Rescue',
    description:
        'Partner with NDRF and SDRF for hands-on flood, collapse, and night rescue missions.',
    icon: Icons.flood_rounded,
    color: const Color(0xFF2E6B4F),
    lightColor: const Color(0xFFE8F5E9),
    xpReward: 1000,
    level: 6,
    status: BlockStatus.inProgress,
    progress: 0.0,
    tier: BlockTier.silver,
    blockType: 'rescue',
    missions: [
      TrainingMission(
        title: 'Flood Water Rescue with Boat',
        type: 'practical',
        xp: 200,
        durationMin: 60,
      ),
      TrainingMission(
        title: 'Rope Rescue from Height',
        type: 'practical',
        xp: 220,
        durationMin: 90,
      ),
      TrainingMission(
        title: 'Collapsed Structure Victim Search',
        type: 'practical',
        xp: 250,
        durationMin: 120,
      ),
      TrainingMission(
        title: 'Swiftwater Swimmer Rescue',
        type: 'practical',
        xp: 200,
        durationMin: 75,
      ),
      TrainingMission(
        title: 'Mass Casualty Triage Setup',
        type: 'practical',
        xp: 180,
        durationMin: 90,
      ),
      TrainingMission(
        title: 'Night Search Operation',
        type: 'practical',
        xp: 160,
        durationMin: 80,
      ),
      TrainingMission(
        title: 'Chemical Spill Rescue Protocol',
        type: 'practical',
        xp: 230,
        durationMin: 100,
      ),
      TrainingMission(
        title: 'Completion Certificate from NDRF/SDRF',
        type: 'certificate',
        xp: 500,
        durationMin: 0,
      ),
    ],
  ),
  TrainingBlock(
    id: 'fire',
    title: 'FIRE DEPARTMENT',
    subtitle: 'Silver Level · Fire Safety',
    description:
        'Live drills at your local fire station. Extinguisher handling, hose operation, evacuation leading.',
    icon: Icons.local_fire_department_rounded,
    color: const Color(0xFFB84A00),
    lightColor: const Color(0xFFFFF3E0),
    xpReward: 800,
    level: 5,
    status: BlockStatus.inProgress,
    progress: 0.15,
    tier: BlockTier.silver,
    blockType: 'fire',
    missions: [
      TrainingMission(
        title: 'Kitchen Fire Containment',
        type: 'practical',
        xp: 150,
        durationMin: 30,
      ),
      TrainingMission(
        title: 'High-Rise Evacuation Lead',
        type: 'practical',
        xp: 180,
        durationMin: 40,
      ),
      TrainingMission(
        title: 'Hose Operation at Live Site',
        type: 'practical',
        xp: 160,
        durationMin: 45,
      ),
      TrainingMission(
        title: 'Search & Rescue in Smoke-Filled Corridor',
        type: 'practical',
        xp: 200,
        durationMin: 50,
      ),
      TrainingMission(
        title: 'Electrical Fire Safety Protocol',
        type: 'practical',
        xp: 140,
        durationMin: 35,
      ),
      TrainingMission(
        title: 'Casualty Extraction from Burning Vehicle',
        type: 'practical',
        xp: 210,
        durationMin: 60,
      ),
      TrainingMission(
        title: 'Mass Evacuation Coordination',
        type: 'practical',
        xp: 180,
        durationMin: 70,
      ),
      TrainingMission(
        title: 'Completion Certificate from Fire Station',
        type: 'certificate',
        xp: 400,
        durationMin: 0,
      ),
    ],
  ),
  TrainingBlock(
    id: 'medical',
    title: 'MEDICAL AID',
    subtitle: 'Bronze Level · First Aid & BLS',
    description:
        'Life-saving skills — CPR, wound care, fracture management, and AED operation at certified hospitals.',
    icon: Icons.local_hospital_rounded,
    color: const Color(0xFFD94035),
    lightColor: const Color(0xFFFFEBEB),
    xpReward: 600,
    level: 4,
    status: BlockStatus.inProgress,
    progress: 0.4,
    tier: BlockTier.bronze,
    blockType: 'medical',
    missions: [
      TrainingMission(
        title: 'Adult CPR Certification',
        type: 'practical',
        xp: 180,
        durationMin: 90,
      ),
      TrainingMission(
        title: 'Wound Care & Bandaging',
        type: 'practical',
        xp: 120,
        durationMin: 45,
      ),
      TrainingMission(
        title: 'Choking & Heimlich Maneuver',
        type: 'practical',
        xp: 100,
        durationMin: 40,
      ),
      TrainingMission(
        title: 'AED Usage in Cardiac Arrest',
        type: 'practical',
        xp: 160,
        durationMin: 60,
      ),
      TrainingMission(
        title: 'Fracture Splinting & Immobilisation',
        type: 'practical',
        xp: 130,
        durationMin: 50,
      ),
      TrainingMission(
        title: 'Completion Certificate from Hospital',
        type: 'certificate',
        xp: 300,
        durationMin: 0,
      ),
    ],
  ),
  TrainingBlock(
    id: 'puzzle',
    title: 'CRISIS PUZZLES',
    subtitle: 'Bronze Level · Decision Making',
    description:
        '10 real-world crisis scenarios. Choose the correct action. Test your emergency judgment.',
    icon: Icons.extension_rounded,
    color: const Color(0xFF6A3FA0),
    lightColor: const Color(0xFFF3E8FF),
    xpReward: 400,
    level: 3,
    status: BlockStatus.inProgress,
    progress: 0.6,
    tier: BlockTier.bronze,
    blockType: 'puzzle',
    missions: [
      TrainingMission(
        title: 'Flood Emergency Decision',
        type: 'puzzle',
        xp: 40,
        durationMin: 3,
        completed: true,
        score: '100/100',
      ),
      TrainingMission(
        title: 'Fire Victim Response',
        type: 'puzzle',
        xp: 40,
        durationMin: 3,
        completed: true,
        score: '100/100',
      ),
      TrainingMission(
        title: 'Earthquake Protocol',
        type: 'puzzle',
        xp: 40,
        durationMin: 3,
        completed: true,
        score: '80/100',
      ),
      TrainingMission(
        title: 'Water Safety Post-Disaster',
        type: 'puzzle',
        xp: 40,
        durationMin: 3,
      ),
      TrainingMission(
        title: 'Triage Tag System',
        type: 'puzzle',
        xp: 40,
        durationMin: 3,
      ),
      TrainingMission(
        title: 'Evacuation Protocol',
        type: 'puzzle',
        xp: 40,
        durationMin: 3,
      ),
      TrainingMission(
        title: 'Distress Signal Knowledge',
        type: 'puzzle',
        xp: 40,
        durationMin: 3,
      ),
      TrainingMission(
        title: 'Bleeding Control',
        type: 'puzzle',
        xp: 40,
        durationMin: 3,
      ),
      TrainingMission(
        title: 'Gas Leak Safety',
        type: 'puzzle',
        xp: 40,
        durationMin: 3,
      ),
      TrainingMission(
        title: 'BLS Order',
        type: 'puzzle',
        xp: 40,
        durationMin: 3,
      ),
    ],
  ),
  TrainingBlock(
    id: 'survival',
    title: 'SURVIVAL SKILLS',
    subtitle: 'Bronze Level · Field Survival',
    description:
        'Water, shelter, signals, kits — master the basics of staying alive in a crisis.',
    icon: Icons.park,
    color: const Color(0xFF2A7ABD),
    lightColor: const Color(0xFFE3F2FD),
    xpReward: 350,
    level: 2,
    status: BlockStatus.inProgress,
    progress: 0.75,
    tier: BlockTier.bronze,
    blockType: 'survival',
    missions: [
      TrainingMission(
        title: 'Water Purification Methods',
        type: 'video',
        xp: 30,
        durationMin: 3,
        completed: true,
        score: '100/100',
      ),
      TrainingMission(
        title: 'Building a Shelter',
        type: 'video',
        xp: 30,
        durationMin: 4,
        completed: true,
        score: '100/100',
      ),
      TrainingMission(
        title: 'Distress Signals',
        type: 'video',
        xp: 30,
        durationMin: 2,
        completed: true,
        score: '100/100',
      ),
      TrainingMission(
        title: 'Emergency Kit Packing',
        type: 'video',
        xp: 30,
        durationMin: 3,
        completed: true,
        score: '100/100',
      ),
      TrainingMission(
        title: 'Food Safety After Disaster',
        type: 'video',
        xp: 30,
        durationMin: 2,
      ),
      TrainingMission(
        title: 'Stress Management in Crisis',
        type: 'video',
        xp: 30,
        durationMin: 3,
      ),
    ],
  ),
  TrainingBlock(
    id: 'basic',
    title: 'BASIC TRAINING',
    subtitle: 'Bronze Level · Disaster Awareness',
    description:
        'Your first step. Learn the types of disasters, warning signs, and your role as a volunteer.',
    icon: Icons.school_rounded,
    color: const Color(0xFF8B5E2E),
    lightColor: const Color(0xFFFFF8F0),
    xpReward: 200,
    level: 1,
    status: BlockStatus.completed,
    progress: 1.0,
    tier: BlockTier.bronze,
    blockType: 'basic',
    missions: [
      TrainingMission(
        title: 'Types of Disasters Explained',
        type: 'video',
        xp: 20,
        durationMin: 5,
        completed: true,
        score: '100/100',
      ),
      TrainingMission(
        title: 'Flood Warning Signs & Safety',
        type: 'video',
        xp: 20,
        durationMin: 3,
        completed: true,
        score: '100/100',
      ),
      TrainingMission(
        title: 'Earthquake — Before, During & After',
        type: 'video',
        xp: 20,
        durationMin: 5,
        completed: true,
        score: '100/100',
      ),
      TrainingMission(
        title: 'Fire Safety at Home & Work',
        type: 'video',
        xp: 20,
        durationMin: 4,
        completed: true,
        score: '95/100',
      ),
      TrainingMission(
        title: 'Cyclone Preparedness Guide',
        type: 'video',
        xp: 20,
        durationMin: 4,
        completed: true,
        score: '90/100',
      ),
      TrainingMission(
        title: 'Community Alert Systems',
        type: 'video',
        xp: 20,
        durationMin: 3,
        completed: true,
        score: '88/100',
      ),
      TrainingMission(
        title: 'Emergency Signal Recognition',
        type: 'video',
        xp: 20,
        durationMin: 3,
        completed: true,
        score: '92/100',
      ),
      TrainingMission(
        title: 'Your Role as a Volunteer',
        type: 'video',
        xp: 20,
        durationMin: 5,
        completed: true,
        score: '100/100',
      ),
    ],
  ),
];

// ─────────────────────────────────────────────
// ANIMATED VIDEO PLAYER (Card — tappable)
// ─────────────────────────────────────────────

class AnimatedVideoPlayer extends StatefulWidget {
  final Map<String, dynamic> video;
  final Color color;
  final bool initialCompleted;
  final VoidCallback? onCompleted;

  const AnimatedVideoPlayer({
    super.key,
    required this.video,
    required this.color,
    this.initialCompleted = false,
    this.onCompleted,
  });

  @override
  State<AnimatedVideoPlayer> createState() => _AnimatedVideoPlayerState();
}

class _AnimatedVideoPlayerState extends State<AnimatedVideoPlayer>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _isCompleted = widget.initialCompleted;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _openPlayer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VideoPlayerModal(
        video: widget.video,
        color: widget.color,
        initialCompleted: _isCompleted,
        onCompleted: () {
          setState(() => _isCompleted = true);
          widget.onCompleted?.call();
        },
        onRestart: () {
          setState(() => _isCompleted = false);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openPlayer,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isCompleted
                ? const Color(0xFF3D7A3A).withOpacity(0.3)
                : widget.color.withOpacity(0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Thumbnail area
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return Container(
                    height: 160,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        // Background gradient
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.color.withOpacity(0.25),
                                widget.color.withOpacity(0.08),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                        // Animated wave lines
                        CustomPaint(
                          size: const Size(double.infinity, 160),
                          painter: _WavePainter(
                            progress: _pulseController.value,
                            color: widget.color,
                          ),
                        ),
                        // Completed overlay
                        if (_isCompleted)
                          Container(
                            color: const Color(0xFF3D7A3A).withOpacity(0.12),
                          ),
                        // Progress bar at bottom
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            value: _isCompleted ? 1.0 : 0.0,
                            backgroundColor: Colors.white.withOpacity(0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _isCompleted
                                  ? const Color(0xFF3D7A3A)
                                  : widget.color,
                            ),
                            minHeight: 4,
                          ),
                        ),
                        // Center play/done button
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: _isCompleted
                                      ? const Color(0xFF3D7A3A)
                                      : widget.color,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (_isCompleted
                                                  ? const Color(0xFF3D7A3A)
                                                  : widget.color)
                                              .withOpacity(0.4),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _isCompleted
                                      ? Icons.check_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isCompleted ? '✅ Completed' : 'Tap to Watch',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _isCompleted
                                      ? const Color(0xFF3D7A3A)
                                      : widget.color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Duration badge
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.video['duration'] as String,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        // Icon badge
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: widget.color.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              widget.video['icon'] as IconData,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Bottom info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.video['title'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.video['tag'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isCompleted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3D7A3A).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF3D7A3A).withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF3D7A3A),
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF3D7A3A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: widget.color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Watch',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// VIDEO PLAYER MODAL (Full-featured)
// ─────────────────────────────────────────────

class VideoPlayerModal extends StatefulWidget {
  final Map<String, dynamic> video;
  final Color color;
  final bool initialCompleted;
  final VoidCallback? onCompleted;
  final VoidCallback? onRestart;

  const VideoPlayerModal({
    super.key,
    required this.video,
    required this.color,
    this.initialCompleted = false,
    this.onCompleted,
    this.onRestart,
  });

  @override
  State<VideoPlayerModal> createState() => _VideoPlayerModalState();
}

class _VideoPlayerModalState extends State<VideoPlayerModal>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late AnimationController _waveController;
  bool _isPlaying = false;
  bool _isCompleted = false;
  int _currentSceneIndex = 0;

  int get _totalSeconds {
    final dur = widget.video['duration'] as String;
    final parts = dur.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  List<Map<String, dynamic>> get _scenes =>
      (widget.video['scenes'] as List<Map<String, dynamic>>?) ?? [];

  List<String> get _keyPoints =>
      (widget.video['keyPoints'] as List<String>?) ?? [];

  @override
  void initState() {
    super.initState();
    _isCompleted = widget.initialCompleted;
    _progressController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _totalSeconds),
    );
    _progressController.addListener(_onProgressUpdate);
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    if (_isCompleted) _progressController.value = 1.0;
  }

  void _onProgressUpdate() {
    if (!mounted) return;
    final elapsed = _progressController.value * _totalSeconds;
    if (_scenes.isNotEmpty) {
      int newScene = 0;
      for (int i = 0; i < _scenes.length; i++) {
        if (elapsed >= (_scenes[i]['timeSecs'] as int)) newScene = i;
      }
      if (newScene != _currentSceneIndex) {
        setState(() => _currentSceneIndex = newScene);
      }
    }
    if (_progressController.value >= 1.0) {
      setState(() {
        _isPlaying = false;
        _isCompleted = true;
      });
      widget.onCompleted?.call();
    }
  }

  void _togglePlay() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying)
      _progressController.forward();
    else
      _progressController.stop();
  }

  void _restart() {
    setState(() {
      _isPlaying = false;
      _isCompleted = false;
      _currentSceneIndex = 0;
      _progressController.reset();
    });
    widget.onRestart?.call();
  }

  void _seekToScene(int index) {
    final t = (_scenes[index]['timeSecs'] as int) / _totalSeconds;
    _progressController.value = t.clamp(0.0, 1.0);
    setState(() => _currentSceneIndex = index);
    if (!_isPlaying && !_isCompleted) {
      setState(() => _isPlaying = true);
      _progressController.forward();
    }
  }

  String get _currentTimeStr {
    final secs = (_progressController.value * _totalSeconds).toInt();
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString()}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _progressController.removeListener(_onProgressUpdate);
    _progressController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final title = widget.video['title'] as String;
    final tag = widget.video['tag'] as String;
    final duration = widget.video['duration'] as String;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D1420),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // ── VIDEO CANVAS ──
              AspectRatio(
                aspectRatio: 16 / 9,
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _progressController,
                    _waveController,
                  ]),
                  builder: (context, _) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            color.withOpacity(0.3),
                            const Color(0xFF060A12),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        children: [
                          if (_isPlaying)
                            CustomPaint(
                              size: Size.infinite,
                              painter: _VideoWavePainter(
                                progress: _waveController.value,
                                playProgress: _progressController.value,
                                color: color,
                              ),
                            ),
                          if (_isCompleted)
                            Container(color: Colors.black.withOpacity(0.4)),
                          // Scene label
                          if (_scenes.isNotEmpty)
                            Positioned(
                              top: 10,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.55),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.15),
                                  ),
                                ),
                                child: Text(
                                  (_scenes[_currentSceneIndex]['title']
                                          as String)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          // Center button
                          Center(
                            child: GestureDetector(
                              onTap: _isCompleted ? null : _togglePlay,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: _isCompleted
                                      ? const Color(0xFF3D7A3A)
                                      : Colors.white.withOpacity(0.92),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _isCompleted
                                      ? Icons.check_rounded
                                      : (_isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded),
                                  color: _isCompleted
                                      ? Colors.white
                                      : const Color(0xFF111111),
                                  size: 30,
                                ),
                              ),
                            ),
                          ),
                          // Bottom controls
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                20,
                                14,
                                10,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.8),
                                  ],
                                ),
                              ),
                              child: Column(
                                children: [
                                  // Progress bar
                                  Container(
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: _progressController.value,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: _isCompleted
                                            ? null
                                            : _togglePlay,
                                        child: Icon(
                                          _isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      GestureDetector(
                                        onTap: _restart,
                                        child: const Icon(
                                          Icons.replay_rounded,
                                          color: Colors.white70,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '$_currentTimeStr / $duration',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // ── SCROLLABLE INFO ──
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tag + duration
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: color.withOpacity(0.4)),
                            ),
                            child: Text(
                              tag.toUpperCase(),
                              style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            duration,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      // ── ACTION BUTTONS ──
                      const SizedBox(height: 14),
                      if (_isCompleted)
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3D7A3A),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Marked as Done ✅',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _restart,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.replay_rounded,
                                      color: Colors.white70,
                                      size: 16,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Restart',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        GestureDetector(
                          onTap: _togglePlay,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isPlaying ? 'Pause' : 'Play',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // ── CHAPTER SELECT ──
                      if (_scenes.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'CHAPTER SELECT',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _scenes.asMap().entries.map((e) {
                            final isActive = e.key == _currentSceneIndex;
                            final sceneColor = e.value['color'] as Color;
                            return GestureDetector(
                              onTap: () => _seekToScene(e.key),
                              child: Container(
                                width:
                                    (MediaQuery.of(context).size.width - 52) /
                                    2,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? sceneColor.withOpacity(0.18)
                                      : Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isActive
                                        ? sceneColor.withOpacity(0.6)
                                        : Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.value['time'] as String,
                                      style: TextStyle(
                                        color: sceneColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      e.value['title'] as String,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      // ── KEY LEARNING POINTS ──
                      if (_keyPoints.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.07),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'KEY LEARNING POINTS',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ..._keyPoints.map(
                                (kp) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(
                                          top: 5,
                                          right: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          kp,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VideoWavePainter extends CustomPainter {
  final double progress;
  final double playProgress;
  final Color color;
  _VideoWavePainter({
    required this.progress,
    required this.playProgress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 5; i++) {
      final paint = Paint()
        ..color = color.withOpacity(0.06 + i * 0.03)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final path = Path();
      path.moveTo(0, size.height * 0.5);
      for (double x = 0; x <= size.width; x += 2) {
        final y =
            size.height * 0.5 +
            math.sin(
                  (x / size.width * 4 * math.pi) +
                      (progress * math.pi * 2) +
                      i * 0.8,
                ) *
                (18 - i * 2);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
    final dotPaint = Paint()..color = color.withOpacity(0.25);
    for (int i = 0; i < 30; i++) {
      final px = (math.sin(i * 137.5) * 0.5 + 0.5) * size.width;
      final py = ((i * 0.016 + playProgress * 0.4) % 1.0) * size.height;
      canvas.drawCircle(Offset(px, py), 1.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_VideoWavePainter old) =>
      old.progress != progress || old.playProgress != playProgress;
}

class _WavePainter extends CustomPainter {
  final double progress;
  final Color color;
  _WavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (int i = 0; i < 4; i++) {
      final path = Path();
      final offset = i * 30.0;
      path.moveTo(0, size.height * 0.5);
      for (double x = 0; x <= size.width; x += 1) {
        final y =
            size.height * 0.5 +
            math.sin(
                  (x / size.width * 4 * math.pi) +
                      (progress * math.pi * 2) +
                      offset,
                ) *
                (20 - i * 4);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint..color = color.withOpacity(0.1 + i * 0.04));
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────
// MISSION START SCREEN (for drills/medical/fire/rescue/combined)
// ─────────────────────────────────────────────

class MissionStartScreen extends StatefulWidget {
  final DrillScenario drill;
  final Color color;
  final String blockType;

  const MissionStartScreen({
    super.key,
    required this.drill,
    required this.color,
    required this.blockType,
  });

  @override
  State<MissionStartScreen> createState() => _MissionStartScreenState();
}

class _MissionStartScreenState extends State<MissionStartScreen> {
  bool _missionStarted = false;
  bool _missionCompleted = false;
  bool _photoSubmitted = false;
  int _currentStep = 0;
  Timer? _timer;
  int _elapsedSeconds = 0;
  String? _aiDebrief;
  bool _loadingDebrief = false;

  void _startMission() {
    setState(() => _missionStarted = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _completeMission() {
    _timer?.cancel();
    setState(() => _missionCompleted = true);
    _fetchAIDebrief();
    // Feature 2 — trigger post-trauma mental health check for high/critical missions
    TraumaCheckTrigger.onMissionCompleted(
      context,
      widget.drill,
      widget.blockType,
      _elapsedSeconds,
    );
  }

  Future<void> _fetchAIDebrief() async {
    setState(() => _loadingDebrief = true);
    final prompt =
        'The volunteer just completed the drill: "${widget.drill.title}" in ${_elapsedTime} (target: ${widget.drill.durationMin} min). '
        'Steps completed: ${widget.drill.steps.join(", ")}. '
        'Give a concise AI mission debrief: (1) Overall performance assessment, (2) One thing done well, (3) One area to improve, (4) Skill rating out of 10. Keep it under 100 words.';
    final result = await GeminiService.generateContent(prompt, 'drill');
    if (mounted)
      setState(() {
        _aiDebrief = result;
        _loadingDebrief = false;
      });
  }

  void _submitPhoto() {
    // Simulate photo submission
    setState(() => _photoSubmitted = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 8),
            const Text('Completion photo submitted! +XP earned'),
          ],
        ),
        backgroundColor: const Color(0xFF3D7A3A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String get _elapsedTime {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2EDE8),
      appBar: AppBar(
        backgroundColor: widget.color,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.drill.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (_missionStarted && !_missionCompleted)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.timer_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _elapsedTime,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mission Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [widget.color, widget.color.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.drill.department,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            color: Colors.white70,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.drill.durationMin} min',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_missionCompleted)
                    const Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'MISSION COMPLETED!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    )
                  else if (_missionStarted)
                    const Row(
                      children: [
                        Icon(
                          Icons.play_circle_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'MISSION IN PROGRESS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    )
                  else
                    const Row(
                      children: [
                        Icon(Icons.flag_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'READY TO START',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Mission Brief
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: widget.color,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Mission Brief',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: widget.color,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Text(
                    widget.drill.missionBrief.isNotEmpty
                        ? widget.drill.missionBrief
                        : widget.drill.objective,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF444440),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Steps
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mission Steps',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...widget.drill.steps.asMap().entries.map((e) {
                    final done = _missionStarted && e.key < _currentStep;
                    final current = _missionStarted && e.key == _currentStep;
                    return GestureDetector(
                      onTap: _missionStarted && !_missionCompleted
                          ? () => setState(() => _currentStep = e.key + 1)
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: done
                              ? const Color(0xFFE8F5E9)
                              : (current
                                    ? widget.color.withOpacity(0.08)
                                    : const Color(0xFFF8F5F0)),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: done
                                ? const Color(0xFF3D7A3A).withOpacity(0.3)
                                : (current
                                      ? widget.color.withOpacity(0.4)
                                      : Colors.transparent),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: done
                                    ? const Color(0xFF3D7A3A)
                                    : (current
                                          ? widget.color
                                          : const Color(0xFFD0CCC6)),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: done
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      )
                                    : Text(
                                        '${e.key + 1}',
                                        style: TextStyle(
                                          color: current
                                              ? Colors.white
                                              : const Color(0xFF888880),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                e.value,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: done
                                      ? const Color(0xFF3D7A3A)
                                      : (current
                                            ? const Color(0xFF1A1A1A)
                                            : const Color(0xFF666660)),
                                  fontWeight: current
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            if (current && !_missionCompleted)
                              Icon(
                                Icons.touch_app_rounded,
                                color: widget.color,
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Location & Authority
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.color.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        color: widget.color,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.drill.location,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF444440),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.badge_rounded, color: widget.color, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.drill.authorisedPerson,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF444440),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            if (!_missionStarted) ...[
              GestureDetector(
                onTap: _startMission,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'START MISSION',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (!_missionCompleted) ...[
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _timer?.cancel();
                        _missionStarted = false;
                        _currentStep = 0;
                        _elapsedSeconds = 0;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFD94035).withOpacity(0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.stop_rounded,
                              color: Color(0xFFD94035),
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Stop',
                              style: TextStyle(
                                color: Color(0xFFD94035),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _currentStep >= widget.drill.steps.length
                          ? _completeMission
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _currentStep >= widget.drill.steps.length
                              ? const Color(0xFF3D7A3A)
                              : const Color(0xFFD0CCC6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Mark Complete',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_currentStep < widget.drill.steps.length)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Tap each step above to mark it done (${_currentStep}/${widget.drill.steps.length} steps)',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF888880),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ] else ...[
              // Photo submission
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF3D7A3A).withOpacity(0.1),
                      const Color(0xFF3D7A3A).withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF3D7A3A).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.workspace_premium_rounded,
                          color: Color(0xFF3D7A3A),
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Mission Complete!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF3D7A3A),
                            ),
                          ),
                        ),
                        Text(
                          '${_elapsedTime} elapsed',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF888880),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Submit a photo with your authorised supervisor as proof of completion. The supervisor will verify and approve your mission.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF444440),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_photoSubmitted)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3D7A3A).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF3D7A3A),
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Photo Submitted — Pending Approval',
                              style: TextStyle(
                                color: Color(0xFF3D7A3A),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _submitPhoto,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3D7A3A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Upload Completion Photo',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // AI Mission Debrief
            if (_loadingDebrief)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF4285F4),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Gemini AI is generating your mission debrief...',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF4285F4),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_aiDebrief != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE8F0FE), Color(0xFFEEF2FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF4285F4).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFF4285F4),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'AI Mission Debrief',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4285F4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4285F4).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Gemini',
                            style: TextStyle(
                              fontSize: 9,
                              color: Color(0xFF4285F4),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _aiDebrief!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1A1A1A),
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TRAINING SCREEN
// ─────────────────────────────────────────────

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  String? _adaptivePath;
  bool _loadingPath = false;
  int _streakMultiplier = 1;

  @override
  void initState() {
    super.initState();
    _computeStreakMultiplier();
    _fetchAdaptivePath();
  }

  void _computeStreakMultiplier() {
    // Count consecutive completed days from home_screen AppData
    // Streak multiplier: 1x (0-2 days), 2x (3-4 days), 3x (5+ days)
    // Using a fixed streak value from the profile data
    int streak = 5; // default from AppData.volunteerProfile['streak']
    setState(() {
      if (streak >= 5)
        _streakMultiplier = 3;
      else if (streak >= 3)
        _streakMultiplier = 2;
      else
        _streakMultiplier = 1;
    });
  }

  Future<void> _fetchAdaptivePath() async {
    setState(() => _loadingPath = true);
    final completedBlocks = trainingBlocks
        .where((b) => b.status == BlockStatus.completed)
        .map((b) => b.title)
        .join(', ');
    final inProgressBlocks = trainingBlocks
        .where((b) => b.status == BlockStatus.inProgress)
        .map((b) => '${b.title} (${(b.progress * 100).toInt()}%)')
        .join(', ');
    final prompt =
        'A disaster response volunteer has completed: $completedBlocks. '
        'Currently in progress: $inProgressBlocks. '
        'Based on skill gaps and progression, recommend which block to focus on next and why. '
        'Also mention one specific mission within that block to tackle first. '
        'Keep it to 2 sentences max.';
    final result = await GeminiService.generateContent(prompt, 'basic');
    if (mounted)
      setState(() {
        _adaptivePath = result;
        _loadingPath = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2EDE8),
      body: SafeArea(
        child: Column(
          children: [
            _TrainingHeader(streakMultiplier: _streakMultiplier),
            _XPSummaryBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                children: [
                  // ── Adaptive Learning Path Card ──
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4285F4), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4285F4).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'AI Adaptive Learning Path',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            if (_streakMultiplier > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Text(
                                      '🔥',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    Text(
                                      ' ${_streakMultiplier}x XP',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_loadingPath)
                          const Text(
                            'Gemini is analysing your skill gaps...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          )
                        else if (_adaptivePath != null)
                          Text(
                            _adaptivePath!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              height: 1.5,
                            ),
                          ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _fetchAdaptivePath,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.refresh_rounded,
                                color: Colors.white60,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'Refresh recommendation',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _TierLegend(),
                  const SizedBox(height: 16),
                  ...trainingBlocks.map(
                    (block) => _TrainingBlockCard(block: block),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingHeader extends StatelessWidget {
  final int streakMultiplier;
  const _TrainingHeader({this.streakMultiplier = 1});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Training Path',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD94035),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Hero Level 3 · Ravi Kumar',
                    style: TextStyle(fontSize: 13, color: Color(0xFF888880)),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFD94035),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.bolt_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      '680 XP',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (streakMultiplier > 1) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '🔥 ${streakMultiplier}x XP Streak!',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _XPSummaryBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            _StatChip(
              label: 'Completed',
              value: '1',
              color: const Color(0xFF3D7A3A),
            ),
            _Divider(),
            _StatChip(
              label: 'In Progress',
              value: '7',
              color: const Color(0xFFD94035),
            ),
            _Divider(),
            _StatChip(
              label: 'Locked',
              value: '0',
              color: const Color(0xFF888880),
            ),
            _Divider(),
            _StatChip(
              label: 'Total XP',
              value: '10.2K',
              color: const Color(0xFF0D5B8E),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF888880),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: const Color(0xFFE8E4DF));
}

class _TierLegend extends StatelessWidget {
  const _TierLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _LegendChip(
            color: const Color(0xFFC79000),
            label: 'Gold',
            icon: Icons.star_rounded,
          ),
          const SizedBox(width: 10),
          _LegendChip(
            color: const Color(0xFF607D8B),
            label: 'Silver',
            icon: Icons.shield_rounded,
          ),
          const SizedBox(width: 10),
          _LegendChip(
            color: const Color(0xFFB87333),
            label: 'Bronze',
            icon: Icons.military_tech_rounded,
          ),
          const Spacer(),
          const Text(
            'All Unlocked 🔓',
            style: TextStyle(
              fontSize: 10,
              color: Color(0xFF3D7A3A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;
  const _LegendChip({
    required this.color,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// TRAINING BLOCK CARD
// ─────────────────────────────────────────────

class _TrainingBlockCard extends StatelessWidget {
  final TrainingBlock block;
  const _TrainingBlockCard({required this.block});

  Color get _tierAccent {
    switch (block.tier) {
      case BlockTier.gold:
        return const Color(0xFFC79000);
      case BlockTier.silver:
        return const Color(0xFF8A9BAB);
      case BlockTier.bronze:
        return const Color(0xFFB87333);
      case BlockTier.army:
        return Colors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isCompleted = block.status == BlockStatus.completed;
    final bool isInProgress = block.status == BlockStatus.inProgress;

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Column(
        children: [
          if (block.id != 'army')
            _ConnectorLine(
              isUnlocked: true,
              color: isCompleted ? block.color : const Color(0xFFD0CCC6),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isInProgress
                    ? block.color.withOpacity(0.5)
                    : (isCompleted
                          ? block.color.withOpacity(0.3)
                          : const Color(0xFFDDD9D3)),
                width: isInProgress ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: block.color.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: block.isArmy
                ? _ArmyBlock(block: block)
                : _StandardBlock(
                    block: block,
                    isLocked: false,
                    isCompleted: isCompleted,
                    isInProgress: isInProgress,
                    tierAccent: _tierAccent,
                  ),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Widget screen;
    switch (block.blockType) {
      case 'basic':
        screen = BasicDetailScreen(block: block);
        break;
      case 'survival':
        screen = SurvivalDetailScreen(block: block);
        break;
      case 'puzzle':
        screen = PuzzleDetailScreen(block: block);
        break;
      case 'medical':
        screen = MedicalDetailScreen(block: block);
        break;
      case 'fire':
        screen = FireDetailScreen(block: block);
        break;
      case 'rescue':
        screen = RescueDetailScreen(block: block);
        break;
      case 'drill':
        screen = DrillDetailScreen(block: block);
        break;
      case 'combined':
        screen = CombinedDrillDetailScreen(block: block);
        break;
      default:
        screen = TrainingDetailScreen(block: block);
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _ConnectorLine extends StatelessWidget {
  final bool isUnlocked;
  final Color color;
  const _ConnectorLine({required this.isUnlocked, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(
          children: [
            Container(width: 2, height: 20, color: color),
            Icon(Icons.arrow_drop_up_rounded, color: color, size: 20),
          ],
        ),
      ],
    );
  }
}

class _StandardBlock extends StatelessWidget {
  final TrainingBlock block;
  final bool isLocked, isCompleted, isInProgress;
  final Color tierAccent;
  const _StandardBlock({
    required this.block,
    required this.isLocked,
    required this.isCompleted,
    required this.isInProgress,
    required this.tierAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tierAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  block.tier.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: tierAccent,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              _StatusBadge(
                isLocked: false,
                isCompleted: isCompleted,
                isInProgress: isInProgress,
                color: block.color,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: block.lightColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(block.icon, color: block.color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      block.subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF888880),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            block.description,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF666660),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: block.progress,
                    backgroundColor: const Color(0xFFE8E4DF),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isCompleted ? const Color(0xFF3D7A3A) : block.color,
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(block.progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: block.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 13, color: block.color),
              const SizedBox(width: 3),
              Text(
                '+${block.xpReward} XP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: block.color,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.layers_rounded,
                size: 13,
                color: const Color(0xFF888880),
              ),
              const SizedBox(width: 3),
              Text(
                'Level ${block.level}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF888880)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: block.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isCompleted ? 'Review' : 'Open',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isLocked, isCompleted, isInProgress;
  final Color color;
  const _StatusBadge({
    required this.isLocked,
    required this.isCompleted,
    required this.isInProgress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF3D7A3A).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 12,
              color: Color(0xFF3D7A3A),
            ),
            SizedBox(width: 4),
            Text(
              'Completed',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3D7A3A),
              ),
            ),
          ],
        ),
      );
    }
    if (isInProgress) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.play_circle_rounded, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              'Open',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE8E4DF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_open_rounded, size: 12, color: Color(0xFF888880)),
          SizedBox(width: 4),
          Text(
            'Start',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF888880),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArmyBlock extends StatefulWidget {
  final TrainingBlock block;
  const _ArmyBlock({required this.block});

  @override
  State<_ArmyBlock> createState() => _ArmyBlockState();
}

class _ArmyBlockState extends State<_ArmyBlock> {
  String? _levelGateJustification;
  bool _loading = false;

  TrainingBlock get block => widget.block;

  Future<void> _fetchLevelGate() async {
    setState(() => _loading = true);
    final completedBlocks = trainingBlocks
        .where((b) => b.status == BlockStatus.completed)
        .map((b) => b.title)
        .join(', ');
    final prompt =
        'A disaster response volunteer wants to join Army Corps (elite level). '
        'They have completed: $completedBlocks. '
        'Explain in 2 sentences what specific skills and real-world experience they still need to unlock this elite tier. Be direct and motivating.';
    final result = await GeminiService.generateContent(prompt, 'basic');
    if (mounted)
      setState(() {
        _levelGateJustification = result;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [block.color, const Color(0xFF2D2D4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.military_tech_rounded,
                  color: Colors.amber,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ARMY CORPS',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Elite Volunteer Force',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: const Text(
                  'ELITE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.amber,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            block.description,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          // AI Level-Gate Justification
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.amber,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'AI checking your requirements...',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            )
          else if (_levelGateJustification != null)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.amber,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _levelGateJustification!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: _fetchLevelGate,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFF1A1A2E),
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Check AI Requirements',
                    style: TextStyle(
                      color: Color(0xFF1A1A2E),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SHARED DETAIL SCREEN BASE
// ─────────────────────────────────────────────

class _BaseDetailScreen extends StatelessWidget {
  final TrainingBlock block;
  final List<Widget> children;
  const _BaseDetailScreen({required this.block, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2EDE8),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: block.color,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'AI Help',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GeminiChatScreen(
                      title: block.title,
                      topic: block.title,
                      color: block.color,
                      blockType: block.blockType,
                    ),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                block.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [block.color, block.color.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 30),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(block.icon, color: Colors.white, size: 34),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        block.subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            sliver: SliverList(delegate: SliverChildListDelegate(children)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// BASIC DETAIL SCREEN
// ─────────────────────────────────────────────

class BasicDetailScreen extends StatefulWidget {
  final TrainingBlock block;
  const BasicDetailScreen({super.key, required this.block});

  @override
  State<BasicDetailScreen> createState() => _BasicDetailScreenState();
}

class _BasicDetailScreenState extends State<BasicDetailScreen> {
  final Set<int> _completedVideos = {0, 1, 2, 3, 4};

  static final List<Map<String, dynamic>> videos = [
    {
      'title': 'Types of Disasters Explained',
      'duration': '4:45',
      'tag': 'Overview',
      'icon': Icons.tsunami_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'What is a Disaster?',
          'color': const Color(0xFFFF4136),
        },
        {
          'time': '0:45',
          'timeSecs': 45,
          'title': 'Natural Disasters',
          'color': const Color(0xFFFF6B35),
        },
        {
          'time': '1:30',
          'timeSecs': 90,
          'title': 'Geological Events',
          'color': const Color(0xFFFF4136),
        },
        {
          'time': '2:15',
          'timeSecs': 135,
          'title': 'Hydro-meteorological',
          'color': const Color(0xFF4FC3F7),
        },
        {
          'time': '3:00',
          'timeSecs': 180,
          'title': 'Man-made Disasters',
          'color': const Color(0xFFFFD700),
        },
        {
          'time': '3:45',
          'timeSecs': 225,
          'title': 'Global Impact Stats',
          'color': const Color(0xFF39FF14),
        },
        {
          'time': '4:15',
          'timeSecs': 255,
          'title': 'Why Preparedness Matters',
          'color': const Color(0xFFFF4136),
        },
      ],
      'keyPoints': <String>[
        'Disasters are classified as natural (geological, meteorological, biological) or man-made (technological, conflict-based).',
        'Over 90% of disaster deaths occur in low- and middle-income countries.',
        'Climate change is increasing the frequency and intensity of weather-related disasters.',
        'Early warning systems can reduce disaster deaths by up to 30 times.',
        'Community preparedness is the single most effective disaster risk reduction tool.',
      ],
    },
    {
      'title': 'Flood Warning Signs & Safety',
      'duration': '4:30',
      'tag': 'Flood',
      'icon': Icons.water_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'How Floods Form',
          'color': const Color(0xFF00AAFF),
        },
        {
          'time': '0:40',
          'timeSecs': 40,
          'title': 'Early Warning Signs',
          'color': const Color(0xFF4FC3F7),
        },
        {
          'time': '1:20',
          'timeSecs': 80,
          'title': 'Flood Categories',
          'color': const Color(0xFF0077CC),
        },
        {
          'time': '2:10',
          'timeSecs': 130,
          'title': 'Before a Flood',
          'color': const Color(0xFF00D4FF),
        },
        {
          'time': '2:50',
          'timeSecs': 170,
          'title': 'During a Flood',
          'color': const Color(0xFF00AAFF),
        },
        {
          'time': '3:30',
          'timeSecs': 210,
          'title': 'Evacuation Routes',
          'color': const Color(0xFF39FF14),
        },
        {
          'time': '4:00',
          'timeSecs': 240,
          'title': 'After the Flood',
          'color': const Color(0xFFFFD700),
        },
      ],
      'keyPoints': <String>[
        'Rapidly rising water levels, unusual sounds from rivers, and dark discolored water are key early flood indicators.',
        'Never drive through flooded roads — just 15cm of water can knock a person down.',
        'Flash floods can develop in under 6 hours — leave immediately when warned.',
        'Prepare a Go-Bag with documents, medications, water (3 days), and flashlights.',
        'After flooding, avoid tap water until authorities declare it safe.',
      ],
    },
    {
      'title': 'Earthquake — Before, During & After',
      'duration': '5:00',
      'tag': 'Earthquake',
      'icon': Icons.vibration_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'How Earthquakes Work',
          'color': const Color(0xFFFF8C00),
        },
        {
          'time': '0:50',
          'timeSecs': 50,
          'title': 'The Richter Scale',
          'color': const Color(0xFFFFB347),
        },
        {
          'time': '1:30',
          'timeSecs': 90,
          'title': 'BEFORE: Prepare Home',
          'color': const Color(0xFFFFD700),
        },
        {
          'time': '2:20',
          'timeSecs': 140,
          'title': 'DURING: Drop Cover Hold',
          'color': const Color(0xFFFF4136),
        },
        {
          'time': '3:00',
          'timeSecs': 180,
          'title': 'DURING: If Outside / Driving',
          'color': const Color(0xFFFF8C00),
        },
        {
          'time': '3:40',
          'timeSecs': 220,
          'title': 'AFTER: Aftershocks',
          'color': const Color(0xFFFF6B35),
        },
        {
          'time': '4:20',
          'timeSecs': 260,
          'title': 'AFTER: Damage Assessment',
          'color': const Color(0xFF39FF14),
        },
      ],
      'keyPoints': <String>[
        'Earthquakes occur at tectonic plate boundaries — 80% of major quakes happen in the Ring of Fire.',
        'DROP to hands/knees, take COVER under a sturdy table, HOLD ON until shaking stops.',
        'Secure heavy furniture, know your utility shutoffs, and identify safe spots in each room.',
        'Expect aftershocks after any major quake — some can be nearly as powerful as the main event.',
        'If trapped, conserve air, tap on pipes to signal rescuers, and do not use lighters.',
      ],
    },
    {
      'title': 'Fire Safety at Home & Work',
      'duration': '4:20',
      'tag': 'Fire',
      'icon': Icons.local_fire_department_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'The Fire Triangle',
          'color': const Color(0xFFFF6B00),
        },
        {
          'time': '0:40',
          'timeSecs': 40,
          'title': 'How Fire Spreads',
          'color': const Color(0xFFFF4500),
        },
        {
          'time': '1:20',
          'timeSecs': 80,
          'title': 'Prevention at Home',
          'color': const Color(0xFFFFD700),
        },
        {
          'time': '2:00',
          'timeSecs': 120,
          'title': 'RACE Protocol',
          'color': const Color(0xFFFF6B00),
        },
        {
          'time': '2:40',
          'timeSecs': 160,
          'title': 'PASS Extinguisher Use',
          'color': const Color(0xFFFF4136),
        },
        {
          'time': '3:15',
          'timeSecs': 195,
          'title': 'Escape Planning',
          'color': const Color(0xFF39FF14),
        },
        {
          'time': '3:45',
          'timeSecs': 225,
          'title': 'Smoke & Burns First Aid',
          'color': const Color(0xFF00D4FF),
        },
      ],
      'keyPoints': <String>[
        'Fire needs fuel, heat, and oxygen — removing any one element stops it. CO2 extinguishers remove oxygen.',
        'RACE: Rescue, Alarm, Contain (close doors!), Extinguish or Evacuate.',
        'PASS: Pull pin, Aim at base, Squeeze handle, Sweep side to side.',
        'Most fire deaths are from smoke inhalation, not burns — stay low and crawl under smoke.',
        'Test smoke alarms monthly and replace batteries every 6 months.',
      ],
    },
    {
      'title': 'Cyclone Preparedness Guide',
      'duration': '4:50',
      'tag': 'Cyclone',
      'icon': Icons.air_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'How Cyclones Form',
          'color': const Color(0xFF9B59B6),
        },
        {
          'time': '0:45',
          'timeSecs': 45,
          'title': 'Saffir-Simpson Scale',
          'color': const Color(0xFFC678DD),
        },
        {
          'time': '1:30',
          'timeSecs': 90,
          'title': 'Storm Surge Danger',
          'color': const Color(0xFF00D4FF),
        },
        {
          'time': '2:15',
          'timeSecs': 135,
          'title': '72hrs Before: Prepare',
          'color': const Color(0xFFFFD700),
        },
        {
          'time': '3:00',
          'timeSecs': 180,
          'title': 'During the Cyclone',
          'color': const Color(0xFF9B59B6),
        },
        {
          'time': '3:40',
          'timeSecs': 220,
          'title': 'The Eye — False Safety',
          'color': const Color(0xFFFF4136),
        },
        {
          'time': '4:15',
          'timeSecs': 255,
          'title': 'After: Safe Return',
          'color': const Color(0xFF39FF14),
        },
      ],
      'keyPoints': <String>[
        'Cyclones form over warm ocean water (>26°C) and are driven by the Coriolis effect.',
        'Storm surge — not wind — causes 90% of cyclone deaths. Coastal areas must evacuate when ordered.',
        'Board windows, fill bathtubs with water, charge devices 72 hours before landfall.',
        'The eye of the cyclone brings calm — do NOT go outside, the dangerous eyewall follows immediately.',
        'Wait for official all-clear before returning home; downed power lines and flooding remain deadly.',
      ],
    },
    {
      'title': 'Community Alert Systems',
      'duration': '2:50',
      'tag': 'Alerts',
      'icon': Icons.campaign_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'Why Alert Systems Exist',
          'color': const Color(0xFF39FF14),
        },
        {
          'time': '0:40',
          'timeSecs': 40,
          'title': 'Siren Pattern Guide',
          'color': const Color(0xFFFFD700),
        },
        {
          'time': '1:20',
          'timeSecs': 80,
          'title': 'Emergency Alert System',
          'color': const Color(0xFF39FF14),
        },
        {
          'time': '2:00',
          'timeSecs': 120,
          'title': 'Mobile Cell Alerts',
          'color': const Color(0xFF00D4FF),
        },
        {
          'time': '2:30',
          'timeSecs': 150,
          'title': 'Building Your Alert Plan',
          'color': const Color(0xFFFFD700),
        },
      ],
      'keyPoints': <String>[
        'A steady siren typically means all clear; a wailing/wavering siren means take action now.',
        'The Emergency Alert System uses a distinctive attention signal — never ignore it.',
        'Wireless Emergency Alerts (WEA) go directly to cell phones — keep location services on.',
        'Register with your local emergency management office for personalized neighborhood alerts.',
      ],
    },
    {
      'title': 'Emergency Signal Recognition',
      'duration': '3:20',
      'tag': 'Signals',
      'icon': Icons.sos_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'Visual Distress Signals',
          'color': const Color(0xFFFF4136),
        },
        {
          'time': '0:50',
          'timeSecs': 50,
          'title': 'SOS in Different Forms',
          'color': const Color(0xFFFFD700),
        },
        {
          'time': '1:40',
          'timeSecs': 100,
          'title': 'Ground-to-Air Signals',
          'color': const Color(0xFF00D4FF),
        },
        {
          'time': '2:20',
          'timeSecs': 140,
          'title': 'Mirror & Light Signals',
          'color': const Color(0xFF39FF14),
        },
        {
          'time': '2:55',
          'timeSecs': 175,
          'title': 'Know Before You Need It',
          'color': const Color(0xFFFF4136),
        },
      ],
      'keyPoints': <String>[
        'Three blasts of a whistle or horn is the universal distress signal; mirrors can signal over 16km.',
        'SOS (... --- ...) is internationally recognized — use it with light, sound, or markings.',
        'Ground-to-Air signals: V = need assistance, X = need medical help, → = moving this direction.',
        'Bright colors, reflective materials, and smoke are highly visible to rescue aircraft.',
      ],
    },
    {
      'title': 'Your Role as a Volunteer',
      'duration': '4:00',
      'tag': 'Volunteer',
      'icon': Icons.volunteer_activism_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'Why Volunteers Matter',
          'color': const Color(0xFF2A7ABD),
        },
        {
          'time': '0:55',
          'timeSecs': 55,
          'title': 'Volunteer Responsibilities',
          'color': const Color(0xFF4FC3F7),
        },
        {
          'time': '1:40',
          'timeSecs': 100,
          'title': 'Chain of Command',
          'color': const Color(0xFFFFD700),
        },
        {
          'time': '2:20',
          'timeSecs': 140,
          'title': 'Communication Protocols',
          'color': const Color(0xFF39FF14),
        },
        {
          'time': '3:05',
          'timeSecs': 185,
          'title': 'Self-Care During Crisis',
          'color': const Color(0xFFFF6B35),
        },
        {
          'time': '3:35',
          'timeSecs': 215,
          'title': 'Your Commitment Pledge',
          'color': const Color(0xFF2A7ABD),
        },
      ],
      'keyPoints': <String>[
        'Trained volunteers multiply emergency response capacity — every certified person saves lives.',
        'Always work within your assigned role and never freelance during an active disaster.',
        'Maintain clear communication with your team leader; silence = confusion.',
        'Volunteer burnout is real — rotate, rest, and debrief after every deployment.',
        'Your credibility comes from your training; stay current and practice regularly.',
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return _BaseDetailScreen(
      block: widget.block,
      children: [
        _SectionHeader(
          icon: Icons.play_circle_filled_rounded,
          label: 'Video Lectures & Animated Clips',
          color: widget.block.color,
        ),
        const SizedBox(height: 8),
        const Text(
          'Short, focused video lessons covering crisis basics. Tap Play to watch each animated lesson.',
          style: TextStyle(fontSize: 13, color: Color(0xFF666660), height: 1.5),
        ),
        const SizedBox(height: 16),
        ...videos.asMap().entries.map(
          (e) => AnimatedVideoPlayer(
            video: e.value,
            color: widget.block.color,
            initialCompleted: _completedVideos.contains(e.key),
            onCompleted: () => setState(() => _completedVideos.add(e.key)),
          ),
        ),
        const SizedBox(height: 20),
        _MissionsSection(block: widget.block),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// SURVIVAL DETAIL SCREEN
// ─────────────────────────────────────────────

class SurvivalDetailScreen extends StatefulWidget {
  final TrainingBlock block;
  const SurvivalDetailScreen({super.key, required this.block});

  @override
  State<SurvivalDetailScreen> createState() => _SurvivalDetailScreenState();
}

class _SurvivalDetailScreenState extends State<SurvivalDetailScreen> {
  final Set<int> _completedVideos = {0, 1, 2, 3};

  static const List<Map<String, dynamic>> safetyRules = [
    {
      'rule': 'Stay calm — panic kills faster than the disaster',
      'icon': Icons.self_improvement_rounded,
    },
    {
      'rule': 'Move to higher ground immediately during floods',
      'icon': Icons.trending_up_rounded,
    },
    {
      'rule': 'Drop, Cover, Hold during earthquakes',
      'icon': Icons.shield_rounded,
    },
    {
      'rule': 'Never re-enter a building after fire or quake',
      'icon': Icons.block_rounded,
    },
    {
      'rule': 'Keep your emergency kit within 60 seconds reach',
      'icon': Icons.backpack_rounded,
    },
    {
      'rule': 'Conserve phone battery for emergency calls only',
      'icon': Icons.battery_saver_rounded,
    },
    {
      'rule': 'Know your local evacuation routes by heart',
      'icon': Icons.map_rounded,
    },
    {
      'rule': 'Help children and elderly before assisting others',
      'icon': Icons.elderly_rounded,
    },
  ];

  static final List<Map<String, dynamic>> videos = [
    {
      'title': 'Water Purification in a Crisis',
      'duration': '2:45',
      'tag': 'Water',
      'icon': Icons.water_drop_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'Why Water Safety Matters',
          'color': const Color(0xFF00AAFF),
        },
        {
          'time': '0:40',
          'timeSecs': 40,
          'title': 'Boiling Method',
          'color': const Color(0xFF4FC3F7),
        },
        {
          'time': '1:20',
          'timeSecs': 80,
          'title': 'Chemical Treatment',
          'color': const Color(0xFFFFD700),
        },
        {
          'time': '1:55',
          'timeSecs': 115,
          'title': 'Improvised Filtration',
          'color': const Color(0xFF39FF14),
        },
        {
          'time': '2:20',
          'timeSecs': 140,
          'title': 'Safe Storage Tips',
          'color': const Color(0xFF00D4FF),
        },
      ],
      'keyPoints': <String>[
        'Boiling water for at least 1 minute kills all biological contaminants including viruses.',
        'Chlorine/iodine tablets are lightweight and essential in every emergency kit.',
        'A simple improvised filter: layer cloth, sand, gravel, and activated charcoal in a bottle.',
        'Store purified water in clean sealed containers away from sunlight.',
        'Never drink from unknown sources without treatment — even clear water can be contaminated.',
      ],
    },
    {
      'title': 'Building a Basic Shelter',
      'duration': '3:30',
      'tag': 'Shelter',
      'icon': Icons.home_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'Shelter Priority in Survival',
          'color': const Color(0xFF8B5E2E),
        },
        {
          'time': '0:45',
          'timeSecs': 45,
          'title': 'Site Selection',
          'color': const Color(0xFFFF8C00),
        },
        {
          'time': '1:20',
          'timeSecs': 80,
          'title': 'Lean-To Structure',
          'color': const Color(0xFFFFD700),
        },
        {
          'time': '2:00',
          'timeSecs': 120,
          'title': 'Debris Hut Method',
          'color': const Color(0xFF39FF14),
        },
        {
          'time': '2:45',
          'timeSecs': 165,
          'title': 'Using Available Materials',
          'color': const Color(0xFF8B5E2E),
        },
        {
          'time': '3:10',
          'timeSecs': 190,
          'title': 'Insulation & Warmth',
          'color': const Color(0xFFFF6B35),
        },
      ],
      'keyPoints': <String>[
        'In survival situations, shelter is the #1 priority — exposure kills faster than hunger or thirst.',
        'Choose high, flat ground away from flood paths, falling trees, and animal trails.',
        'A lean-to can be built in under 30 minutes using branches and leaves.',
        'Insulate the floor first — ground contact steals body heat faster than cold air.',
        'A properly constructed debris hut can maintain warmth even in near-freezing temperatures.',
      ],
    },
    {
      'title': 'Sending Distress Signals',
      'duration': '2:00',
      'tag': 'Signal',
      'icon': Icons.sos_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'Universal SOS Signal',
          'color': const Color(0xFFFF4136),
        },
        {
          'time': '0:30',
          'timeSecs': 30,
          'title': 'Mirror Signaling',
          'color': const Color(0xFFFFD700),
        },
        {
          'time': '1:00',
          'timeSecs': 60,
          'title': 'Smoke & Fire Signals',
          'color': const Color(0xFFFF6B00),
        },
        {
          'time': '1:35',
          'timeSecs': 95,
          'title': 'Ground-to-Air Patterns',
          'color': const Color(0xFF39FF14),
        },
      ],
      'keyPoints': <String>[
        'SOS (3 short, 3 long, 3 short) is the universal distress signal by light, sound, or marking.',
        'A signal mirror can be seen by aircraft at over 16km — learn the two-hole aiming technique.',
        'Smoke signals: white smoke (green leaves) is more visible against dark terrain; black (rubber) against snow.',
        'Ground-to-air patterns must be at least 10m wide to be visible from aircraft altitude.',
      ],
    },
    {
      'title': 'What to Pack in Your Emergency Kit',
      'duration': '3:10',
      'tag': 'Kit',
      'icon': Icons.backpack_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'The 72-Hour Rule',
          'color': const Color(0xFF6A3FA0),
        },
        {
          'time': '0:45',
          'timeSecs': 45,
          'title': 'Water & Food Essentials',
          'color': const Color(0xFF00AAFF),
        },
        {
          'time': '1:15',
          'timeSecs': 75,
          'title': 'Medical & Documents',
          'color': const Color(0xFFD94035),
        },
        {
          'time': '1:50',
          'timeSecs': 110,
          'title': 'Tools & Communication',
          'color': const Color(0xFFFF8C00),
        },
        {
          'time': '2:20',
          'timeSecs': 140,
          'title': 'Clothing & Warmth',
          'color': const Color(0xFF2E6B4F),
        },
        {
          'time': '2:45',
          'timeSecs': 165,
          'title': 'Kit Maintenance Tips',
          'color': const Color(0xFFFFD700),
        },
      ],
      'keyPoints': <String>[
        'Your emergency kit should sustain you for 72 hours (3 days) minimum without outside help.',
        'Pack 3 liters of water per person per day plus water purification tablets.',
        'Always include photocopies of critical documents: ID, insurance, medical records.',
        'A hand-crank or solar radio keeps you informed when phone networks fail.',
        'Review and restock your kit every 6 months — replace expired food, batteries, and medications.',
      ],
    },
    {
      'title': 'Food Safety After a Disaster',
      'duration': '2:20',
      'tag': 'Food',
      'icon': Icons.restaurant_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'The Danger Zone',
          'color': const Color(0xFFFF4136),
        },
        {
          'time': '0:40',
          'timeSecs': 40,
          'title': 'What to Discard',
          'color': const Color(0xFFFF6B00),
        },
        {
          'time': '1:10',
          'timeSecs': 70,
          'title': 'Safe Foods to Keep',
          'color': const Color(0xFF39FF14),
        },
        {
          'time': '1:45',
          'timeSecs': 105,
          'title': 'Cooking Without Power',
          'color': const Color(0xFFFFD700),
        },
      ],
      'keyPoints': <String>[
        'Food left between 4°C and 60°C for more than 2 hours must be discarded — bacteria multiply rapidly.',
        'Discard any food with unusual odor, color, or texture, or that touched floodwater.',
        'Canned goods, dry foods, and commercially sealed items in intact packages are generally safe.',
        'A camp stove, wood fire, or solar cooker can safely heat food when electricity is unavailable.',
        'When in doubt, throw it out — food poisoning during a disaster can be life-threatening.',
      ],
    },
    {
      'title': 'How to Handle Stress in Crisis',
      'duration': '2:50',
      'tag': 'Mental',
      'icon': Icons.psychology_rounded,
      'scenes': <Map<String, dynamic>>[
        {
          'time': '0:00',
          'timeSecs': 0,
          'title': 'Why Crisis Stress is Different',
          'color': const Color(0xFF9B59B6),
        },
        {
          'time': '0:40',
          'timeSecs': 40,
          'title': 'Recognizing Symptoms',
          'color': const Color(0xFFFF4136),
        },
        {
          'time': '1:15',
          'timeSecs': 75,
          'title': 'Immediate Calming Techniques',
          'color': const Color(0xFF00D4FF),
        },
        {
          'time': '1:55',
          'timeSecs': 115,
          'title': 'Helping Others Cope',
          'color': const Color(0xFF39FF14),
        },
        {
          'time': '2:25',
          'timeSecs': 145,
          'title': 'Long-term Recovery',
          'color': const Color(0xFF9B59B6),
        },
      ],
      'keyPoints': <String>[
        'Acute stress response (fight-or-flight) is normal during a crisis — learn to channel it productively.',
        'Box breathing (4 counts in, hold, out, hold) rapidly reduces anxiety and improves decision-making.',
        'Focus on what you CAN control — your actions, your breathing, your next small step.',
        'Children and elderly show stress differently — watch for behavioral changes, not just verbal reports.',
        'Seeking help after a disaster is strength, not weakness — debriefing improves long-term resilience.',
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return _BaseDetailScreen(
      block: widget.block,
      children: [
        _SectionHeader(
          icon: Icons.rule_rounded,
          label: 'Safety Rules to Remember',
          color: widget.block.color,
        ),
        const SizedBox(height: 12),
        ...safetyRules.map(
          (r) => _SafetyRuleCard(rule: r, color: widget.block.color),
        ),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.play_circle_filled_rounded,
          label: 'Animated Short Videos',
          color: widget.block.color,
        ),
        const SizedBox(height: 8),
        const Text(
          'Quick 2-3 minute animated clips. Visual, practical, and easy to remember.',
          style: TextStyle(fontSize: 13, color: Color(0xFF666660), height: 1.5),
        ),
        const SizedBox(height: 12),
        ...videos.asMap().entries.map(
          (e) => AnimatedVideoPlayer(
            video: e.value,
            color: widget.block.color,
            initialCompleted: _completedVideos.contains(e.key),
            onCompleted: () => setState(() => _completedVideos.add(e.key)),
          ),
        ),
        const SizedBox(height: 20),
        _MissionsSection(block: widget.block),
      ],
    );
  }
}

class _SafetyRuleCard extends StatelessWidget {
  final Map<String, dynamic> rule;
  final Color color;
  const _SafetyRuleCard({required this.rule, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(rule['icon'] as IconData, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              rule['rule'] as String,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF444440),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PUZZLE DETAIL SCREEN
// ─────────────────────────────────────────────

class PuzzleDetailScreen extends StatefulWidget {
  final TrainingBlock block;
  const PuzzleDetailScreen({super.key, required this.block});

  @override
  State<PuzzleDetailScreen> createState() => _PuzzleDetailScreenState();
}

class _PuzzleDetailScreenState extends State<PuzzleDetailScreen> {
  final List<int?> _scores = List.filled(10, null);

  @override
  Widget build(BuildContext context) {
    return _BaseDetailScreen(
      block: widget.block,
      children: [
        _SectionHeader(
          icon: Icons.extension_rounded,
          label: '10 Crisis Scenario Puzzles',
          color: widget.block.color,
        ),
        const SizedBox(height: 8),
        const Text(
          'Each puzzle is a unique crisis situation. Think carefully — one correct answer. Reattempt anytime to improve your score.',
          style: TextStyle(fontSize: 13, color: Color(0xFF666660), height: 1.5),
        ),
        const SizedBox(height: 16),
        ...survivalPuzzles.asMap().entries.map(
          (e) => _PuzzleCard(
            puzzle: e.value,
            index: e.key,
            color: widget.block.color,
            score: _scores[e.key],
            onScoreUpdated: (score) => setState(() => _scores[e.key] = score),
          ),
        ),
      ],
    );
  }
}

class _PuzzleCard extends StatefulWidget {
  final PuzzleQuestion puzzle;
  final int index;
  final Color color;
  final int? score;
  final ValueChanged<int> onScoreUpdated;
  const _PuzzleCard({
    required this.puzzle,
    required this.index,
    required this.color,
    required this.score,
    required this.onScoreUpdated,
  });

  @override
  State<_PuzzleCard> createState() => _PuzzleCardState();
}

class _PuzzleCardState extends State<_PuzzleCard> {
  bool _expanded = false;
  int? _selected;
  bool _submitted = false;
  String? _aiJustification;
  bool _loadingAI = false;

  Future<void> _fetchAIJustification(int selectedIdx, bool correct) async {
    setState(() => _loadingAI = true);
    final prompt =
        'The user answered option "${widget.puzzle.options[selectedIdx]}" to this crisis puzzle: "${widget.puzzle.question}". '
        'They were ${correct ? "correct" : "incorrect"}. The correct answer is "${widget.puzzle.options[widget.puzzle.correctIndex]}". '
        'Rate their emergency response skill on this question (1-10), explain why the correct action is critical in real disasters, and give one practical tip to remember it. Keep it concise, 3-4 sentences.';
    final result = await GeminiService.generateContent(prompt, 'puzzle');
    if (mounted)
      setState(() {
        _aiJustification = result;
        _loadingAI = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final bool attempted = widget.score != null;
    final bool passed = (widget.score ?? 0) >= 70;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: attempted
              ? (passed ? const Color(0xFF3D7A3A) : const Color(0xFFD94035))
                    .withOpacity(0.3)
              : const Color(0xFFE8E4DF),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.index + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: widget.color,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Puzzle ${widget.index + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF888880),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (attempted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (passed
                                    ? const Color(0xFF3D7A3A)
                                    : const Color(0xFFD94035))
                                .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.score}/100',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: passed
                              ? const Color(0xFF3D7A3A)
                              : const Color(0xFFD94035),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF888880),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    widget.puzzle.question,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...widget.puzzle.options.asMap().entries.map(
                    (e) => _OptionTile(
                      label: e.value,
                      index: e.key,
                      selected: _selected == e.key,
                      submitted: _submitted,
                      isCorrect: e.key == widget.puzzle.correctIndex,
                      onTap: _submitted
                          ? null
                          : () => setState(() => _selected = e.key),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_submitted && _selected != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            (_selected == widget.puzzle.correctIndex
                                    ? const Color(0xFF3D7A3A)
                                    : const Color(0xFFD94035))
                                .withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              (_selected == widget.puzzle.correctIndex
                                      ? const Color(0xFF3D7A3A)
                                      : const Color(0xFFD94035))
                                  .withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _selected == widget.puzzle.correctIndex
                                ? Icons.check_circle_rounded
                                : Icons.info_rounded,
                            color: _selected == widget.puzzle.correctIndex
                                ? const Color(0xFF3D7A3A)
                                : const Color(0xFFD94035),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.puzzle.explanation,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF444440),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_loadingAI)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F0FE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF4285F4),
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Gemini AI is scoring your response...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4285F4),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_aiJustification != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F0FE),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF4285F4).withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 14,
                                  color: Color(0xFF4285F4),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'AI Skill Assessment',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF4285F4),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _aiJustification!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1A1A1A),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => setState(() {
                        _selected = null;
                        _submitted = false;
                        _aiJustification = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: widget.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              color: widget.color,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Try Again',
                              style: TextStyle(
                                color: widget.color,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else
                    GestureDetector(
                      onTap: _selected == null
                          ? null
                          : () {
                              final correct =
                                  _selected == widget.puzzle.correctIndex;
                              setState(() => _submitted = true);
                              final score = correct ? 100 : 40;
                              widget.onScoreUpdated(score);
                              _fetchAIJustification(_selected!, correct);
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selected != null
                              ? widget.color
                              : const Color(0xFFD0CCC6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Submit Answer',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
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

class _OptionTile extends StatelessWidget {
  final String label;
  final int index;
  final bool selected, submitted, isCorrect;
  final VoidCallback? onTap;
  const _OptionTile({
    required this.label,
    required this.index,
    required this.selected,
    required this.submitted,
    required this.isCorrect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = Colors.white;
    Color border = const Color(0xFFE8E4DF);
    Color text = const Color(0xFF1A1A1A);
    if (submitted && isCorrect) {
      bg = const Color(0xFFE8F5E9);
      border = const Color(0xFF3D7A3A);
      text = const Color(0xFF3D7A3A);
    } else if (submitted && selected && !isCorrect) {
      bg = const Color(0xFFFFEBEB);
      border = const Color(0xFFD94035);
      text = const Color(0xFFD94035);
    } else if (selected) {
      bg = const Color(0xFFE3F2FD);
      border = const Color(0xFF2A7ABD);
      text = const Color(0xFF2A7ABD);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: border.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  ['A', 'B', 'C', 'D'][index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: border,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: text,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// MEDICAL DETAIL SCREEN
// ─────────────────────────────────────────────

class MedicalDetailScreen extends StatelessWidget {
  final TrainingBlock block;
  const MedicalDetailScreen({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    return _BaseDetailScreen(
      block: block,
      children: [
        _SectionHeader(
          icon: Icons.info_rounded,
          label: 'How This Works',
          color: block.color,
        ),
        const SizedBox(height: 8),
        _InfoBox(
          color: block.color,
          text:
              'All medical missions must be completed at a nearby hospital or health centre. Click START MISSION to begin, follow the steps, then submit a photo with the authorised doctor as completion proof.',
        ),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.local_hospital_rounded,
          label: 'Nearby Medical Centres',
          color: block.color,
        ),
        const SizedBox(height: 12),
        ...[
          {
            'name': 'Apollo Hospital',
            'area': 'Greams Road',
            'type': 'Multi-specialty',
          },
          {
            'name': 'GH Chennai',
            'area': 'Park Town',
            'type': 'Government Hospital',
          },
          {
            'name': 'Primary Health Centre',
            'area': 'Villivakkam',
            'type': 'PHC',
          },
          {
            'name': 'MIOT International',
            'area': 'Manapakkam',
            'type': 'Trauma Centre',
          },
        ].map((c) => _CentreCard(centre: c, color: block.color)),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.assignment_rounded,
          label: 'Medical Missions',
          color: block.color,
        ),
        const SizedBox(height: 12),
        ...medicalDrills.asMap().entries.map(
          (e) => _DrillCard(
            drill: e.value,
            index: e.key,
            color: block.color,
            completed: e.key < 2,
            blockType: block.blockType,
          ),
        ),
        const SizedBox(height: 20),
        _MissionsSection(block: block),
        const SizedBox(height: 16),
        _CertificateSection(color: block.color, department: 'Medical'),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// FIRE DETAIL SCREEN
// ─────────────────────────────────────────────

class FireDetailScreen extends StatelessWidget {
  final TrainingBlock block;
  const FireDetailScreen({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    return _BaseDetailScreen(
      block: block,
      children: [
        _SectionHeader(
          icon: Icons.info_rounded,
          label: 'How This Works',
          color: block.color,
        ),
        const SizedBox(height: 8),
        _InfoBox(
          color: block.color,
          text:
              'All fire missions must be completed at your nearest government fire station with an authorised fire officer present. Click START MISSION, complete each step, then submit your photo as proof.',
        ),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.fire_truck_rounded,
          label: 'Nearby Fire Stations',
          color: block.color,
        ),
        const SizedBox(height: 12),
        ...[
          {
            'name': 'Anna Nagar Fire Station',
            'area': 'Anna Nagar West',
            'type': 'District Station',
          },
          {
            'name': 'TNFRS Training Ground',
            'area': 'Egmore',
            'type': 'Training Centre',
          },
          {
            'name': 'Tambaram Fire Station',
            'area': 'Tambaram',
            'type': 'Sub Station',
          },
          {
            'name': 'Guindy Mock Structure',
            'area': 'Guindy',
            'type': 'SDRF Facility',
          },
        ].map((c) => _CentreCard(centre: c, color: block.color)),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.local_fire_department_rounded,
          label: 'Fire Drill Missions',
          color: block.color,
        ),
        const SizedBox(height: 12),
        ...fireDrills.asMap().entries.map(
          (e) => _DrillCard(
            drill: e.value,
            index: e.key,
            color: block.color,
            completed: e.key < 1,
            blockType: block.blockType,
          ),
        ),
        const SizedBox(height: 20),
        _MissionsSection(block: block),
        const SizedBox(height: 16),
        _CertificateSection(color: block.color, department: 'Fire & Rescue'),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// RESCUE DETAIL SCREEN
// ─────────────────────────────────────────────

class RescueDetailScreen extends StatelessWidget {
  final TrainingBlock block;
  const RescueDetailScreen({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    return _BaseDetailScreen(
      block: block,
      children: [
        _SectionHeader(
          icon: Icons.info_rounded,
          label: 'How This Works',
          color: block.color,
        ),
        const SizedBox(height: 8),
        _InfoBox(
          color: block.color,
          text:
              'All rescue missions are conducted with NDRF or SDRF teams at authorised training locations. Click START MISSION, follow each step, then submit a photo for completion approval.',
        ),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.location_on_rounded,
          label: 'NDRF / SDRF Centres Near You',
          color: block.color,
        ),
        const SizedBox(height: 12),
        ...[
          {
            'name': 'NDRF Regional Centre',
            'area': 'Chennai',
            'type': 'National Unit',
          },
          {
            'name': 'SDRF Training Tower',
            'area': 'Ambattur',
            'type': 'State Unit',
          },
          {'name': 'Mock Rubble Site', 'area': 'Porur', 'type': 'USAR Site'},
          {
            'name': 'Chembarambakkam Reservoir',
            'area': 'West Chennai',
            'type': 'Swiftwater',
          },
        ].map((c) => _CentreCard(centre: c, color: block.color)),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.flood_rounded,
          label: 'Rescue Missions',
          color: block.color,
        ),
        const SizedBox(height: 12),
        ...rescueDrills.asMap().entries.map(
          (e) => _DrillCard(
            drill: e.value,
            index: e.key,
            color: block.color,
            completed: false,
            blockType: block.blockType,
          ),
        ),
        const SizedBox(height: 20),
        _MissionsSection(block: block),
        const SizedBox(height: 16),
        _CertificateSection(color: block.color, department: 'NDRF / SDRF'),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// DRILL DETAIL SCREEN
// ─────────────────────────────────────────────

class DrillDetailScreen extends StatefulWidget {
  final TrainingBlock block;
  const DrillDetailScreen({super.key, required this.block});

  @override
  State<DrillDetailScreen> createState() => _DrillDetailScreenState();
}

class _DrillDetailScreenState extends State<DrillDetailScreen> {
  String? _selectedDept;

  static const List<Map<String, dynamic>> departments = [
    {
      'id': 'fire',
      'label': 'Fire Department',
      'icon': Icons.local_fire_department_rounded,
      'color': Color(0xFFB84A00),
    },
    {
      'id': 'medical',
      'label': 'Medical Services',
      'icon': Icons.favorite_rounded,
      'color': Color(0xFFD94035),
    },
    {
      'id': 'rescue',
      'label': 'Rescue Team (NDRF)',
      'icon': Icons.flood_rounded,
      'color': Color(0xFF2E6B4F),
    },
  ];

  List<DrillScenario> get _drills {
    switch (_selectedDept) {
      case 'fire':
        return fireDrills;
      case 'medical':
        return medicalDrills;
      case 'rescue':
        return rescueDrills;
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BaseDetailScreen(
      block: widget.block,
      children: [
        _SectionHeader(
          icon: Icons.directions_run_rounded,
          label: 'Select Your Department',
          color: widget.block.color,
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose a department to view nearby govt offices and drill scenarios.',
          style: TextStyle(fontSize: 13, color: Color(0xFF666660), height: 1.5),
        ),
        const SizedBox(height: 16),
        Row(
          children: departments.map((d) {
            final selected = _selectedDept == d['id'];
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedDept = d['id']),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: selected ? (d['color'] as Color) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? (d['color'] as Color)
                          : const Color(0xFFE8E4DF),
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: (d['color'] as Color).withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        d['icon'] as IconData,
                        color: selected ? Colors.white : (d['color'] as Color),
                        size: 26,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        d['label'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF444440),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (_selectedDept != null) ...[
          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.location_on_rounded,
            label: 'Nearby Govt Departments',
            color: widget.block.color,
          ),
          const SizedBox(height: 12),
          ..._getNearbyForDept(
            _selectedDept!,
          ).map((c) => _CentreCard(centre: c, color: widget.block.color)),
          const SizedBox(height: 20),
          _SectionHeader(
            icon: Icons.auto_awesome_rounded,
            label: 'Drill Missions',
            color: widget.block.color,
          ),
          const SizedBox(height: 12),
          ..._drills.asMap().entries.map(
            (e) => _DrillCard(
              drill: e.value,
              index: e.key,
              color: widget.block.color,
              completed: false,
              blockType: 'drill',
            ),
          ),
        ],
      ],
    );
  }

  List<Map<String, dynamic>> _getNearbyForDept(String dept) {
    switch (dept) {
      case 'fire':
        return [
          {
            'name': 'Anna Nagar Fire Station',
            'area': 'Anna Nagar West',
            'type': 'District Station',
          },
          {
            'name': 'TNFRS Training Ground',
            'area': 'Egmore',
            'type': 'Training Centre',
          },
          {
            'name': 'Tambaram Fire Station',
            'area': 'Tambaram',
            'type': 'Sub Station',
          },
        ];
      case 'medical':
        return [
          {
            'name': 'Apollo Hospital',
            'area': 'Greams Road',
            'type': 'Multi-specialty',
          },
          {
            'name': 'GH Chennai',
            'area': 'Park Town',
            'type': 'Government Hospital',
          },
          {
            'name': 'MIOT International',
            'area': 'Manapakkam',
            'type': 'Trauma Centre',
          },
        ];
      case 'rescue':
        return [
          {
            'name': 'NDRF Regional Centre',
            'area': 'Chennai',
            'type': 'National Unit',
          },
          {
            'name': 'SDRF Training Tower',
            'area': 'Ambattur',
            'type': 'State Unit',
          },
          {'name': 'Mock Rubble Site', 'area': 'Porur', 'type': 'USAR Site'},
        ];
      default:
        return [];
    }
  }
}

// ─────────────────────────────────────────────
// COMBINED DRILL DETAIL SCREEN
// ─────────────────────────────────────────────

class CombinedDrillDetailScreen extends StatelessWidget {
  final TrainingBlock block;
  const CombinedDrillDetailScreen({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    return _BaseDetailScreen(
      block: block,
      children: [
        _SectionHeader(
          icon: Icons.hub_rounded,
          label: 'Multi-Agency Crisis Drills',
          color: block.color,
        ),
        const SizedBox(height: 8),
        _InfoBox(
          color: block.color,
          text:
              'These drills involve ALL emergency departments working together. Read the mission brief, click START MISSION, coordinate with your team, then submit a group photo as completion proof.',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: block.color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: block.color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: block.color, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'These are advanced drills. Ensure all agency participants are briefed before starting.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF444440),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.assignment_rounded,
          label: 'Combined Drill Missions',
          color: block.color,
        ),
        const SizedBox(height: 12),
        ...combinedDrills.asMap().entries.map(
          (e) => _DrillCard(
            drill: e.value,
            index: e.key,
            color: block.color,
            completed: false,
            blockType: 'combined',
          ),
        ),
        const SizedBox(height: 20),
        _CertificateSection(color: block.color, department: 'All Departments'),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// TRAINING DETAIL SCREEN (default/army)
// ─────────────────────────────────────────────

class TrainingDetailScreen extends StatelessWidget {
  final TrainingBlock block;
  const TrainingDetailScreen({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    return _BaseDetailScreen(
      block: block,
      children: [
        _InfoBox(color: block.color, text: block.description),
        const SizedBox(height: 20),
        _MissionsSection(block: block),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// DRILL CARD — WITH FUNCTIONAL START MISSION
// ─────────────────────────────────────────────

class _DrillCard extends StatefulWidget {
  final DrillScenario drill;
  final int index;
  final Color color;
  final bool completed;
  final String blockType;

  const _DrillCard({
    required this.drill,
    required this.index,
    required this.color,
    required this.completed,
    required this.blockType,
  });

  @override
  State<_DrillCard> createState() => _DrillCardState();
}

class _DrillCardState extends State<_DrillCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.completed
              ? const Color(0xFF3D7A3A).withOpacity(0.3)
              : const Color(0xFFE8E4DF),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: widget.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '${widget.index + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: widget.color,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.drill.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                      if (widget.completed)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF3D7A3A),
                          size: 20,
                        )
                      else
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: const Color(0xFF888880),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(width: 42),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _DrillChip(
                              icon: Icons.apartment_rounded,
                              label: widget.drill.department,
                              color: widget.color,
                            ),
                            _DrillChip(
                              icon: Icons.access_time_rounded,
                              label: '${widget.drill.durationMin} min',
                              color: widget.color,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  _DrillInfoRow(
                    icon: Icons.location_on_rounded,
                    label: 'Location',
                    value: widget.drill.location,
                  ),
                  const SizedBox(height: 6),
                  _DrillInfoRow(
                    icon: Icons.badge_rounded,
                    label: 'Authorised by',
                    value: widget.drill.authorisedPerson,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Objective',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: widget.color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.drill.objective,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF444440),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Steps',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...widget.drill.steps.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: widget.color,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${e.key + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              e.value,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF444440),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GeminiChatScreen(
                          title: widget.drill.title,
                          topic: widget.drill.title,
                          color: widget.color,
                          blockType: 'drill',
                        ),
                      ),
                    ),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: widget.color.withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: widget.color,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Ask AI About This Drill',
                            style: TextStyle(
                              color: widget.color,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // START MISSION button — navigates to MissionStartScreen
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MissionStartScreen(
                          drill: widget.drill,
                          color: widget.color,
                          blockType: widget.blockType,
                        ),
                      ),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: widget.completed
                            ? const Color(0xFF3D7A3A)
                            : widget.color,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.completed
                                ? Icons.replay_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.completed ? 'Redo Mission' : 'Start Mission',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
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

// ─────────────────────────────────────────────
// SHARED WIDGET HELPERS
// ─────────────────────────────────────────────

class _DrillChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _DrillChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrillInfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _DrillInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF888880)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF888880),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, color: Color(0xFF444440)),
          ),
        ),
      ],
    );
  }
}

class _CentreCard extends StatelessWidget {
  final Map<String, dynamic> centre;
  final Color color;
  const _CentreCard({required this.centre, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.location_on_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  centre['name'] as String,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  centre['area'] as String,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF888880),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              centre['type'] as String,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.directions_rounded, color: color, size: 18),
        ],
      ),
    );
  }
}

class _CertificateSection extends StatefulWidget {
  final Color color;
  final String department;
  const _CertificateSection({required this.color, required this.department});

  @override
  State<_CertificateSection> createState() => _CertificateSectionState();
}

class _CertificateSectionState extends State<_CertificateSection> {
  bool _uploaded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.color.withOpacity(0.1),
            widget.color.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                color: widget.color,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Completion Certificate',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Issued by authorised ${widget.department} personnel',
                      style: TextStyle(fontSize: 11, color: widget.color),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Once you complete all missions at the centre, the authorised doctor/incharge will issue your completion certificate. Upload it here to unlock the next level.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF444440),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _uploaded
                ? null
                : () {
                    setState(() => _uploaded = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Certificate uploaded successfully!',
                        ),
                        backgroundColor: widget.color,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _uploaded ? const Color(0xFF3D7A3A) : widget.color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _uploaded ? Icons.check_rounded : Icons.upload_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _uploaded ? 'Certificate Uploaded ✓' : 'Upload Certificate',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final Color color;
  final String text;
  const _InfoBox({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF444440),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ),
      ],
    );
  }
}

class _MissionsSection extends StatelessWidget {
  final TrainingBlock block;
  const _MissionsSection({required this.block});

  @override
  Widget build(BuildContext context) {
    if (block.missions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.task_alt_rounded,
          label: 'Missions',
          color: block.color,
        ),
        const SizedBox(height: 12),
        ...block.missions.asMap().entries.map(
          (entry) => _MissionCard(
            mission: entry.value,
            index: entry.key,
            blockColor: block.color,
            isLocked: false,
          ),
        ),
      ],
    );
  }
}

class _MissionCard extends StatelessWidget {
  final TrainingMission mission;
  final int index;
  final Color blockColor;
  final bool isLocked;
  const _MissionCard({
    required this.mission,
    required this.index,
    required this.blockColor,
    required this.isLocked,
  });

  static const Map<String, Color> _typeColors = {
    'quiz': Color(0xFF2A7ABD),
    'drill': Color(0xFFB84A00),
    'practical': Color(0xFF2E6B4F),
    'puzzle': Color(0xFF6A3FA0),
    'operation': Color(0xFF8B1A1A),
    'video': Color(0xFF0D5B8E),
    'certificate': Color(0xFFC79000),
  };
  static const Map<String, IconData> _typeIcons = {
    'quiz': Icons.quiz_rounded,
    'drill': Icons.fitness_center_rounded,
    'practical': Icons.handshake_rounded,
    'puzzle': Icons.extension_rounded,
    'operation': Icons.crisis_alert_rounded,
    'video': Icons.play_circle_rounded,
    'certificate': Icons.workspace_premium_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColors[mission.type] ?? blockColor;
    final typeIcon = _typeIcons[mission.type] ?? Icons.task_rounded;
    final bool isCert = mission.type == 'certificate';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCert ? const Color(0xFFFFFDE7) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: mission.completed
              ? const Color(0xFF3D7A3A).withOpacity(0.3)
              : (isCert
                    ? const Color(0xFFC79000).withOpacity(0.4)
                    : const Color(0xFFE8E4DF)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              mission.completed ? Icons.check_rounded : typeIcon,
              color: mission.completed ? const Color(0xFF3D7A3A) : typeColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mission.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        mission.type.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: typeColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (mission.durationMin > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${mission.durationMin} min',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF888880),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Text(
                      '+${mission.xp} XP',
                      style: TextStyle(
                        fontSize: 11,
                        color: blockColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (mission.score != null)
            Column(
              children: [
                Text(
                  mission.score!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3D7A3A),
                  ),
                ),
                const Text(
                  'score',
                  style: TextStyle(fontSize: 9, color: Color(0xFF888880)),
                ),
              ],
            )
          else if (!mission.completed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isCert ? const Color(0xFFC79000) : blockColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isCert ? 'Upload' : 'Start',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
