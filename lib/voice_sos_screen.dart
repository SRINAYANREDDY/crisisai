// lib/voice_sos_screen.dart
// Feature 3 — Voice SOS Screen
// Hooks into home_screen.dart via _AISOSTriageSheet replacement

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'voice_sos_service.dart';
import 'home_screen.dart'; // AppColors, AppData
import 'gemini_live_screen.dart';

// ---------------------------------------------------------------------------
// Entry-point widget — drop this where _AISOSTriageSheet was shown
// Usage:  showModalBottomSheet(... builder: (_) => const VoiceSOSSheet())
// ---------------------------------------------------------------------------

class VoiceSOSSheet extends StatefulWidget {
  /// Optional: pass your nearby-volunteer list in directly.
  /// Falls back to [AppData.sosVolunteers] when null.
  final List<Map<String, dynamic>>? nearbyVolunteers;

  const VoiceSOSSheet({super.key, this.nearbyVolunteers});

  @override
  State<VoiceSOSSheet> createState() => _VoiceSOSSheetState();
}

class _VoiceSOSSheetState extends State<VoiceSOSSheet>
    with TickerProviderStateMixin {
  final _service = VoiceSOSService.instance;

  // UI state machine
  _SOSPhase _phase = _SOSPhase.idle;
  String _transcript = '';
  SOSTriageResult? _result;
  String? _error;

  // Dispatch countdown
  int _countdown = 5;
  Timer? _countdownTimer;
  bool _dispatched = false;

  // Animations
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _service.initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _countdownTimer?.cancel();
    _service.cancelRecording();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // State transitions
  // -------------------------------------------------------------------------

  Future<void> _startRecording() async {
    HapticFeedback.heavyImpact();
    setState(() {
      _phase = _SOSPhase.recording;
      _transcript = '';
      _error = null;
    });
    await _service.startRecording();
  }

  Future<void> _stopAndAnalyse() async {
    if (_phase != _SOSPhase.recording) return;
    HapticFeedback.mediumImpact();

    final text = await _service.stopRecording();

    if (text.trim().isEmpty) {
      setState(() {
        _phase = _SOSPhase.idle;
        _error = 'No speech detected. Hold the button and speak clearly.';
      });
      return;
    }

    setState(() {
      _transcript = text;
      _phase = _SOSPhase.analysing;
    });

    try {
      // Build volunteer list from AppData
      final volunteers = _buildVolunteerList();
      final result = await _service.triage(text, volunteers);
      setState(() {
        _result = result;
        _phase = _SOSPhase.result;
      });
      _startCountdown();
    } catch (e) {
      setState(() {
        _phase = _SOSPhase.idle;
        _error = 'Analysis failed. Please try again.';
      });
    }
  }

  void _startCountdown() {
    _countdown = 5;
    _dispatched = false;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        _dispatch();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _cancelDispatch() {
    _countdownTimer?.cancel();
    HapticFeedback.lightImpact();
    setState(() => _phase = _SOSPhase.idle);
  }

  String? _sosId;

  Future<void> _dispatch() async {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() => _dispatched = true);

    final uids = _result!.matchedVolunteers.map((v) => v.id).toList();
    _sosId = await VoiceSOSService.instance.publishSOSEvent(_result!, uids);
  }

  void _reset() {
    _countdownTimer?.cancel();
    setState(() {
      _phase = _SOSPhase.idle;
      _result = null;
      _transcript = '';
      _error = null;
      _dispatched = false;
      _sosId = null;
    });
  }

  List<Map<String, dynamic>> _buildVolunteerList() {
    // Use the list passed in from the caller, or fall back to AppData.sosVolunteers.
    // AppData.sosVolunteers uses the skill-keyed format (first_aid, cpr, …)
    // that VoiceSOSService.matchVolunteers expects.
    return widget.nearbyVolunteers ?? AppData.sosVolunteers;
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(),
          const Divider(height: 1, color: AppColors.border),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() => Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.campaign_rounded,
                color: AppColors.red,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice SOS',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'AI-powered emergency dispatch',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              color: AppColors.textSecondary,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );

  Widget _buildBody() {
    switch (_phase) {
      case _SOSPhase.idle:
        return _buildIdlePhase();
      case _SOSPhase.recording:
        return _buildRecordingPhase();
      case _SOSPhase.analysing:
        return _buildAnalysingPhase();
      case _SOSPhase.result:
        return _dispatched ? _buildDispatchedPhase() : _buildResultPhase();
    }
  }

  // ---- IDLE ----------------------------------------------------------------

  Widget _buildIdlePhase() => Column(
        children: [
          const SizedBox(height: 8),
          if (_error != null) _buildErrorBanner(_error!),
          const SizedBox(height: 20),
          Text(
            'Hold the button below and describe\nthe emergency in your own words.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 36),
          _buildHoldButton(),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              GeminiLiveScreen.route(),
            ),
            icon: const Icon(Icons.sensors_rounded, size: 18),
            label: const Text('AI CO-RESPONDER'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 28),
          _buildTipRow(
            Icons.wifi_off_rounded,
            'Works offline too — AI triage without network',
          ),
        ],
      );

  Widget _buildHoldButton() => GestureDetector(
        onLongPressStart: (_) => _startRecording(),
        onLongPressEnd: (_) => _stopAndAnalyse(),
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Transform.scale(
            scale: 1.0, // only pulse when recording
            child: child,
          ),
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.red,
              boxShadow: [
                BoxShadow(
                  color: AppColors.red.withOpacity(0.35),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic_rounded, color: Colors.white, size: 38),
                SizedBox(height: 4),
                Text(
                  'HOLD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  // ---- RECORDING -----------------------------------------------------------

  Widget _buildRecordingPhase() => Column(
        children: [
          const SizedBox(height: 12),
          // Live waveform visualiser
          ValueListenableBuilder<double>(
            valueListenable: _service.soundLevel,
            builder: (_, level, __) => _WaveVisualiser(level: level),
          ),
          const SizedBox(height: 20),
          // Live transcript
          ValueListenableBuilder<String>(
            valueListenable: _service.liveTranscript,
            builder: (_, text, __) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                text.isEmpty ? 'Listening…' : text,
                style: TextStyle(
                  fontSize: 15,
                  color: text.isEmpty
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Animated record button (pulsing)
          GestureDetector(
            onTap: _stopAndAnalyse,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) =>
                  Transform.scale(scale: _pulseAnim.value, child: child),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.red.withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.stop_rounded, color: Colors.white, size: 34),
                    SizedBox(height: 2),
                    Text(
                      'RELEASE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              await _service.cancelRecording();
              setState(() => _phase = _SOSPhase.idle);
            },
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      );

  // ---- ANALYSING -----------------------------------------------------------

  Widget _buildAnalysingPhase() => Column(
        children: [
          const SizedBox(height: 32),
          _AnalysingSpinner(),
          const SizedBox(height: 20),
          Text(
            'AI is classifying your emergency…',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '"$_transcript"',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 32),
        ],
      );

  // ---- RESULT + COUNTDOWN --------------------------------------------------

  Widget _buildResultPhase() {
    final r = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Offline badge
        if (r.wasOffline) _buildOfflineBadge(),
        const SizedBox(height: 4),

        // Incident card
        _buildIncidentCard(r),
        const SizedBox(height: 16),

        // Immediate actions
        _buildActionsCard(r),
        const SizedBox(height: 16),

        // Matched volunteers
        _buildVolunteersCard(r),
        const SizedBox(height: 20),

        // Countdown banner
        _buildCountdownBanner(),
        const SizedBox(height: 8),

        // Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _cancelDispatch,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _dispatch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Dispatch Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIncidentCard(SOSTriageResult r) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.incidentType,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                // Severity badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: r.severityColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: r.severityColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: r.severityColor,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'SEV ${r.severity} · ${r.severityLabel.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: r.severityColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Severity bar
            _SeverityBar(severity: r.severity),
            const SizedBox(height: 12),
            // Required skills chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: r.requiredSkills
                  .map((s) => _SkillChip(label: s, isRequired: true))
                  .toList(),
            ),
          ],
        ),
      );

  Widget _buildActionsCard(SOSTriageResult r) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.amber.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.amber.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on_rounded, color: AppColors.amber, size: 16),
                const SizedBox(width: 6),
                Text(
                  'IMMEDIATE ACTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.amber,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...r.immediateActions.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.only(top: 1, right: 10),
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Center(
                            child: Text(
                              '${e.key + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.value,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      );

  Widget _buildVolunteersCard(SOSTriageResult r) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.group_rounded, color: AppColors.teal, size: 16),
                const SizedBox(width: 6),
                Text(
                  'MATCHED VOLUNTEERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.teal,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${r.matchedVolunteers.length} found',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.teal,
                    ),
                  ),
                ),
              ],
            ),
            if (r.matchedVolunteers.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'No nearby volunteers match the required skills.\nAll available units will be notified.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              ...r.matchedVolunteers.map(
                (v) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _VolunteerDispatchRow(volunteer: v),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _buildCountdownBanner() => TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 0.0),
        duration: Duration(seconds: _countdown),
        builder: (_, progress, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.red.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.timer_rounded, color: AppColors.red, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Dispatching in $_countdown second${_countdown == 1 ? '' : 's'}…',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.red,
                  ),
                ),
              ),
              // Progress indicator
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  value: _countdown / 5,
                  strokeWidth: 3,
                  backgroundColor: AppColors.red.withOpacity(0.15),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.red),
                ),
              ),
            ],
          ),
        ),
      );

  // ---- DISPATCHED ----------------------------------------------------------

  Widget _buildDispatchedPhase() => Column(
        children: [
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.teal.withOpacity(0.1),
            ),
            child: Icon(
              Icons.check_circle_rounded,
              color: AppColors.teal,
              size: 56,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Dispatched!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_result!.matchedVolunteers.length} volunteer${_result!.matchedVolunteers.length == 1 ? '' : 's'} notified.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            _result!.incidentType,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _reset,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'New SOS',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text('Close', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      );

  // ---- Shared helpers ------------------------------------------------------

  Widget _buildOfflineBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.amber.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.amber.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 13, color: AppColors.amber),
            const SizedBox(width: 5),
            Text(
              'OFFLINE — Local AI triage used',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.amber,
              ),
            ),
          ],
        ),
      );

  Widget _buildErrorBanner(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.red.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.red.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.red, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: TextStyle(fontSize: 13, color: AppColors.red),
              ),
            ),
          ],
        ),
      );

  Widget _buildTipRow(IconData icon, String text) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SeverityBar extends StatelessWidget {
  final int severity;
  const _SeverityBar({required this.severity});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final filled = i < severity;
        final color = _color(severity);
        return Expanded(
          child: Container(
            height: 5,
            margin: EdgeInsets.only(right: i < 4 ? 3 : 0),
            decoration: BoxDecoration(
              color: filled ? color : color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  Color _color(int s) {
    if (s <= 2) return const Color(0xFF1D9E75);
    if (s == 3) return const Color(0xFFBA7517);
    return const Color(0xFFE24B4A);
  }
}

class _SkillChip extends StatelessWidget {
  final String label;
  final bool isRequired;
  const _SkillChip({required this.label, this.isRequired = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isRequired
            ? AppColors.red.withOpacity(0.08)
            : AppColors.teal.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRequired
              ? AppColors.red.withOpacity(0.2)
              : AppColors.teal.withOpacity(0.2),
        ),
      ),
      child: Text(
        label.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isRequired ? AppColors.red : AppColors.teal,
        ),
      ),
    );
  }
}

