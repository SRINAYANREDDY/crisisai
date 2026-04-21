// trauma_check_screen.dart
// CrisisAI — AI Post-Trauma Mental Health Check UI
//
// Screens / widgets in this file:
//   1. TraumaCheckSheet        — bottom sheet that shows after a mission (3-step flow)
//   2. TraumaHistoryScreen     — full history of all past check-ins
//   3. TraumaCheckResultScreen — detailed view of one completed session
//   4. _TraumaBannerWidget     — small persistent banner on HomeScreen / profile
//      when a check-in is pending
//
// How to launch:
//   • After mission: TraumaCheckTrigger.onMissionCompleted(...) sets
//     TraumaCheckPending; the HomeScreen listens and calls _launchPendingCheck().
//   • From profile: Navigate to TraumaHistoryScreen directly.
//
// Important: This file intentionally contains NO medical diagnosis.
//   All AI output includes the disclaimer "This is not a clinical assessment."

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';       // AppColors, AppData
import 'trauma_check_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  HOW TO LAUNCH FROM home_screen.dart
//  Add this mixin to _HomeScreenState to listen for pending checks:
//
//  @override
//  void initState() {
//    super.initState();
//    TraumaCheckPending.addListener(_onPendingCheck);
//    // Check immediately on mount in case it was set before navigation
//    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingCheck());
//  }
//
//  @override
//  void dispose() {
//    TraumaCheckPending.removeListener(_onPendingCheck);
//    super.dispose();
//  }
//
//  void _onPendingCheck() {
//    if (!mounted || !TraumaCheckPending.hasPending) return;
//    final ctx = TraumaCheckPending.consume();
//    if (ctx == null) return;
//    Future.delayed(const Duration(milliseconds: 800), () {
//      if (mounted) _launchTraumaCheck(ctx);
//    });
//  }
//
//  void _launchTraumaCheck(CompletedMissionContext ctx) {
//    showModalBottomSheet(
//      context: context,
//      isScrollControlled: true,
//      backgroundColor: Colors.transparent,
//      isDismissible: false,
//      enableDrag: false,
//      builder: (_) => TraumaCheckSheet(mission: ctx),
//    );
//  }
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
//  TRAUMA CHECK SHEET — the 3-step bottom sheet shown after a mission
// ══════════════════════════════════════════════════════════════════════════════

class TraumaCheckSheet extends StatefulWidget {
  final CompletedMissionContext mission;

  const TraumaCheckSheet({super.key, required this.mission});

  @override
  State<TraumaCheckSheet> createState() => _TraumaCheckSheetState();
}

