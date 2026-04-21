// gemini_live_screen.dart
// ---------------------------------------------------------------------------
// Feature 2 UI — Gemini Live API real-time voice co-responder screen
//
// Visual highlights for judges:
//  • Animated waveform that pulses with mic input level
//  • Live AI guidance text streams in as Gemini responds
//  • "ARIA" AI avatar with pulsing ring when speaking
//  • Session transcript log visible in real time
//  • Seamlessly transitions to SOSTriageResult on session end
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'gemini_live_service.dart';
import 'voice_sos_service.dart';
import 'volunteer_repository.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

class GeminiLiveScreen extends StatefulWidget {
  const GeminiLiveScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const GeminiLiveScreen());

  @override
  State<GeminiLiveScreen> createState() => _GeminiLiveScreenState();
}

class _GeminiLiveScreenState extends State<GeminiLiveScreen>
    with TickerProviderStateMixin {
  final _service = GeminiLiveService.instance;

  late AnimationController _waveController;
  late AnimationController _ariaController;

  bool _sessionStarted = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _ariaController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _waveController.dispose();
    _ariaController.dispose();
    super.dispose();
  }

  // ── Session control ───────────────────────────────────────────────────────

  Future<void> _startSession() async {
    setState(() {
      _errorMessage = null;
    });

    final ok = await _service.initialize();
    if (!ok) {
      setState(() {
        _errorMessage = 'Microphone permission required.';
      });
      return;
    }

    setState(() => _sessionStarted = true);

    final volunteers = VolunteerRepository.instance.sosVolunteersNotifier.value;

    try {
      final result = await _service.startSession(
        nearbyVolunteers: volunteers,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => _LiveResultScreen(result: result),
          ),
        );
      }
    } on CancelledException {
      // user cancelled — go back
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _sessionStarted = false;
          _errorMessage = 'Connection failed. Check internet and try again.';
        });
      }
    }
  }

  Future<void> _stopSession() async {
    await _service.stopSession();
    if (mounted) setState(() => _sessionStarted = false);
  }

  Future<void> _cancelSession() async {
    await _service.cancelSession();
    if (mounted) {
      setState(() => _sessionStarted = false);
      Navigator.of(context).pop();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 20),
            onPressed:
                _sessionStarted ? _cancelSession : () => Navigator.pop(context),
          ),
          const Spacer(),
          ValueListenableBuilder<LiveSessionState>(
            valueListenable: _service.stateNotifier,
            builder: (_, state, __) {
              final label = _stateLabel(state);
              final color = _stateColor(state);
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildAriaAvatar(),
          const SizedBox(height: 24),
          _buildGuidanceCard(),
          const SizedBox(height: 16),
          _buildTranscriptCard(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            _buildErrorCard(),
          ],
        ],
      ),
    );
  }

  // ── ARIA avatar with pulsing ring ─────────────────────────────────────────

  Widget _buildAriaAvatar() {
    return ValueListenableBuilder<bool>(
      valueListenable: _service.isSpeaking,
      builder: (_, speaking, __) {
        return AnimatedBuilder(
          animation: _ariaController,
          builder: (_, __) {
            final pulse = speaking ? 1.0 + 0.12 * _ariaController.value : 1.0;
            final ringColor =
                speaking ? const Color(0xFF4285F4) : const Color(0xFF1D9E75);

            return Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow ring
                Transform.scale(
                  scale: pulse * 1.25,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: ringColor.withOpacity(0.2), width: 8),
                    ),
                  ),
                ),
                // Mid ring
                Transform.scale(
                  scale: pulse * 1.12,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: ringColor.withOpacity(0.4), width: 4),
                    ),
                  ),
                ),
                // Avatar circle
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        ringColor.withOpacity(0.3),
                        const Color(0xFF1A1A2E),
                      ],
                    ),
                    border: Border.all(color: ringColor, width: 2),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        speaking
                            ? Icons.record_voice_over_rounded
                            : Icons.support_agent_rounded,
                        color: ringColor,
                        size: 36,
                      ),
                      const SizedBox(height: 2),
                      Text('ARIA',
                          style: TextStyle(
                              color: ringColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Waveform + guidance card ──────────────────────────────────────────────

  Widget _buildGuidanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4285F4).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_rounded,
                  color: Color(0xFF4285F4), size: 16),
              const SizedBox(width: 6),
              const Text('AI GUIDANCE',
                  style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5)),
              const Spacer(),
              // Waveform
              ValueListenableBuilder<double>(
                valueListenable: _service.inputLevel,
                builder: (_, level, __) =>
                    _MiniWaveform(level: level, controller: _waveController),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<String>(
            valueListenable: _service.aiGuidance,
            builder: (_, guidance, __) {
              if (guidance.isEmpty) {
                return Text(
                  _sessionStarted
                      ? 'Listening… describe what you see.'
                      : 'Tap START to connect to ARIA, your AI co-responder.',
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 14,
                      fontStyle: FontStyle.italic),
                );
              }
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  guidance,
                  key: ValueKey(guidance.hashCode),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.5),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Transcript card ───────────────────────────────────────────────────────

  Widget _buildTranscriptCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 160),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mic_rounded, color: Colors.white38, size: 13),
              SizedBox(width: 5),
              Text('YOUR VOICE',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: _service.liveTranscript,
              builder: (_, transcript, __) {
                if (transcript.isEmpty) {
                  return const Text('Your words will appear here in real time…',
                      style: TextStyle(color: Colors.white24, fontSize: 12));
                }
                return SingleChildScrollView(
                  child: Text(transcript,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13, height: 1.5)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE24B4A).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE24B4A).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFE24B4A), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_errorMessage!,
                style: const TextStyle(color: Color(0xFFE24B4A), fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: ValueListenableBuilder<LiveSessionState>(
        valueListenable: _service.stateNotifier,
        builder: (_, state, __) {
          if (!_sessionStarted || state == LiveSessionState.idle) {
            return _BigButton(
              label: 'START SESSION',
              icon: Icons.sensors_rounded,
              color: const Color(0xFF4285F4),
              onTap: _startSession,
            );
          }
          if (state == LiveSessionState.connecting) {
            return const Center(
              child: Column(children: [
                CircularProgressIndicator(color: Color(0xFF4285F4)),
                SizedBox(height: 10),
                Text('Connecting to ARIA…',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
            );
          }
          if (state == LiveSessionState.processing) {
            return const Center(
              child: Column(children: [
                CircularProgressIndicator(color: Color(0xFF1D9E75)),
                SizedBox(height: 10),
                Text('Analysing incident…',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
            );
          }
          return Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _cancelSession,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('CANCEL'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _BigButton(
                  label: 'END & TRIAGE',
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF1D9E75),
                  onTap: _stopSession,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _stateLabel(LiveSessionState s) {
    switch (s) {
      case LiveSessionState.idle:
        return 'READY';
      case LiveSessionState.connecting:
        return 'CONNECTING';
      case LiveSessionState.active:
        return 'LIVE';
      case LiveSessionState.processing:
        return 'ANALYSING';
      case LiveSessionState.error:
        return 'ERROR';
      case LiveSessionState.ended:
        return 'ENDED';
    }
  }

  Color _stateColor(LiveSessionState s) {
    switch (s) {
      case LiveSessionState.active:
        return const Color(0xFF1D9E75);
      case LiveSessionState.connecting:
        return const Color(0xFF4285F4);
      case LiveSessionState.error:
        return const Color(0xFFE24B4A);
      case LiveSessionState.idle:
      case LiveSessionState.processing:
      case LiveSessionState.ended:
        return Colors.white38;
    }
  }
}

// ---------------------------------------------------------------------------
// Mini animated waveform
// ---------------------------------------------------------------------------

class _MiniWaveform extends StatelessWidget {
  final double level;
  final AnimationController controller;
  const _MiniWaveform({required this.level, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return CustomPaint(
          size: const Size(40, 20),
          painter: _WavePainter(level: level, t: controller.value),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double level;
  final double t;
  _WavePainter({required this.level, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4285F4).withOpacity(0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const bars = 7;
    final w = size.width / bars;
    for (int i = 0; i < bars; i++) {
      final phase = (i / bars + t) * math.pi * 2;
      final h = (0.3 + 0.7 * level) * (0.4 + 0.6 * math.sin(phase).abs());
      final barH = h * size.height;
      final x = i * w + w / 2;
      canvas.drawLine(
        Offset(x, (size.height - barH) / 2),
        Offset(x, (size.height + barH) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.level != level || old.t != t;
}

// ---------------------------------------------------------------------------
// Big button widget
// ---------------------------------------------------------------------------

class _BigButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _BigButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 14)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result screen after session ends
// ---------------------------------------------------------------------------

class _LiveResultScreen extends StatelessWidget {
  final SOSTriageResult result;
  const _LiveResultScreen({required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Triage Result',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: BackButton(
            color: Colors.white70,
            onPressed: () => Navigator.of(context).pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Incident card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: result.severityColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: result.severityColor.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('INCIDENT',
                      style: TextStyle(
                          color: result.severityColor.withOpacity(0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text(result.incidentType,
                      style: TextStyle(
                          color: result.severityColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                      '${result.severityLabel} Severity (${result.severity}/5)',
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // What was said
            if (result.rawTranscription.isNotEmpty) ...[
              _sectionHeader('WHAT YOU SAID'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(result.rawTranscription,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.5,
                        fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: 16),
            ],

            // Immediate actions
            _sectionHeader('IMMEDIATE ACTIONS'),
            const SizedBox(height: 8),
            ...result.immediateActions.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: result.severityColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text('${e.key + 1}',
                              style: TextStyle(
                                  color: result.severityColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(e.value,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  height: 1.4)),
                        ),
                      ],
                    ),
                  ),
                ),

            // Matched volunteers
            if (result.matchedVolunteers.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionHeader(
                  'MATCHED VOLUNTEERS (${result.matchedVolunteers.length})'),
              const SizedBox(height: 8),
              ...result.matchedVolunteers.map(
                (v) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.person_rounded,
                          color: Color(0xFF4285F4), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            Text(v.matchedSkills.join(', '),
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                      ),
                      Text('${v.distanceKm.toStringAsFixed(1)} km',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ]),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) => Text(
        text,
        style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5),
      );
}