class _VolunteerDispatchRow extends StatelessWidget {
  final MatchedVolunteer volunteer;
  const _VolunteerDispatchRow({required this.volunteer});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.teal.withOpacity(0.12),
          child: Text(
            volunteer.name.isNotEmpty ? volunteer.name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: AppColors.teal,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                volunteer.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 4,
                children: volunteer.matchedSkills
                    .map((s) => _SkillChip(label: s, isRequired: false))
                    .toList(),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${volunteer.distanceKm.toStringAsFixed(1)} km',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_active_rounded,
                    size: 10,
                    color: AppColors.teal,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Notifying',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.teal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AnalysingSpinner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.gemini),
          ),
        ),
        const Icon(Icons.psychology_rounded, color: AppColors.gemini, size: 30),
      ],
    );
  }
}

class _WaveVisualiser extends StatefulWidget {
  final double level;
  const _WaveVisualiser({required this.level});

  @override
  State<_WaveVisualiser> createState() => _WaveVisualiserState();
}

class _WaveVisualiserState extends State<_WaveVisualiser>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        size: const Size(double.infinity, 60),
        painter: _WavePainter(progress: _ctrl.value, level: widget.level),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final double level;
  _WavePainter({required this.progress, required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.red.withOpacity(0.7)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const barCount = 24;
    final barWidth = size.width / (barCount * 2);

    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth * 2 + barWidth;
      final phase = (i / barCount + progress) * math.pi * 2;
      final amplitude = (math.sin(phase) * 0.5 + 0.5) * level;
      final barH = math.max(4.0, amplitude * size.height * 0.9);
      final top = (size.height - barH) / 2;

      canvas.drawLine(Offset(x, top), Offset(x, top + barH), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.level != level;
}

// ---------------------------------------------------------------------------
// Phase enum
// ---------------------------------------------------------------------------

enum _SOSPhase { idle, recording, analysing, result }
