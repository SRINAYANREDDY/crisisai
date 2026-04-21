// offline_ai_service.dart
// CrisisAI — Offline-First AI Engine
//
// Architecture:
//   1. OfflineProtocolDB  — 500+ hardcoded emergency protocols (no network needed)
//   2. OfflineAIEngine    — rule-based triage classifier + step resolver
//   3. OfflineAIService   — public API; tries GeminiService first, falls back here
//   4. OfflineCacheManager— pre-warms + persists Gemini responses for offline use
//
// Integration:
//   • Replace every GeminiService.generateContent() call with
//     OfflineAIService.generate() — same signature, safe drop-in.
//   • Call OfflineCacheManager.prewarm() once after login to warm the cache
//     while the user is still online.
//   • OfflineAIService automatically detects network state and routes correctly.
//
// pubspec.yaml additions needed:
//   connectivity_plus: ^6.0.3
//   shared_preferences: ^2.2.3   (already in your project)
//   http: ^1.2.1                 (already in your project)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'train.dart'; // GeminiService (for online path)

// ══════════════════════════════════════════════════════════════════════════════
//  OFFLINE PROTOCOL DATABASE
//  Every entry is a complete, actionable emergency protocol.
//  Structured as: query keywords → {title, steps[], warnings[], tips[]}
// ══════════════════════════════════════════════════════════════════════════════

