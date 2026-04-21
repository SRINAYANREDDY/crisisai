// dispatch_notification_banner.dart
// ---------------------------------------------------------------------------
// Full-screen dispatch alert shown when an FCM SOS notification arrives
// while the app is in the FOREGROUND.
//
// Usage — wrap your top-level widget (e.g. in main.dart) or call from any
// screen that imports FCMDispatchService:
//
//   FCMDispatchService.instance.dispatchStream.listen((payload) {
//     if (mounted) {
//       showDispatchAlert(context, payload);
//     }
//   });
//
// Or drop <DispatchNotificationOverlay> into your widget tree once and it
// self-manages via the FCMDispatchService stream.
// ---------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/material.dart';

import 'fcm_dispatch_service.dart';

// ---------------------------------------------------------------------------
// Helper function — show modal dispatch alert
// ---------------------------------------------------------------------------

void showDispatchAlert(BuildContext context, DispatchPayload payload) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => DispatchAlertDialog(payload: payload),
  );
}

// ---------------------------------------------------------------------------
// DispatchAlertDialog
// ---------------------------------------------------------------------------

class DispatchAlertDialog extends StatefulWidget {
  final DispatchPayload payload;
  const DispatchAlertDialog({super.key, required this.payload});

  @override
  State<DispatchAlertDialog> createState() => _DispatchAlertDialogState();
}

class _DispatchAlertDialogState extends State<DispatchAlertDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scaleAnim;
  int _countdown = 30; // auto-dismiss if no response
  Timer? _timer;
  bool _responded = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );

    // Countdown timer
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        if (mounted && !_responded) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _accept() async {
    _responded = true;
    _timer?.cancel();
    await FCMDispatchService.instance.acceptDispatch(widget.payload.sosId);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _decline() async {
    _responded = true;
    _timer?.cancel();
    await FCMDispatchService.instance.declineDispatch(widget.payload.sosId);
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    final color = p.severityColor;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.campaign_rounded,
                        color: color,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'DISPATCH ALERT',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(
                            p.incidentType,
                            style: TextStyle(
                              color: color,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Countdown ring
                    _CountdownRing(countdown: _countdown, color: color),
                  ],
                ),
              ),

              // ── Body ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Severity + distance row
                    Row(
                      children: [
                        _Chip(
                          label: '${p.severityLabel} Severity',
                          color: color,
                          icon: Icons.warning_amber_rounded,
                        ),
                        const SizedBox(width: 8),
                        _Chip(
                          label: '${p.distanceKm.toStringAsFixed(1)} km away',
                          color: const Color(0xFF4285F4),
                          icon: Icons.location_on_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Location
                    if (p.location.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.place_rounded,
                            size: 14,
                            color: Colors.white54,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              p.location,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Required skills
                    if (p.requiredSkills.isNotEmpty) ...[
                      const Text(
                        'REQUIRED SKILLS',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: p.requiredSkills
                            .map(
                              (s) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.white24,
                                  ),
                                ),
                                child: Text(
                                  _prettify(s),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Top immediate action
                    if (p.immediateActions.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: color.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: 16,
                              color: color,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                p.immediateActions.first,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
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

              // ── Action buttons ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _decline,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'DECLINE',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _accept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'RESPOND',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
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
        ),
      ),
    );
  }

  String _prettify(String key) => key
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}',
      )
      .join(' ');
}

// ---------------------------------------------------------------------------
// Countdown ring widget
// ---------------------------------------------------------------------------

class _CountdownRing extends StatelessWidget {
  final int countdown;
  final Color color;
  const _CountdownRing({required this.countdown, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: countdown / 30.0,
            strokeWidth: 3,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Text(
            '$countdown',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chip widget
// ---------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _Chip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay widget — drop once into your widget tree
// ---------------------------------------------------------------------------

/// Drop this into your top-level widget tree once (e.g. inside your
/// MaterialApp builder or Scaffold) to automatically handle dispatch alerts
/// across all screens.
///
/// Example:
///   Stack(children: [
///     child,
///     const DispatchNotificationOverlay(),
///   ])
class DispatchNotificationOverlay extends StatefulWidget {
  final Widget? child;
  const DispatchNotificationOverlay({super.key, this.child});

  @override
  State<DispatchNotificationOverlay> createState() =>
      _DispatchNotificationOverlayState();
}

class _DispatchNotificationOverlayState
    extends State<DispatchNotificationOverlay> {
  StreamSubscription<DispatchPayload>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FCMDispatchService.instance.dispatchStream.listen((payload) {
      if (mounted) showDispatchAlert(context, payload);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.child ?? const SizedBox.shrink();
}