class _TraumaCheckSheetState extends State<TraumaCheckSheet>
    with TickerProviderStateMixin {
  // Phase: intro → q1 → q2 → q3 → analysing → result
  _CheckPhase _phase = _CheckPhase.intro;

  late AnimationController _fadeCtrl;
  late Animation<double> _fade;
  late AnimationController _slideCtrl;
  late Animation<Offset> _slide;

  List<String> _questions = [];
  int _questionIndex = 0;
  final List<TraumaCheckAnswer> _answers = [];
  final TextEditingController _inputCtrl = TextEditingController();
  bool _loadingQuestions = false;
  bool _analysing = false;
  TraumaAnalysisResult? _result;
  late TraumaCheckSession _session;

  static const Color _warmBg = Color(0xFF1A1A2E);
  static const Color _card = Color(0xFF252540);
  static const Color _accent = Color(0xFF7B8FFF);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    _session = TraumaCheckSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      mission: widget.mission,
      answers: const [],
      startedAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  void _animateTransition(VoidCallback fn) {
    _fadeCtrl.reverse().then((_) {
      if (mounted) {
        setState(fn);
        _fadeCtrl.forward();
        _slideCtrl
          ..reset()
          ..forward();
      }
    });
  }

  Future<void> _startCheckin() async {
    _animateTransition(() => _loadingQuestions = true);
    final questions =
        await TraumaCheckEngine.generateQuestions(widget.mission);
    if (mounted) {
      _animateTransition(() {
        _questions = questions;
        _loadingQuestions = false;
        _phase = _CheckPhase.questioning;
        _questionIndex = 0;
      });
    }
  }

  Future<void> _submitAnswer() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();

    final answer = TraumaCheckAnswer(
      question: _questions[_questionIndex],
      answer: text,
      answeredAt: DateTime.now(),
    );
    _answers.add(answer);
    _inputCtrl.clear();

    // Persist partial session
    final updatedSession = _session.copyWith(answers: List.from(_answers));
    _session = updatedSession;
    await TraumaCheckStore.saveSession(_session);

    if (_questionIndex < _questions.length - 1) {
      _animateTransition(() => _questionIndex++);
    } else {
      // All 3 answered — analyse
      _animateTransition(() {
        _phase = _CheckPhase.analysing;
        _analysing = true;
      });
      final result = await TraumaCheckEngine.analyseAnswers(
        mission: widget.mission,
        answers: _answers,
      );
      if (mounted) {
        final completedSession = _session.copyWith(
          riskLevel: result.riskLevel,
          aiSummary: result.summary,
          aiRecommendation: result.recommendation,
          aiNextSteps: result.nextSteps,
          completedAt: DateTime.now(),
          isComplete: true,
        );
        _session = completedSession;
        await TraumaCheckStore.saveSession(_session);

        _animateTransition(() {
          _result = result;
          _analysing = false;
          _phase = _CheckPhase.result;
        });
      }
    }
  }

  void _skipAndClose() {
    HapticFeedback.lightImpact();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: _warmBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad),
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: _buildPhase(),
        ),
      ),
    );
  }

  Widget _buildPhase() {
    return switch (_phase) {
      _CheckPhase.intro => _buildIntro(),
      _CheckPhase.questioning =>
        _loadingQuestions ? _buildLoadingQuestions() : _buildQuestion(),
      _CheckPhase.analysing => _buildAnalysing(),
      _CheckPhase.result => _buildResult(),
    };
  }

  // ── PHASE 0: INTRO ─────────────────────────────────────────────────────────
  Widget _buildIntro() {
    final name = widget.mission.volunteerName.split(' ').first;
    final missionName = widget.mission.missionTitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          const SizedBox(height: 24),
          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: _accent,
              size: 30,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Great work, $name.',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            missionName,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.5),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Before you go — 3 quick questions.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Responding to emergencies can be intense. This 2-minute check-in helps us make sure you\'re okay. Your answers are private.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.65),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _infoRow(
                  Icons.lock_outline_rounded,
                  'Private — only you can see your answers',
                ),
                const SizedBox(height: 8),
                _infoRow(
                  Icons.timer_outlined,
                  'Takes about 2 minutes',
                ),
                const SizedBox(height: 8),
                _infoRow(
                  Icons.auto_awesome,
                  'AI-powered, personalised to your mission',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _primaryButton(
            label: 'Start Check-in',
            onTap: _startCheckin,
            icon: Icons.chat_bubble_outline_rounded,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _skipAndClose,
            child: Text(
              'Skip for now',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.4),
                decoration: TextDecoration.underline,
                decorationColor: Colors.white.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _accent),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  // ── PHASE 0b: LOADING QUESTIONS ────────────────────────────────────────────
  Widget _buildLoadingQuestions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          const SizedBox(height: 48),
          _PulsingIcon(icon: Icons.auto_awesome, color: _accent),
          const SizedBox(height: 24),
          const Text(
            'Personalising your check-in…',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Gemini is crafting questions specific to your mission.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  // ── PHASE 1–3: QUESTIONING ─────────────────────────────────────────────────
  Widget _buildQuestion() {
    if (_questions.isEmpty) return _buildLoadingQuestions();
    final q = _questions[_questionIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _handle(),
          const SizedBox(height: 20),
          // Progress dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _questions.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _questionIndex ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _questionIndex
                      ? _accent
                      : (i < _questionIndex
                          ? _accent.withOpacity(0.5)
                          : Colors.white.withOpacity(0.2)),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          // Question number
          Text(
            'Question ${_questionIndex + 1} of ${_questions.length}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _accent.withOpacity(0.8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          // Question text
          Text(
            q,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          // Input
          Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _accent.withOpacity(0.3)),
            ),
            child: TextField(
              controller: _inputCtrl,
              autofocus: true,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.6,
              ),
              decoration: InputDecoration(
                hintText: 'Share as much or as little as you\'d like…',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 13,
                ),
                contentPadding: const EdgeInsets.all(16),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'There are no right or wrong answers. This is just for you.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 20),
          _primaryButton(
            label: _questionIndex < _questions.length - 1
                ? 'Next question'
                : 'Submit & see results',
            onTap: _submitAnswer,
            icon: _questionIndex < _questions.length - 1
                ? Icons.arrow_forward_rounded
                : Icons.done_rounded,
          ),
          if (_questionIndex == 0) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _skipAndClose,
              child: Center(
                child: Text(
                  'Skip check-in',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.3),
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white.withOpacity(0.2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── PHASE 4: ANALYSING ─────────────────────────────────────────────────────
  Widget _buildAnalysing() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          const SizedBox(height: 48),
          _PulsingIcon(
            icon: Icons.psychology_rounded,
            color: _accent,
            large: true,
          ),
          const SizedBox(height: 24),
          const Text(
            'Analysing your responses…',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Gemini is reviewing what you shared\nand preparing personalised support.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.5),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  // ── PHASE 5: RESULT ────────────────────────────────────────────────────────
  Widget _buildResult() {
    if (_result == null) return const SizedBox.shrink();
    final r = _result!;
    final riskColor = Color(r.riskLevel.colorHex);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _handle(),
          const SizedBox(height: 20),

          // Risk level badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: riskColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: riskColor.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: riskColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    r.riskLevel.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: riskColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Gemini summary
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: _accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Gemini\'s reflection',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _accent,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  r.summary,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Recommendation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: riskColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: riskColor.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _riskIcon(r.riskLevel),
                  color: riskColor,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r.recommendation,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Next steps
          if (r.nextSteps.isNotEmpty) ...[
            const Text(
              'SUGGESTED NEXT STEPS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7B8FFF),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            ...r.nextSteps.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _accent.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${e.key + 1}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _accent,
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
                              color: Colors.white.withOpacity(0.85),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 6),
          ],

          // Immediate escalation — only shown for urgent
          if (r.requiresImmediateEscalation) ...[
            _UrgentResourceCard(),
            const SizedBox(height: 14),
          ],

          // Support resources (always shown, less prominent for clear)
          if (r.riskLevel != TraumaRiskLevel.clear)
            _SupportResourcesCard(riskLevel: r.riskLevel),

          const SizedBox(height: 14),

          // Disclaimer
          Text(
            'This is not a clinical assessment. CrisisAI is a support tool, not a medical or mental health service.',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.3),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          _primaryButton(
            label: 'Done — I\'m okay',
            onTap: () => Navigator.pop(context),
            icon: Icons.check_rounded,
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                // Open history in a new screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TraumaHistoryScreen(),
                  ),
                );
              },
              child: Text(
                'View past check-ins',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.35),
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white.withOpacity(0.2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _riskIcon(TraumaRiskLevel level) => switch (level) {
        TraumaRiskLevel.clear => Icons.check_circle_outline_rounded,
        TraumaRiskLevel.monitor => Icons.bedtime_outlined,
        TraumaRiskLevel.support => Icons.volunteer_activism_outlined,
        TraumaRiskLevel.urgent => Icons.warning_amber_rounded,
      };

  // ── SHARED HELPERS ─────────────────────────────────────────────────────────

  Widget _handle() {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CheckPhase { intro, questioning, analysing, result }

// ══════════════════════════════════════════════════════════════════════════════
//  URGENT RESOURCE CARD
// ══════════════════════════════════════════════════════════════════════════════

class _UrgentResourceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.red.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.phone_in_talk_rounded,
                color: AppColors.red,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Please reach out now',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Based on what you shared, speaking to someone right now would really help. You don\'t have to carry this alone.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.8),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          _CallButton(
            number: 'iCall: 9152987821',
            label: 'iCall India — free counselling',
            color: AppColors.red,
          ),
          const SizedBox(height: 8),
          _CallButton(
            number: 'Vandrevala: 1860-2662-345',
            label: '24/7 mental health helpline',
            color: AppColors.red,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SUPPORT RESOURCES CARD
// ══════════════════════════════════════════════════════════════════════════════

class _SupportResourcesCard extends StatelessWidget {
  final TraumaRiskLevel riskLevel;
  const _SupportResourcesCard({required this.riskLevel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252540),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.volunteer_activism_outlined,
                size: 14,
                color: Colors.white.withOpacity(0.5),
              ),
              const SizedBox(width: 6),
              Text(
                'SUPPORT RESOURCES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withOpacity(0.4),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ResourceRow(
            icon: Icons.phone_outlined,
            title: 'iCall (TISS)',
            subtitle: '9152987821 · Free counselling',
          ),
          _ResourceRow(
            icon: Icons.phone_outlined,
            title: 'Vandrevala Foundation',
            subtitle: '1860-2662-345 · 24/7 helpline',
          ),
          _ResourceRow(
            icon: Icons.phone_outlined,
            title: 'NIMHANS',
            subtitle: '080-46110007 · National helpline',
          ),
          _ResourceRow(
            icon: Icons.language_outlined,
            title: 'Mpower Minds',
            subtitle: 'mpowerminds.com · Online therapy',
          ),
          const SizedBox(height: 4),
          Text(
            'All services are confidential. Reaching out is a sign of strength.',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.3),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _ResourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF7B8FFF)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.45),
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

class _CallButton extends StatelessWidget {
  final String number;
  final String label;
  final Color color;
  const _CallButton({
    required this.number,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Calling $number…'),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        // In production: launchUrl(Uri.parse('tel:${number.replaceAll(RegExp(r'[^0-9]'), '')}'))
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.call_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  number,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TRAUMA HISTORY SCREEN — list of all past check-ins
// ══════════════════════════════════════════════════════════════════════════════

class TraumaHistoryScreen extends StatefulWidget {
  const TraumaHistoryScreen({super.key});

  @override
  State<TraumaHistoryScreen> createState() => _TraumaHistoryScreenState();
}

class _TraumaHistoryScreenState extends State<TraumaHistoryScreen> {
  List<TraumaCheckSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await TraumaCheckStore.loadCompletedSessions();
    if (mounted) setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Mental Health Check-ins',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.red,
                strokeWidth: 2,
              ),
            )
          : _sessions.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.favorite_border_rounded,
            size: 48,
            color: AppColors.textSecondary.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'No check-ins yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Complete a mission to trigger\nyour first wellbeing check-in.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    // Aggregate stats
    final totalSessions = _sessions.length;
    final clearCount =
        _sessions.where((s) => s.riskLevel == TraumaRiskLevel.clear).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.teal.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.teal.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatBit(
                value: '$totalSessions',
                label: 'Total check-ins',
                color: AppColors.teal,
              ),
              Container(
                width: 1,
                height: 36,
                color: AppColors.border,
              ),
              _StatBit(
                value: '$clearCount',
                label: 'All good results',
                color: AppColors.teal,
              ),
              Container(
                width: 1,
                height: 36,
                color: AppColors.border,
              ),
              _StatBit(
                value: '${totalSessions - clearCount}',
                label: 'Support flagged',
                color: AppColors.amber,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'RECENT CHECK-INS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        ..._sessions.map(
          (s) => _SessionCard(
            session: s,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TraumaCheckResultScreen(session: s),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatBit extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatBit({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  final TraumaCheckSession session;
  final VoidCallback onTap;
  const _SessionCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final risk = session.riskLevel ?? TraumaRiskLevel.clear;
    final riskColor = Color(risk.colorHex);
    final date = session.completedAt ?? session.startedAt;
    final dateStr =
        '${date.day}/${date.month}/${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: riskColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.favorite_rounded,
                color: riskColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.mission.missionTitle,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                          color: riskColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          risk.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: riskColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TRAUMA CHECK RESULT SCREEN — detailed view of one session
// ══════════════════════════════════════════════════════════════════════════════

class TraumaCheckResultScreen extends StatelessWidget {
  final TraumaCheckSession session;
  const TraumaCheckResultScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final risk = session.riskLevel ?? TraumaRiskLevel.clear;
    final riskColor = Color(risk.colorHex);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Check-in Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Mission header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF252540),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.mission.missionTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${session.mission.missionType.toUpperCase()} · ${session.mission.durationMinutes} min · ${session.mission.severity.name.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: riskColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        risk.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: riskColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      risk.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Q&A
          const Text(
            'YOUR RESPONSES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7B8FFF),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          ...session.answers.map(
            (a) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF252540),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.question,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    a.answer,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // AI summary
          if (session.aiSummary != null) ...[
            const Text(
              'GEMINI\'S REFLECTION',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7B8FFF),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF252540),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                session.aiSummary!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Next steps
          if (session.aiNextSteps != null &&
              session.aiNextSteps!.isNotEmpty) ...[
            const Text(
              'NEXT STEPS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7B8FFF),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            ...session.aiNextSteps!.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFF7B8FFF).withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${e.key + 1}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7B8FFF),
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
                              color: Colors.white.withOpacity(0.85),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 24),

          Text(
            'This is not a clinical assessment.',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.25),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TRAUMA BANNER — small persistent banner for profile / home screen
//  Shows when a check-in is pending or when last result was high risk
// ══════════════════════════════════════════════════════════════════════════════

class TraumaPendingBanner extends StatefulWidget {
  const TraumaPendingBanner({super.key});

  @override
  State<TraumaPendingBanner> createState() => _TraumaPendingBannerState();
}

class _TraumaPendingBannerState extends State<TraumaPendingBanner> {
  bool _hasPending = false;

  @override
  void initState() {
    super.initState();
    _hasPending = TraumaCheckPending.hasPending;
    TraumaCheckPending.addListener(_onPendingChange);
  }

  @override
  void dispose() {
    TraumaCheckPending.removeListener(_onPendingChange);
    super.dispose();
  }

  void _onPendingChange() {
    if (mounted) setState(() => _hasPending = TraumaCheckPending.hasPending);
  }

  void _launch() {
    final ctx = TraumaCheckPending.consume();
    if (ctx == null || !mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => TraumaCheckSheet(mission: ctx),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPending) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _launch,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF7B8FFF).withOpacity(0.4),
          ),
        ),
        child: Row(
          children: [
            const _PulsingDot(),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wellbeing check-in waiting',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Tap to complete your 3-question check-in',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF7B8FFF),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF7B8FFF),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SMALL REUSABLE WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final bool large;
  const _PulsingIcon({
    required this.icon,
    required this.color,
    this.large = false,
  });

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.large ? 80.0 : 60.0;
    final iconSize = widget.large ? 36.0 : 26.0;
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(widget.icon, color: widget.color, size: iconSize),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF7B8FFF),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