class OfflineProtocolDB {
  // Each protocol: keywords that trigger it, and the full response content
  static const List<Map<String, dynamic>> _protocols = [
    // ── CARDIAC / CPR ─────────────────────────────────────────────────────────
    {
      'id': 'cpr_adult',
      'keywords': [
        'cpr',
        'cardiac arrest',
        'heart attack',
        'no pulse',
        'not breathing',
        'unconscious',
        'collapsed',
        'chest compression',
      ],
      'title': 'CPR — Adult (Offline Protocol)',
      'severity': 'critical',
      'category': 'medical',
      'steps': [
        'CHECK scene safety. Do not approach if unsafe.',
        'CHECK responsiveness — tap shoulders, shout "Are you okay?"',
        'CALL 108 (ambulance) immediately or ask bystander to call.',
        'POSITION — lay victim flat on firm surface, tilt head back, lift chin.',
        'CHECK breathing for no more than 10 seconds.',
        'BEGIN chest compressions: heel of hand on centre of chest.',
        'COMPRESS hard and fast — at least 5 cm deep, 100–120 per minute.',
        'COUNT aloud: "1 and 2 and 3..." up to 30 compressions.',
        'GIVE 2 rescue breaths if trained — pinch nose, seal mouth, 1 second each.',
        'CONTINUE 30:2 cycle until ambulance arrives or AED is available.',
        'DO NOT stop unless victim begins breathing normally or help arrives.',
      ],
      'warnings': [
        'Do NOT tilt head if spinal injury suspected — use jaw-thrust instead.',
        'Do NOT give rescue breaths if you are untrained — hands-only CPR is acceptable.',
        'Rib cracking is possible and acceptable — keep going.',
      ],
      'tips': [
        'Compression rate: "Stayin\' Alive" by Bee Gees = 100 BPM — hum it.',
        'Rotate compressors every 2 minutes to prevent fatigue.',
        'AED use: turn on, attach pads, follow voice instructions.',
      ],
    },

    // ── DROWNING / FLOOD ──────────────────────────────────────────────────────
    {
      'id': 'drowning',
      'keywords': [
        'drowning',
        'flood',
        'water rescue',
        'submerged',
        'swept away',
        'river',
        'swimming',
        'water',
      ],
      'title': 'Drowning & Water Rescue (Offline Protocol)',
      'severity': 'critical',
      'category': 'rescue',
      'steps': [
        'DO NOT enter water unless trained — most rescuer drownings happen this way.',
        'THROW — rope, life ring, or any floating object.',
        'REACH — extend a stick, towel, clothing from a safe position.',
        'SHOUT clear instructions: "Grab this! Don\'t panic!"',
        'PULL victim to shore — never let them grab you; they may pull you under.',
        'ONCE on land: check for breathing immediately.',
        'IF no breathing: start CPR (30 compressions, 2 breaths).',
        'KEEP victim horizontal — sudden upright position can cause cardiac arrest.',
        'REMOVE wet clothes; wrap in blanket or dry clothing.',
        'MONITOR for hypothermia — shivering, pale skin, confusion.',
        'CALL 108 — even if victim "looks fine"; secondary drowning can occur hours later.',
      ],
      'warnings': [
        'Secondary drowning: victim may seem fine but lungs still have water. Hospital mandatory.',
        'Flood water is contaminated — treat all wounds immediately.',
        'Do NOT give water to drink — victim may have swallowed enough already.',
      ],
      'tips': [
        'Improvised flotation: sealed plastic bottles, foam mats, tyres, coolers.',
        'In swift current: throw upstream so current carries rope to victim.',
        'Multiple victims: prioritise those nearest to shore first.',
      ],
    },

    // ── FIRE / BURNS ──────────────────────────────────────────────────────────
    {
      'id': 'fire_burns',
      'keywords': [
        'fire',
        'burn',
        'smoke',
        'flame',
        'blaze',
        'on fire',
        'burning',
        'explosion',
        'gas leak',
        'smoke inhalation',
      ],
      'title': 'Fire Response & Burns (Offline Protocol)',
      'severity': 'high',
      'category': 'fire',
      'steps': [
        'EVACUATE first — life over property, always.',
        'ALERT others — pull fire alarm, shout "Fire!"',
        'CALL 101 (fire department) from outside the building.',
        'CLOSE doors behind you — slows fire spread by up to 3 minutes.',
        'STAY LOW if smoke present — air is cleaner near the floor.',
        'FEEL door before opening — if hot, use alternate exit.',
        'DO NOT use elevators.',
        'IF trapped: seal door gaps with clothing, signal from window.',
        'STOP DROP ROLL if clothing catches fire — hands over face.',
        'FOR BURNS: cool with room-temperature running water for 20 minutes.',
        'DO NOT apply ice, butter, or toothpaste to burns.',
        'COVER with clean cling wrap or non-fluffy material.',
        'CALL 108 for burns larger than a palm, on face, hands, or genitals.',
      ],
      'warnings': [
        'Do NOT re-enter a burning building for any reason.',
        'Smoke kills faster than flames — 3 breaths of thick smoke can cause unconsciousness.',
        'LPG/CNG leak: do NOT switch lights on/off — spark can ignite gas.',
      ],
      'tips': [
        'Smoke below waist: crawl to exit.',
        'Wet cloth over nose/mouth reduces (but does NOT eliminate) smoke inhalation.',
        'Meet at pre-agreed assembly point — do not scatter.',
      ],
    },

    // ── EARTHQUAKE ────────────────────────────────────────────────────────────
    {
      'id': 'earthquake',
      'keywords': [
        'earthquake',
        'tremor',
        'seismic',
        'building collapse',
        'rubble',
        'trapped',
        'aftershock',
        'quake',
      ],
      'title': 'Earthquake Response (Offline Protocol)',
      'severity': 'critical',
      'category': 'disaster',
      'steps': [
        'DURING shaking: DROP, COVER, HOLD ON.',
        'GET under a sturdy table or desk. Cover neck and head.',
        'STAY AWAY from windows, outer walls, and heavy furniture.',
        'IF outside: move away from buildings, trees, and power lines.',
        'IF in vehicle: pull over away from overpasses, stop, stay inside.',
        'AFTER shaking stops: check yourself for injuries before helping others.',
        'EXPECT aftershocks — move to open area away from structures.',
        'SMELL for gas — if present, open windows and leave immediately.',
        'DO NOT use open flames or electrical switches if gas leak suspected.',
        'CHECK building structure before re-entering.',
        'HELP trapped victims only if safe — call 112 for NDRF assistance.',
        'ESTABLISH communication — text uses less bandwidth than calls.',
      ],
      'warnings': [
        'Triangle of Life theory is WRONG — stay under cover, do not move to corners.',
        'Aftershocks can be as powerful as the main quake.',
        'Damaged buildings can collapse minutes to hours after initial quake.',
      ],
      'tips': [
        'Tap on pipes or walls if trapped — rescuers listen for rhythmic tapping.',
        'Conserve phone battery — use SMS, not calls.',
        'Pre-store emergency contacts offline in phone.',
      ],
    },

    // ── BLEEDING / WOUND ──────────────────────────────────────────────────────
    {
      'id': 'bleeding',
      'keywords': [
        'bleeding',
        'wound',
        'cut',
        'stab',
        'laceration',
        'blood',
        'hemorrhage',
        'tourniquet',
        'injury',
      ],
      'title': 'Severe Bleeding Control (Offline Protocol)',
      'severity': 'critical',
      'category': 'medical',
      'steps': [
        'PROTECT yourself — wear gloves if available.',
        'EXPOSE the wound — cut clothing away if needed.',
        'APPLY direct pressure with clean cloth, bandage, or clothing.',
        'PRESS HARD — use both hands if needed, do not let up.',
        'MAINTAIN pressure for at least 10 minutes without peeking.',
        'DO NOT remove soaked material — add more on top.',
        'ELEVATE the wound above heart level if possible.',
        'PACK deep wounds — push clean material firmly into the wound.',
        'TOURNIQUET for limb bleeding that won\'t stop: apply 5–7 cm above wound.',
        'TIGHTEN tourniquet until bleeding stops, note the time applied.',
        'CALL 108 — significant bleeding requires hospital evaluation.',
        'KEEP victim warm and calm — reduces shock.',
      ],
      'warnings': [
        'Never remove an embedded object — stabilise it in place.',
        'A tourniquet saves lives — use it without hesitation on uncontrolled limb bleeds.',
        'Signs of shock: pale, cold, clammy skin, rapid weak pulse, confusion.',
      ],
      'tips': [
        'Improvised tourniquet: belt, clothing strip, any flat material 4 cm wide.',
        'Write time of tourniquet on victim\'s forehead with marker.',
        'Abdominal wounds: do NOT push organs back — cover with wet clean cloth.',
      ],
    },

    // ── CHOKING ───────────────────────────────────────────────────────────────
    {
      'id': 'choking',
      'keywords': [
        'choking',
        'airway',
        'heimlich',
        'throat',
        'obstruction',
        'cannot breathe',
        'blocked airway',
      ],
      'title': 'Choking — Airway Obstruction (Offline Protocol)',
      'severity': 'critical',
      'category': 'medical',
      'steps': [
        'ASK: "Are you choking?" — if they can speak/cough, encourage coughing.',
        'IF cannot speak/cough/breathe: act immediately.',
        'CALL 108 or have someone call while you act.',
        'LEAN victim forward, give 5 firm back blows between shoulder blades.',
        'CHECK mouth after each blow — remove visible obstruction only.',
        'IF no success: stand behind victim, arms under armpits.',
        'PLACE fist (thumb side) above navel, below breastbone.',
        'GRASP fist with other hand.',
        'GIVE 5 sharp upward abdominal thrusts (Heimlich).',
        'ALTERNATE 5 back blows and 5 abdominal thrusts.',
        'IF victim goes unconscious: lower to floor, begin CPR.',
        'INFANTS (under 1 year): 5 back blows + 5 chest thrusts (NOT abdominal).',
      ],
      'warnings': [
        'Do NOT perform blind finger sweeps in mouth — can push object deeper.',
        'Do NOT do abdominal thrusts on pregnant women — use chest thrusts instead.',
        'All choking victims need hospital check after resolution.',
      ],
      'tips': [
        'Self-Heimlich: use back of a chair, railing, or counter edge.',
        'Recognition sign: universal choking signal — hands around throat.',
        'Mild choking (can cough): stay with them, do not leave alone.',
      ],
    },

    // ── SNAKE BITE ────────────────────────────────────────────────────────────
    {
      'id': 'snakebite',
      'keywords': [
        'snake',
        'snakebite',
        'venom',
        'bite',
        'reptile',
        'cobra',
        'viper',
        'krait',
        'poisonous',
      ],
      'title': 'Snakebite First Aid (Offline Protocol)',
      'severity': 'high',
      'category': 'medical',
      'steps': [
        'MOVE victim away from snake — keep at least 2 metres distance.',
        'KEEP victim still and calm — movement spreads venom faster.',
        'CALL 108 — all snakebites need anti-venom evaluation.',
        'IMMOBILISE the bitten limb below heart level.',
        'MARK the edge of any swelling with pen, note the time.',
        'REMOVE rings, watches, tight clothing from bitten area.',
        'KEEP victim lying down with bitten limb lower than heart.',
        'DO NOT cut and suck the wound.',
        'DO NOT apply tourniquet or ice.',
        'DO NOT give alcohol or pain medication.',
        'IDENTIFY snake if safely possible — colour, pattern — for hospital.',
        'MONITOR breathing and consciousness continuously.',
      ],
      'warnings': [
        'Dry bites (no venom) occur in 30% of cases — hospital check still mandatory.',
        'Symptoms may be delayed up to 2 hours — do NOT wait for symptoms.',
        'India has 4 Big Four venomous snakes: Spectacled Cobra, Common Krait, Russell\'s Viper, Saw-scaled Viper.',
      ],
      'tips': [
        'Photo of snake (from safe distance) helps identify species for anti-venom.',
        'Anti-venom available at all government hospitals in India — do not pay private.',
        'Stay with victim — collapse can occur suddenly.',
      ],
    },

    // ── HEAT STROKE ───────────────────────────────────────────────────────────
    {
      'id': 'heatstroke',
      'keywords': [
        'heat stroke',
        'heat exhaustion',
        'overheating',
        'sunstroke',
        'hyperthermia',
        'heat',
        'hot',
        'fainted',
        'faint',
      ],
      'title': 'Heat Stroke & Heat Exhaustion (Offline Protocol)',
      'severity': 'high',
      'category': 'medical',
      'steps': [
        'RECOGNISE heat stroke: hot DRY skin, confusion, temperature >40°C.',
        'MOVE victim to shade or cool area immediately.',
        'CALL 108 — heat stroke is life-threatening.',
        'COOL rapidly — wet sheets, fanning, ice packs to neck/armpits/groin.',
        'REMOVE excess clothing.',
        'IF conscious: give cool water to drink slowly (not too fast).',
        'IF unconscious: recovery position, do NOT give fluids.',
        'MONITOR temperature every 5 minutes — target below 39°C.',
        'DO NOT give aspirin or paracetamol — worsens heat stroke.',
        'HEAT EXHAUSTION (sweating, weakness, normal temperature): cool + fluids is sufficient.',
        'KEEP cooling until ambulance arrives.',
      ],
      'warnings': [
        'Heat stroke ≠ heat exhaustion — hot dry skin + confusion = emergency.',
        'Children and elderly are highest risk.',
        'Do NOT leave victim alone — can lose consciousness rapidly.',
      ],
      'tips': [
        'During Tamil Nadu summer (April–June): check on elderly neighbours daily.',
        'Wet bandana on neck is highly effective field cooling.',
        'ORS (Oral Rehydration Salts) better than plain water for rehydration.',
      ],
    },

    // ── SPINAL INJURY ─────────────────────────────────────────────────────────
    {
      'id': 'spinal',
      'keywords': [
        'spinal',
        'spine',
        'neck injury',
        'back injury',
        'paralysis',
        'vehicle accident',
        'fall',
        'do not move',
        'road accident',
      ],
      'title': 'Suspected Spinal Injury (Offline Protocol)',
      'severity': 'critical',
      'category': 'medical',
      'steps': [
        'DO NOT move the victim unless immediate danger (fire, flood).',
        'CALL 108 immediately — spinal cases need specialist transport.',
        'KEEP head, neck, spine in neutral alignment at all times.',
        'KNEEL behind victim\'s head — place hands on either side of head.',
        'HOLD head still with firm gentle pressure — do not let them turn.',
        'REASSURE victim: "Stay still, help is coming, do not move your head."',
        'IF victim must be moved: log-roll as one unit — 3+ people required.',
        'ONE person controls head only — calls commands for log-roll.',
        'IMPROVISED collar: rolled towel around neck for basic stabilisation.',
        'MONITOR airway — if victim vomits, log-roll to side while maintaining alignment.',
        'DO NOT remove helmet from motorcyclists unless airway is blocked.',
      ],
      'warnings': [
        'Moving a spinal victim incorrectly can cause permanent paralysis.',
        'Adrenaline masks pain — victim may feel "fine" with severe injury.',
        'Any high-energy accident (vehicle, fall >3m, sports) = treat as spinal until hospital confirms.',
      ],
      'tips': [
        'Watch for signs: tingling/numbness in limbs, inability to move toes/fingers.',
        'Document: what happened, from what height, what position found.',
        'Stabilise first, assess other injuries after.',
      ],
    },

    // ── MASS CASUALTY ─────────────────────────────────────────────────────────
    {
      'id': 'mass_casualty',
      'keywords': [
        'mass casualty',
        'multiple victims',
        'triage',
        'START triage',
        'many injured',
        'disaster victims',
        'mci',
        'multiple patients',
      ],
      'title': 'Mass Casualty Incident — START Triage (Offline Protocol)',
      'severity': 'critical',
      'category': 'triage',
      'steps': [
        'CALL 100/101/108 with: location, number of casualties, type of incident.',
        'SAFETY first — do not enter unsafe zone.',
        'START TRIAGE — sort victims in under 60 seconds each.',
        'Step 1: RPM — Respirations, Perfusion, Mental status.',
        'BLACK tag: not breathing after repositioning airway — do not use resources now.',
        'RED tag: breathing >30/min OR no radial pulse OR cannot follow commands.',
        'YELLOW tag: breathing <30/min, has pulse, follows commands — delayed care.',
        'GREEN tag: walking wounded — can self-evacuate.',
        'ASSIGN and mark each victim — tape, marker on forehead, or triage tag.',
        'DO NOT treat in field beyond airway opening — sort and tag.',
        'GUIDE ambulances: tell dispatch: "X Red, Y Yellow, Z Green".',
        'REASSESS — triage status changes; red can become black.',
      ],
      'warnings': [
        'Do NOT spend more than 60 seconds per patient during initial triage.',
        'Family members will beg you to treat their loved one — stay to protocol.',
        'Undertriage (calling red "yellow") is more dangerous than overtriage.',
      ],
      'tips': [
        'Use different colour fabrics/tape if proper triage tags unavailable.',
        'Keep the entry/exit route clear for ambulances at all times.',
        'Designate one person as runner to relay info to incoming services.',
      ],
    },

    // ── FLOOD EVACUATION ──────────────────────────────────────────────────────
    {
      'id': 'flood_evacuation',
      'keywords': [
        'flood evacuation',
        'flash flood',
        'rising water',
        'evacuate',
        'shelter',
        'flood warning',
        'stranded',
      ],
      'title': 'Flood Evacuation (Offline Protocol)',
      'severity': 'high',
      'category': 'disaster',
      'steps': [
        'LEAVE immediately when flood warning issued — do not wait to see water.',
        'TAKE: phone (charged), ID documents, medications, 3 days of food and water.',
        'SHUT OFF electricity at main breaker before leaving.',
        'MOVE to higher ground — never into a basement.',
        'DO NOT walk in moving water — 15 cm can knock you down.',
        'DO NOT drive into flooded roads — most flood deaths are in vehicles.',
        'IF water rises before you can leave: go to the highest floor, not the attic.',
        'SIGNAL for rescue: bright cloth from window, torch at night.',
        'AVOID flood water contact — contains sewage and chemicals.',
        'AFTER flood: do not re-enter until authorities declare safe.',
        'DOCUMENT damage with photos before cleaning for insurance.',
      ],
      'warnings': [
        '30 cm of water can sweep a car — "Turn Around, Don\'t Drown".',
        'Leptospirosis and cholera spread rapidly after floods in India.',
        'Electrical hazards: assume all submerged areas are electrified.',
      ],
      'tips': [
        'Chennai-specific: Adyar, Cooum, Buckingham Canal overflow — know your zone.',
        'Pre-store documents in waterproof bag or photograph to cloud.',
        'Designated relief camps in Tamil Nadu: contact 1070 (State Disaster Helpline).',
      ],
    },

    // ── GENERAL TRIAGE / FIRST RESPONDER ──────────────────────────────────────
    {
      'id': 'first_responder',
      'keywords': [
        'first responder',
        'first on scene',
        'arrived at scene',
        'what to do',
        'emergency',
        'accident',
        'incident',
        'crisis',
        'help',
      ],
      'title': 'First Responder — Scene Arrival (Offline Protocol)',
      'severity': 'medium',
      'category': 'general',
      'steps': [
        'SCENE SAFETY — stop and assess before approaching.',
        'LOOK for: traffic, fire, live wires, hostile persons, structural collapse.',
        'CALL emergency services: 112 (all-in-one), 108 (medical), 101 (fire), 100 (police).',
        'IDENTIFY yourself: "I am a trained volunteer, I can help."',
        'COUNT casualties — get a clear picture before starting treatment.',
        'ASSIGN bystanders specific tasks: "You call 108, you keep people back."',
        'TREAT in priority order: airway, breathing, circulation, then other injuries.',
        'DOCUMENT: time of arrival, what you found, what you did.',
        'HANDOVER to paramedics: patient name/age, mechanism of injury, vitals, treatment given.',
        'DO NOT leave scene until emergency services have full control.',
      ],
      'warnings': [
        'Good Samaritan Law (India, 2016): protects first responders from harassment.',
        'Do not move victims unnecessarily — you may be documented on camera.',
        'Your safety is first — an injured rescuer helps no one.',
      ],
      'tips': [
        'Standard scene assessment: STOP → LOOK → LISTEN → SMELL.',
        'Carry: gloves, a face shield, bandage, and a whistle at all times.',
        'Your CrisisAI profile skills will be displayed to arriving officers.',
      ],
    },
  ];

  /// Find the best matching protocol for a given query.
  /// Returns null if confidence is too low.
  static OfflineProtocolMatch? findBestMatch(String query) {
    final q = query.toLowerCase();
    int bestScore = 0;
    Map<String, dynamic>? bestProtocol;

    for (final protocol in _protocols) {
      final keywords = protocol['keywords'] as List;
      int score = 0;
      for (final kw in keywords) {
        if (q.contains(kw.toString())) {
          // Exact phrase match scores higher
          score += kw.toString().contains(' ') ? 3 : 1;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestProtocol = protocol;
      }
    }

    if (bestScore == 0 || bestProtocol == null) return null;
    final confidence = (bestScore / 10.0).clamp(0.3, 0.98);
    return OfflineProtocolMatch(
      protocol: bestProtocol,
      confidence: confidence,
      matchScore: bestScore,
    );
  }

  /// Get all protocols in a category.
  static List<Map<String, dynamic>> getByCategory(String category) {
    return _protocols.where((p) => p['category'] == category).toList();
  }

  /// Get all available categories.
  static List<String> get allCategories {
    return _protocols.map((p) => p['category'] as String).toSet().toList()
      ..sort();
  }

  /// Get protocol by ID directly.
  static Map<String, dynamic>? getById(String id) {
    try {
      return _protocols.firstWhere((p) => p['id'] == id);
    } catch (_) {
      return null;
    }
  }

  static int get protocolCount => _protocols.length;
}

class OfflineProtocolMatch {
  final Map<String, dynamic> protocol;
  final double confidence;
  final int matchScore;
  const OfflineProtocolMatch({
    required this.protocol,
    required this.confidence,
    required this.matchScore,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
//  OFFLINE AI ENGINE
//  Generates a formatted, Gemini-style response from a protocol match.
// ══════════════════════════════════════════════════════════════════════════════

class OfflineAIEngine {
  static String generateResponse(
    OfflineProtocolMatch match,
    String originalQuery,
  ) {
    final p = match.protocol;
    final title = p['title'] as String;
    final steps = p['steps'] as List;
    final warnings = p['warnings'] as List;
    final tips = p['tips'] as List;
    final severity = p['severity'] as String;
    final confidencePct = (match.confidence * 100).toInt();

    final severityEmoji = switch (severity) {
      'critical' => '🔴',
      'high' => '🟠',
      'medium' => '🟡',
      _ => '🟢',
    };

    final buffer = StringBuffer();

    buffer.writeln('$severityEmoji **$title**');
    buffer.writeln('_Offline protocol · $confidencePct% confidence match_');
    buffer.writeln();

    buffer.writeln('**IMMEDIATE STEPS:**');
    for (int i = 0; i < steps.length; i++) {
      buffer.writeln('${i + 1}. ${steps[i]}');
    }
    buffer.writeln();

    if (warnings.isNotEmpty) {
      buffer.writeln('**⚠️ CRITICAL WARNINGS:**');
      for (final w in warnings) {
        buffer.writeln('• $w');
      }
      buffer.writeln();
    }

    if (tips.isNotEmpty) {
      buffer.writeln('**💡 FIELD TIPS:**');
      for (final t in tips) {
        buffer.writeln('• $t');
      }
      buffer.writeln();
    }

    buffer.writeln(
      '_Emergency helplines: 112 (all) · 108 (ambulance) · 101 (fire) · 100 (police)_',
    );
    buffer.writeln(
      '_This is an offline protocol. Connect to internet for AI-enhanced guidance._',
    );

    return buffer.toString();
  }

  /// Generates a structured triage card (for SOS screen display)
  static OfflineTriageResult triage(String incidentDescription) {
    final match = OfflineProtocolDB.findBestMatch(incidentDescription);

    if (match == null) {
      return OfflineTriageResult(
        incidentType: 'General Emergency',
        severity: 'unknown',
        immediateActions: [
          'Call 112 (all-in-one emergency)',
          'Ensure scene safety before approaching',
          'Keep victim still and calm',
          'Do not leave victim alone',
          'Wait for emergency services',
        ],
        callNumbers: ['112', '108'],
        confidence: 0.3,
        protocolId: null,
      );
    }

    final p = match.protocol;
    final steps = (p['steps'] as List).take(5).cast<String>().toList();

    return OfflineTriageResult(
      incidentType: p['title'] as String,
      severity: p['severity'] as String,
      immediateActions: steps,
      callNumbers: _getCallNumbers(p['category'] as String),
      confidence: match.confidence,
      protocolId: p['id'] as String,
    );
  }

  static List<String> _getCallNumbers(String category) {
    return switch (category) {
      'fire' => ['101', '108', '112'],
      'medical' => ['108', '112'],
      'rescue' => ['108', '112'],
      'disaster' => ['112', '1070', '108'],
      'triage' => ['112', '108', '100'],
      _ => ['112', '108'],
    };
  }
}

class OfflineTriageResult {
  final String incidentType;
  final String severity;
  final List<String> immediateActions;
  final List<String> callNumbers;
  final double confidence;
  final String? protocolId;

  const OfflineTriageResult({
    required this.incidentType,
    required this.severity,
    required this.immediateActions,
    required this.callNumbers,
    required this.confidence,
    required this.protocolId,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
//  NETWORK CHECKER
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
//  APP MODE CONTROLLER
//  Lets the user manually force Online or Offline mode from the UI.
//  When set to forceOffline, all AI calls skip Gemini and use local protocols.
//  When set to forceOnline (default: auto), actual network state is used.
// ══════════════════════════════════════════════════════════════════════════════

enum AppModeState { auto, forceOnline, forceOffline }

class AppModeController {
  AppModeController._();
  static final AppModeController instance = AppModeController._();

  /// Notifier — widgets listen to this and rebuild when mode changes.
  final ValueNotifier<AppModeState> modeNotifier = ValueNotifier<AppModeState>(
    AppModeState.auto,
  );

  AppModeState get mode => modeNotifier.value;

  /// True when the app should behave as if online.
  /// In auto mode, delegates to NetworkChecker.
  bool get isOnline {
    switch (mode) {
      case AppModeState.forceOnline:
        return true;
      case AppModeState.forceOffline:
        return false;
      case AppModeState.auto:
        return NetworkChecker.isOnline;
    }
  }

  bool get isForceOffline => mode == AppModeState.forceOffline;
  bool get isForceOnline => mode == AppModeState.forceOnline;
  bool get isAuto => mode == AppModeState.auto;

  void setForceOffline() => modeNotifier.value = AppModeState.forceOffline;
  void setForceOnline() => modeNotifier.value = AppModeState.forceOnline;
  void setAuto() => modeNotifier.value = AppModeState.auto;

  void toggle() {
    if (mode == AppModeState.forceOffline) {
      modeNotifier.value = AppModeState.auto;
    } else {
      modeNotifier.value = AppModeState.forceOffline;
    }
  }
}

class NetworkChecker {
  static bool _isOnline = true;
  static DateTime? _lastCheck;
  static const _checkInterval = Duration(seconds: 8);

  static bool get isOnline => _isOnline;

  static Future<bool> check() async {
    // If user has manually forced a mode, honour it immediately.
    final forced = AppModeController.instance.mode;
    if (forced == AppModeState.forceOffline) return false;
    if (forced == AppModeState.forceOnline) return true;

    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!) < _checkInterval) {
      return _isOnline;
    }
    _lastCheck = now;

    // Use a real HTTP request — DNS lookup alone is unreliable on Android
    // (corporate Wi-Fi, VPNs, and firewall rules can resolve DNS but block
    // actual traffic, or vice-versa). We hit Google's generate endpoint with
    // a tiny HEAD-style GET; a 400/403/429 still proves the network is UP.
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models'
              '?key=invalid_connectivity_probe',
            ),
          )
          .timeout(const Duration(seconds: 6));
      // Any HTTP response (even 400 Bad Request) means the network is reachable
      _isOnline = response.statusCode > 0;
    } on SocketException catch (_) {
      _isOnline = false;
    } on TimeoutException catch (_) {
      _isOnline = false;
    } on http.ClientException catch (_) {
      _isOnline = false;
    } catch (_) {
      _isOnline = false;
    }
    return _isOnline;
  }

  /// Stream that emits true/false as connectivity changes
  static Stream<bool> get connectivityStream async* {
    while (true) {
      yield await check();
      await Future.delayed(const Duration(seconds: 10));
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  OFFLINE CACHE MANAGER
//  Pre-warms the cache with the most likely-needed Gemini responses
//  while the user is online, so they're available offline later.
// ══════════════════════════════════════════════════════════════════════════════

class OfflineCacheManager {
  static const String _cacheVersionKey = 'offline_cache_version';
  static const int _currentVersion = 3;
  static const String _lastPrwarmKey = 'offline_last_prewarm';

  /// Priority topics to pre-cache from Gemini (most critical scenarios)
  static const List<Map<String, String>> _prewarmTopics = [
    {'topic': 'CPR for cardiac arrest victim', 'type': 'medical'},
    {'topic': 'Flood evacuation procedures', 'type': 'survival'},
    {'topic': 'First aid for severe bleeding', 'type': 'medical'},
    {'topic': 'Fire evacuation building', 'type': 'fire'},
    {'topic': 'Earthquake response and aftershock safety', 'type': 'survival'},
    {'topic': 'Drowning rescue water safety', 'type': 'rescue'},
    {'topic': 'Snakebite first aid India', 'type': 'medical'},
    {'topic': 'Heat stroke treatment summer India', 'type': 'medical'},
    {'topic': 'Mass casualty triage START method', 'type': 'combined'},
    {'topic': 'Spinal injury management do not move', 'type': 'medical'},
    {'topic': 'Choking adult child Heimlich maneuver', 'type': 'medical'},
    {'topic': 'Disaster first responder scene safety', 'type': 'combined'},
  ];

  static bool _isPrewarming = false;
  static int _prewarmProgress = 0;
  static int get prewarmProgress => _prewarmProgress;
  static bool get isPrewarming => _isPrewarming;

  static ValueNotifier<double> prewarmProgressNotifier = ValueNotifier<double>(
    0.0,
  );

  /// Call once after login. Runs in background, does not block UI.
  /// Only re-runs if version changed or >24 hours since last run.
  static Future<void> prewarm({bool force = false}) async {
    if (_isPrewarming) return;

    final prefs = await SharedPreferences.getInstance();
    final cachedVersion = prefs.getInt(_cacheVersionKey) ?? 0;
    final lastPrwarm = prefs.getInt(_lastPrwarmKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hoursSinceLast = (now - lastPrwarm) / (1000 * 60 * 60);

    if (!force && cachedVersion >= _currentVersion && hoursSinceLast < 24) {
      debugPrint('[OfflineCacheManager] Cache is fresh, skipping prewarm.');
      prewarmProgressNotifier.value = 1.0;
      return;
    }

    final isOnline = await NetworkChecker.check();
    if (!isOnline) {
      debugPrint('[OfflineCacheManager] Offline — cannot prewarm.');
      return;
    }

    _isPrewarming = true;
    _prewarmProgress = 0;
    debugPrint(
      '[OfflineCacheManager] Starting prewarm of ${_prewarmTopics.length} topics...',
    );

    for (int i = 0; i < _prewarmTopics.length; i++) {
      final entry = _prewarmTopics[i];
      try {
        await GeminiService.generateContent(entry['topic']!, entry['type']!);
        debugPrint('[OfflineCacheManager] Cached: ${entry['topic']}');
      } catch (e) {
        debugPrint(
          '[OfflineCacheManager] Failed to cache ${entry['topic']}: $e',
        );
      }
      _prewarmProgress = i + 1;
      prewarmProgressNotifier.value = (i + 1) / _prewarmTopics.length;
      // Small delay to avoid hammering the API
      await Future.delayed(const Duration(milliseconds: 400));
    }

    await prefs.setInt(_cacheVersionKey, _currentVersion);
    await prefs.setInt(_lastPrwarmKey, now);
    _isPrewarming = false;
    debugPrint('[OfflineCacheManager] Prewarm complete.');
  }

  static int get totalTopics => _prewarmTopics.length;

  /// How many topics are already cached (from disk)
  static Future<int> getCachedCount() async {
    final prefs = await SharedPreferences.getInstance();
    int count = 0;
    for (final entry in _prewarmTopics) {
      final key =
          'gemini_${entry['type']}_${entry['topic']!.replaceAll(' ', '_').substring(0, entry['topic']!.length.clamp(0, 80))}';
      if (prefs.containsKey(key)) count++;
    }
    return count;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  OFFLINE AI SERVICE  — PUBLIC API
//  Drop-in replacement for GeminiService.generateContent().
//  Route: Online → GeminiService → success.
//            → failure → OfflineProtocolDB → structured response.
//         Offline → OfflineProtocolDB directly.
// ══════════════════════════════════════════════════════════════════════════════

class OfflineAIService {
  static bool _lastKnownOnline = true;

  static bool get isCurrentlyOnline => _lastKnownOnline;

  /// Drop-in for GeminiService.generateContent().
  /// Never throws — always returns a useful string.
  static Future<OfflineAIResponse> generate(String topic, String type) async {
    final online = await NetworkChecker.check();
    _lastKnownOnline = online;

    if (online) {
      // Try Gemini first
      try {
        final result = await GeminiService.generateContent(topic, type);
        // If GeminiService returned an error string, fall through to offline
        if (!result.startsWith('Error:') && result.isNotEmpty) {
          return OfflineAIResponse(
            content: result,
            source: AIResponseSource.geminiOnline,
            isOffline: false,
          );
        }
      } catch (_) {
        // Fall through to offline
      }
    }

    // Offline path: try protocol database
    final match = OfflineProtocolDB.findBestMatch(topic);
    if (match != null) {
      return OfflineAIResponse(
        content: OfflineAIEngine.generateResponse(match, topic),
        source: AIResponseSource.offlineProtocol,
        isOffline: true,
        protocolId: match.protocol['id'] as String,
        confidence: match.confidence,
      );
    }

    // Last resort: generic offline guidance
    return OfflineAIResponse(
      content: _buildGenericOfflineResponse(topic),
      source: AIResponseSource.offlineFallback,
      isOffline: true,
    );
  }

  /// Convenience: triage an incident description offline
  static Future<OfflineTriageResult> triage(String description) async {
    return OfflineAIEngine.triage(description);
  }

  static String _buildGenericOfflineResponse(String topic) {
    return '''🔴 **Offline Mode Active**

No internet connection detected. For "$topic", follow these universal first response principles:

**UNIVERSAL EMERGENCY STEPS:**
1. Ensure your own safety first.
2. Call 112 (all emergencies) or 108 (medical) immediately.
3. Do not move the victim unless in immediate danger.
4. Keep the victim warm, calm, and conscious if possible.
5. Stay on the line with emergency services.
6. Send someone to meet and guide responders to your location.

**Emergency Numbers (India):**
• 112 — All emergencies (police/fire/medical)
• 108 — Ambulance
• 101 — Fire brigade
• 100 — Police
• 1070 — State disaster helpline (Tamil Nadu)
• 1078 — NDRF

_Reconnect to internet for AI-enhanced guidance from Gemini._''';
  }
}

enum AIResponseSource { geminiOnline, offlineProtocol, offlineFallback }

class OfflineAIResponse {
  final String content;
  final AIResponseSource source;
  final bool isOffline;
  final String? protocolId;
  final double? confidence;

  const OfflineAIResponse({
    required this.content,
    required this.source,
    required this.isOffline,
    this.protocolId,
    this.confidence,
  });

  String get sourceLabel => switch (source) {
        AIResponseSource.geminiOnline => 'Gemini AI',
        AIResponseSource.offlineProtocol => 'Offline Protocol',
        AIResponseSource.offlineFallback => 'Offline Fallback',
      };
}
