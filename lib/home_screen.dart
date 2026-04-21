// home_screen.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'profile.dart';
import 'detector.dart';
import 'map.dart'; // MapScreen
import 'train.dart'; // for trainingBlocks + detail screens, GeminiService
import 'offline_ai_screen.dart'; // Feature 1 — Offline AI Guide
import 'offline_ai_service.dart'; // Feature 1 — NetworkChecker
import 'trauma_check_service.dart'; // Feature 2 — TraumaCheckPending, CompletedMissionContext
import 'trauma_check_screen.dart'; // Feature 2 — TraumaCheckSheet, TraumaPendingBanner
import 'voice_sos_screen.dart'; // Feature 3 — VoiceSOSSheet
import 'disaster_forecast_screen.dart'; // Feature 4 — 48-Hour Disaster Forecast
import 'volunteer_repository.dart'; // Live Firestore volunteer feed
import 'location_presence.dart'; // Online/offline presence writer
import 'notifications_screen.dart'; // Notification store + sheet

// ─── App-wide shared data store ───────────────────────────────────────────────
class AppData {
  static Map<String, dynamic> volunteerProfile = {
    'name': '',
    'email': '',
    'username': '',
    'contactNumber': '',
    'age': '',
    'address': '',
    'gender': '',
    'skills': <String>[],
    'initials': '',
    'level': 3,
    'xp': 680,
    'xpMax': 1000,
    'missionsCompleted': 14,
    'nearbyHeroes': 7,
    'rank': 42,
    'isActive': true,
    'streak': 5,
    'totalXp': 2340,
  };

  static Map<String, dynamic> authorisedProfile = {
    'name': '',
    'email': '',
    'username': '',
    'id': '',
    'password': '',
    'department': '',
    'badgeId': 'AUTH-001',
    'jurisdiction': 'Chennai District',
    'initials': '',
  };

  static String loginType = 'volunteer'; // 'volunteer' or 'authorised'

  // SOS dispatch volunteers — live feed from VolunteerRepository (Firestore).
  // Populated within seconds of app start; empty list is safe until then.
  static List<Map<String, dynamic>> sosVolunteers = [];

  // Completed missions data (linked to train.dart completions)
  static List<Map<String, dynamic>> completedMissions = [
    {
      'title': 'Cardiac Arrest Response',
      'category': 'Medical',
      'location': 'Anna Nagar',
      'date': 'Apr 8, 2026',
      'xp': 120,
      'score': 95,
      'duration': '22 min',
      'icon': Icons.favorite_outline,
      'color': 0xFFE24B4A,
    },
    {
      'title': 'Fire Safety Drill',
      'category': 'Fire',
      'location': 'T. Nagar',
      'date': 'Apr 5, 2026',
      'xp': 80,
      'score': 88,
      'duration': '15 min',
      'icon': Icons.local_fire_department_outlined,
      'color': 0xFFBA7517,
    },
    {
      'title': 'First Aid Support',
      'category': 'Medical',
      'location': 'Adyar',
      'date': 'Apr 2, 2026',
      'xp': 100,
      'score': 92,
      'duration': '18 min',
      'icon': Icons.medical_services_outlined,
      'color': 0xFF1D9E75,
    },
    {
      'title': 'CPR Refresher',
      'category': 'Training',
      'location': 'Online',
      'date': 'Mar 29, 2026',
      'xp': 60,
      'score': 78,
      'duration': '10 min',
      'icon': Icons.favorite,
      'color': 0xFF4285F4,
    },
    {
      'title': 'Flood Response Basics',
      'category': 'Disaster',
      'location': 'Velachery',
      'date': 'Mar 25, 2026',
      'xp': 90,
      'score': 85,
      'duration': '20 min',
      'icon': Icons.water_outlined,
      'color': 0xFF1D4ED8,
    },
  ];

  // Daily activity log for calendar/rank screen
  static Map<String, dynamic> dailyActivity = {
    '2026-04-17': {'xp': 30, 'missions': 1, 'done': true},
    '2026-04-16': {'xp': 80, 'missions': 1, 'done': true},
    '2026-04-15': {'xp': 50, 'missions': 1, 'done': true},
    '2026-04-14': {'xp': 120, 'missions': 2, 'done': true},
    '2026-04-13': {'xp': 0, 'missions': 0, 'done': false},
    '2026-04-12': {'xp': 100, 'missions': 1, 'done': true},
    '2026-04-11': {'xp': 90, 'missions': 2, 'done': true},
    '2026-04-10': {'xp': 60, 'missions': 1, 'done': true},
    '2026-04-09': {'xp': 0, 'missions': 0, 'done': false},
    '2026-04-08': {'xp': 120, 'missions': 1, 'done': true},
    '2026-04-07': {'xp': 40, 'missions': 1, 'done': true},
    '2026-04-06': {'xp': 80, 'missions': 1, 'done': true},
  };

  // Leaderboard data
  static final List<Map<String, dynamic>> leaderboard = [
    {
      'rank': 1,
      'name': 'Priya Sharma',
      'xp': 4820,
      'streak': 12,
      'initials': 'PS',
      'color': 0xFFE24B4A,
    },
    {
      'rank': 2,
      'name': 'Arun Kumar',
      'xp': 4650,
      'streak': 9,
      'initials': 'AK',
      'color': 0xFF1D4ED8,
    },
    {
      'rank': 3,
      'name': 'Divya Nair',
      'xp': 4310,
      'streak': 7,
      'initials': 'DN',
      'color': 0xFF1D9E75,
    },
    {
      'rank': 4,
      'name': 'Ravi Prakash',
      'xp': 3990,
      'streak': 11,
      'initials': 'RP',
      'color': 0xFFBA7517,
    },
    {
      'rank': 5,
      'name': 'Meena Sundaram',
      'xp': 3750,
      'streak': 6,
      'initials': 'MS',
      'color': 0xFF4285F4,
    },
    {
      'rank': 6,
      'name': 'Karthik Raja',
      'xp': 3540,
      'streak': 8,
      'initials': 'KR',
      'color': 0xFFE24B4A,
    },
    {
      'rank': 7,
      'name': 'Anitha Raj',
      'xp': 3200,
      'streak': 4,
      'initials': 'AR',
      'color': 0xFF1D9E75,
    },
    {
      'rank': 8,
      'name': 'Senthil V',
      'xp': 2980,
      'streak': 3,
      'initials': 'SV',
      'color': 0xFF1D4ED8,
    },
    {
      'rank': 9,
      'name': 'Lakshmi Priya',
      'xp': 2710,
      'streak': 5,
      'initials': 'LP',
      'color': 0xFFBA7517,
    },
    {
      'rank': 10,
      'name': 'Vijay Anand',
      'xp': 2500,
      'streak': 2,
      'initials': 'VA',
      'color': 0xFF4285F4,
    },
  ];

  // Nearby volunteers — live feed from VolunteerRepository (Firestore).
  // UI rebuilds via setState whenever this list updates.
  static List<Map<String, dynamic>> nearbyVolunteers = [];

  // Authorised officers
  static final List<Map<String, dynamic>> authorisedOfficers = [
    {
      'name': 'Inspector Suresh',
      'role': 'Police Officer',
      'department': 'Chennai Police',
      'badgeId': 'CP-2847',
      'jurisdiction': 'Anna Nagar',
      'phone': '+91 44 2345 6789',
      'emergency': '100',
      'initials': 'IS',
      'color': 0xFF1D4ED8,
      'isOnDuty': true,
    },
    {
      'name': 'Dr. Kavitha Rao',
      'role': 'Medical Officer',
      'department': 'GGH Chennai',
      'badgeId': 'MO-1192',
      'jurisdiction': 'T. Nagar',
      'phone': '+91 44 2346 7890',
      'emergency': '108',
      'initials': 'KR',
      'color': 0xFF1D9E75,
      'isOnDuty': true,
    },
    {
      'name': 'Captain Vijay',
      'role': 'Fire Officer',
      'department': 'Chennai Fire',
      'badgeId': 'FD-0387',
      'jurisdiction': 'Adyar',
      'phone': '+91 44 2347 8901',
      'emergency': '101',
      'initials': 'CV',
      'color': 0xFFE24B4A,
      'isOnDuty': false,
    },
  ];
}

// ─── Colors ───────────────────────────────────────────────────────────────────
class AppColors {
  static const Color red = Color(0xFFE24B4A);
  static const Color redDark = Color(0xFFA32D2D);
  static const Color redLight = Color(0xFFFCEBEB);
  static const Color teal = Color(0xFF1D9E75);
  static const Color tealLight = Color(0xFFE1F5EE);
  static const Color amber = Color(0xFFBA7517);
  static const Color amberLight = Color(0xFFFAEEDA);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color border = Color(0xFFE8E8E8);
  static const Color background = Color(0xFFF7F6F3);
  static const Color white = Colors.white;
  static const Color gemini = Color(0xFF4285F4);
  static const Color geminiLight = Color(0xFFE8F0FE);
  static const Color blue = Color(0xFF1D4ED8);
  static const Color blueLight = Color(0xFFEFF6FF);
}

// ── Feature 1 — Mode toggle pill (Online / Offline) ──────────────────────
// Tapping it cycles: Auto → Force Offline → Auto
// Long-pressing shows a bottom sheet with all three options.
class _ConnectivityDot extends StatefulWidget {
  const _ConnectivityDot();
  @override
  State<_ConnectivityDot> createState() => _ConnectivityDotState();
}

class _ConnectivityDotState extends State<_ConnectivityDot> {
  bool _actualNetwork = true;

  @override
  void initState() {
    super.initState();
    _checkNetwork();
    NetworkChecker.connectivityStream.listen((v) {
      if (mounted) setState(() => _actualNetwork = v);
    });
    AppModeController.instance.modeNotifier.addListener(_onModeChange);
  }

  @override
  void dispose() {
    AppModeController.instance.modeNotifier.removeListener(_onModeChange);
    super.dispose();
  }

  void _onModeChange() {
    if (mounted) setState(() {});
  }

  Future<void> _checkNetwork() async {
    final v = await NetworkChecker.check();
    if (mounted) setState(() => _actualNetwork = v);
  }

  void _onTap() {
    AppModeController.instance.toggle();
  }

  void _onLongPress() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ModePickerSheet(actualNetwork: _actualNetwork),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = AppModeController.instance;
    final mode = ctrl.mode;
    final effectivelyOnline = ctrl.isOnline;

    // Colour + label based on current effective state
    final color = effectivelyOnline ? AppColors.teal : AppColors.red;
    final icon = mode == AppModeState.forceOffline
        ? Icons.wifi_off_rounded
        : mode == AppModeState.forceOnline
            ? Icons.wifi_rounded
            : effectivelyOnline
                ? Icons.wifi_rounded
                : Icons.wifi_off_rounded;

    final label = mode == AppModeState.forceOffline
        ? 'OFFLINE'
        : mode == AppModeState.forceOnline
            ? 'ONLINE'
            : effectivelyOnline
                ? 'ONLINE'
                : 'OFFLINE';

    return GestureDetector(
      onTap: _onTap,
      onLongPress: _onLongPress,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            // Small lock icon when mode is forced
            if (mode != AppModeState.auto) ...[
              const SizedBox(width: 3),
              Icon(Icons.lock_rounded, size: 9, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Mode picker bottom sheet ────────────────────────────────────────────────
class _ModePickerSheet extends StatelessWidget {
  final bool actualNetwork;
  const _ModePickerSheet({required this.actualNetwork});

  @override
  Widget build(BuildContext context) {
    final ctrl = AppModeController.instance;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'App Mode',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Real network is currently ${actualNetwork ? "online ✓" : "offline ✗"}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<AppModeState>(
            valueListenable: ctrl.modeNotifier,
            builder: (_, mode, __) => Column(
              children: [
                _ModeOption(
                  icon: Icons.wifi_rounded,
                  iconColor: AppColors.teal,
                  title: 'Auto (follow network)',
                  subtitle: 'Switches automatically based on your connection',
                  selected: mode == AppModeState.auto,
                  onTap: () {
                    ctrl.setAuto();
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 10),
                _ModeOption(
                  icon: Icons.wifi_rounded,
                  iconColor: AppColors.teal,
                  title: 'Force Online',
                  subtitle: 'Always use Gemini AI — needs real internet',
                  selected: mode == AppModeState.forceOnline,
                  onTap: () {
                    ctrl.setForceOnline();
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 10),
                _ModeOption(
                  icon: Icons.wifi_off_rounded,
                  iconColor: AppColors.red,
                  title: 'Force Offline',
                  subtitle: 'Use built-in protocols only — no API calls',
                  selected: mode == AppModeState.forceOffline,
                  onTap: () {
                    ctrl.setForceOffline();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? iconColor.withOpacity(0.08) : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? iconColor.withOpacity(0.4) : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? iconColor : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: iconColor, size: 20),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  HOME SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;

  late AnimationController _fadeController;
  late AnimationController _alertPulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _alertPulse;

  // ── Live location state ─────────────────────────────────────────────────
  double? _userLat;
  double? _userLng;
  String _liveLocality = ''; // e.g. "Ranipet, Tamil Nadu"

  Map<String, dynamic> get _user => AppData.loginType == 'volunteer'
      ? AppData.volunteerProfile
      : AppData.authorisedProfile;

  // ── Nearby alerts — lat/lng offsets added for live directions ─────────────
  // The actual lat/lng is set dynamically from live location in _liveAlerts getter.
  // These are the template definitions; location strings are shown as distances.
  final List<Map<String, dynamic>> _alertTemplates = [
    {
      'type': 'Medical',
      'title': 'Cardiac arrest reported',
      'time': '2 min ago',
      'urgency': 'high',
      'volunteersNeeded': 2,
      'description':
          'A 58-year-old male has collapsed and is unresponsive near the bus stop. Bystanders have called 108. CPR-trained volunteer urgently needed before ambulance arrives.',
      'status': 'Active — Ambulance en route',
      'volunteersResponded': ['Priya Sharma (0.4 km)', 'Ravi Kumar (0.7 km)'],
      'requiredSkills': ['CPR', 'First Aid', 'AED'],
      'reportedBy': 'Citizen App Alert',
      // Offsets from user location (approx 0.8 km NE)
      'latOffset': 0.004,
      'lngOffset': 0.006,
      'distLabel': '0.8 km',
    },
    {
      'type': 'Fire',
      'title': 'Small fire at apartment',
      'time': '8 min ago',
      'urgency': 'medium',
      'volunteersNeeded': 3,
      'description':
          'A small kitchen fire has broken out in a 3rd floor apartment. Fire dept notified. Volunteers needed to assist with floor evacuation and crowd control.',
      'status': 'Pending volunteers',
      'volunteersResponded': ['Karthik M (1.4 km)'],
      'requiredSkills': ['Fire Safety', 'Evacuation'],
      'reportedBy': 'Building Resident',
      // Approx 2.1 km SW
      'latOffset': -0.010,
      'lngOffset': -0.015,
      'distLabel': '2.1 km',
    },
  ];

  /// Returns alerts with live location injected (lat, lng, location, addressText).
  List<Map<String, dynamic>> get _nearbyAlerts {
    return _alertTemplates.map((template) {
      final latOff = template['latOffset'] as double;
      final lngOff = template['lngOffset'] as double;
      final distLabel = template['distLabel'] as String;

      // Use live location if available, otherwise omit coordinates
      final lat = _userLat != null ? _userLat! + latOff : null;
      final lng = _userLng != null ? _userLng! + lngOff : null;

      final locationStr =
          _liveLocality.isNotEmpty ? '$_liveLocality, $distLabel' : distLabel;

      final addressText = _liveLocality.isNotEmpty
          ? 'Near $_liveLocality ($distLabel away)'
          : '$distLabel from your location';

      return {
        ...template,
        'lat': lat,
        'lng': lng,
        'location': locationStr,
        'addressText': addressText,
      };
    }).toList();
  }

  final List<Map<String, dynamic>> _dailyTasks = [
    {
      'title': 'CPR refresher quiz',
      'xp': 30,
      'duration': '5 min',
      'done': true,
      'color': AppColors.teal,
      'icon': Icons.favorite_outline,
    },
    {
      'title': 'Fire extinguisher drill',
      'xp': 40,
      'duration': '8 min',
      'done': false,
      'progress': 0.35,
      'color': AppColors.amber,
      'icon': Icons.local_fire_department_outlined,
    },
    {
      'title': 'Flood response basics',
      'xp': 50,
      'duration': '12 min',
      'done': false,
      'locked': true,
      'color': AppColors.textSecondary,
      'icon': Icons.water_outlined,
    },
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..forward();
    _alertPulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _alertPulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _alertPulseController, curve: Curves.easeInOut),
    );
    // Feature 2 — listen for pending trauma check-in after mission completion
    TraumaCheckPending.addListener(_onPendingTraumaCheck);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _onPendingTraumaCheck(),
    );
    // Live location — fetch on first load
    _fetchLiveLocation();

    // ── Live volunteer feed from Firestore ──────────────────────────────────
    VolunteerRepository.instance.startListening();

    // SOS list: no rebuild needed — read at call-time when SOS sheet opens
    VolunteerRepository.instance.sosVolunteersNotifier.addListener(() {
      AppData.sosVolunteers =
          VolunteerRepository.instance.sosVolunteersNotifier.value;
    });

    // Nearby panel: drives UI — setState to trigger rebuild
    VolunteerRepository.instance.nearbyVolunteersNotifier.addListener(
      _onNearbyVolunteersUpdated,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _alertPulseController.dispose();
    TraumaCheckPending.removeListener(_onPendingTraumaCheck); // Feature 2
    VolunteerRepository.instance.nearbyVolunteersNotifier.removeListener(
      _onNearbyVolunteersUpdated,
    );
    super.dispose();
  }

  void _onNearbyVolunteersUpdated() {
    if (!mounted) return;
    setState(() {
      AppData.nearbyVolunteers =
          VolunteerRepository.instance.nearbyVolunteersNotifier.value;
    });
  }

  // Feature 2 — trauma check trigger handler
  void _onPendingTraumaCheck() {
    if (!mounted || !TraumaCheckPending.hasPending) return;
    final ctx = TraumaCheckPending.consume();
    if (ctx == null) return;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _launchTraumaCheckSheet(ctx);
    });
  }

  // ── Live location ─────────────────────────────────────────────────────────
  Future<void> _fetchLiveLocation() async {
    try {
      bool svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) return;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
      });

      // Reverse geocode to locality
      try {
        final marks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (marks.isNotEmpty && mounted) {
          final p = marks.first;
          final parts = [
            p.subLocality,
            p.locality,
          ].where((s) => s != null && s.isNotEmpty).toList();
          setState(() {
            _liveLocality = parts.isNotEmpty
                ? parts.join(', ')
                : (p.administrativeArea ?? '');
          });
        }
      } catch (_) {
        // Geocoding failed — locality stays empty, location coords still set
      }
    } catch (_) {
      // GPS failed silently — app still works with mock data
    }
  }

  /// Opens Google Maps turn-by-turn directions to given lat/lng.
  Future<void> _openMapsDirections(double destLat, double destLng) async {
    // If we have the user's live location, include origin for better routing
    String url;
    if (_userLat != null && _userLng != null) {
      url = 'https://www.google.com/maps/dir/?api=1'
          '&origin=$_userLat,$_userLng'
          '&destination=$destLat,$destLng'
          '&travelmode=driving';
    } else {
      url = 'https://www.google.com/maps/dir/?api=1'
          '&destination=$destLat,$destLng'
          '&travelmode=driving';
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Maps. Please try again.')),
      );
    }
  }

  /// Called when volunteer taps "I'll Respond".
  void _confirmRespond(Map<String, dynamic> alert) {
    Navigator.pop(context); // close the bottom sheet first
    final title = alert['title'] as String? ?? 'this emergency';
    // Show a confirmation snackbar with action to open directions
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Responding to: $title',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Directions',
          textColor: Colors.white,
          onPressed: () {
            final lat = alert['lat'] as double?;
            final lng = alert['lng'] as double?;
            if (lat != null && lng != null) {
              _openMapsDirections(lat, lng);
            }
          },
        ),
        backgroundColor: AppColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _launchTraumaCheckSheet(CompletedMissionContext ctx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => TraumaCheckSheet(mission: ctx),
    );
  }

  // ── FIX: Complete tab routing for both roles with MapScreen integrated ──
  Widget _buildCurrentTab() {
    if (AppData.loginType == 'authorised') {
      // Authorised nav: 0=Home, 1=Detector, 2=Map, 3=Profile
      switch (_selectedIndex) {
        case 1:
          return const DetectorScreen();
        case 2:
          return const MapScreen(); // ← FIXED: Map now works for authorised
        case 3:
          return AuthorisedPersonProfileTab(officer: AppData.authorisedProfile);
        default:
          return _buildHomeContent();
      }
    }
    // Volunteer nav: 0=Home, 1=Map, 2=Train, 3=Profile
    switch (_selectedIndex) {
      case 1:
        return const MapScreen(); // ← FIXED: Map now works for volunteer
      case 2:
        return const TrainingScreen();
      case 3:
        return VolunteerProfileTab(
          user: AppData.volunteerProfile,
          onProfileUpdated: () => setState(() {}),
        );
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  const TraumaPendingBanner(), // Feature 2 — shows pending check-in pill
                  _buildHeroCard(),
                  const SizedBox(height: 20),
                  _buildGeminiInsightCard(),
                  const SizedBox(height: 20),
                  _buildStatsRow(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Nearby emergencies', showBadge: true),
                  const SizedBox(height: 12),
                  _buildAlertsList(),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Today's training"),
                  const SizedBox(height: 12),
                  _buildTrainingTasks(),
                  const SizedBox(height: 24),
                  if (AppData.loginType == 'authorised')
                    _buildAIDetectorCard()
                  else
                    _buildLiveMapCard(),
                  const SizedBox(height: 16),
                  const ForecastHomeCard(), // Feature 4 — 48-Hour Disaster Forecast
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _buildCurrentTab(),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _selectedIndex == 0 ? _buildSOSButton() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      floating: true,
      pinned: false,
      expandedHeight: 70,
      flexibleSpace: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Text(
                      'Good morning,',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (_liveLocality.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.location_on_rounded,
                        size: 10,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _liveLocality,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                // KEY FIX: reads live from AppData so name always reflects edits
                Text(
                  (_user['name'] as String? ?? '').isEmpty
                      ? 'Hero'
                      : _user['name'],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const _ConnectivityDot(), // Feature 1 — red pill when offline
                _buildIconBtn(Icons.offline_bolt_rounded, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OfflineAIScreen()),
                  );
                }),
                const SizedBox(width: 8),
                ValueListenableBuilder<List<AppNotification>>(
                  valueListenable: NotificationStore.instance.notifier,
                  builder: (_, __, ___) => _buildIconBtn(
                    Icons.notifications_outlined,
                    _openNotifications,
                    badge: NotificationStore.instance.hasUnread,
                    badgeCount: NotificationStore.instance.unreadCount,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _selectedIndex = 3),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.tealLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.teal, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        (_user['initials'] as String? ?? '').isEmpty
                            ? 'U'
                            : _user['initials'],
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.teal,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the notification sheet and marks all as read
  void _openNotifications() {
    showNotificationsSheet(context);
    Future.delayed(const Duration(milliseconds: 300), () {
      NotificationStore.instance.markAllRead();
    });
  }

  Widget _buildIconBtn(
    IconData icon,
    VoidCallback onTap, {
    bool badge = false,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Icon(icon, size: 20, color: AppColors.textPrimary),
          ),
          if (badge)
            Positioned(
              top: badgeCount > 0 ? 2 : 6,
              right: badgeCount > 0 ? 2 : 6,
              child: badgeCount > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    final skills =
        (_user['skills'] as List<dynamic>?)?.cast<String>() ?? ['Volunteer'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    (_user['initials'] as String? ?? '').isEmpty
                        ? 'U'
                        : _user['initials'],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shield, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          AppData.loginType == 'volunteer'
                              ? 'Hero Level ${_user['level']}'
                              : 'Authorised Officer',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (_user['name'] as String? ?? '').isEmpty
                          ? 'Hero'
                          : _user['name'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.4),
                    width: 0.5,
                  ),
                ),
                child: const Row(
                  children: [
                    _DotWidget(color: Color(0xFF4ADE80)),
                    SizedBox(width: 5),
                    Text(
                      'Active',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (AppData.loginType == 'volunteer') ...[
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'XP Progress',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    Text(
                      '${_user['xp']} / ${_user['xpMax']} XP',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_user['xp'] as int) / (_user['xpMax'] as int),
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (skills.isNotEmpty)
              Row(
                children: [
                  Text(
                    'Skills: ',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: skills
                          .map(
                            (s) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                s,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildGeminiInsightCard() {
    return _DynamicGeminiInsightCard(user: _user, nearbyAlerts: _nearbyAlerts);
  }

  // ── Stats row — tappable cards ────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCard(
          'Missions done',
          '${_user['missionsCompleted'] ?? 0}',
          Icons.check_circle_outline,
          AppColors.teal,
          AppColors.tealLight,
          onTap: () =>
              Navigator.push(context, _slideRoute(const MissionsDoneScreen())),
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          'Nearby heroes',
          '${_user['nearbyHeroes'] ?? 0}',
          Icons.people_outline,
          AppColors.red,
          AppColors.redLight,
          onTap: () =>
              Navigator.push(context, _slideRoute(const NearbyHeroesScreen())),
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          'Your rank',
          '#${_user['rank'] ?? 42}',
          Icons.leaderboard_outlined,
          AppColors.amber,
          AppColors.amberLight,
          onTap: () => Navigator.push(
            context,
            _slideRoute(const RankAndLeaderboardScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
    Color bgColor, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 20,
                height: 2,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {bool showBadge = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        Row(
          children: [
            if (showBadge)
              AnimatedBuilder(
                animation: _alertPulse,
                builder: (context, child) => Transform.scale(
                  scale: _alertPulse.value,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            if (showBadge) const SizedBox(width: 6),
            GestureDetector(
              onTap: () {},
              child: const Text(
                'See all',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlertsList() {
    return Column(
      children: _nearbyAlerts.map((a) => _buildAlertCard(a)).toList(),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final bool isHigh = alert['urgency'] == 'high';
    final Color urgencyColor = isHigh ? AppColors.red : AppColors.amber;
    final Color urgencyBg = isHigh ? AppColors.redLight : AppColors.amberLight;
    return _AIAlertCard(
      alert: alert,
      urgencyColor: urgencyColor,
      urgencyBg: urgencyBg,
      isHigh: isHigh,
      userSkills: (_user['skills'] as List<dynamic>?)?.cast<String>() ?? [],
      onRespond: () => _showEmergencyDetails(context, alert),
    );
  }

  Widget _buildTrainingTasks() {
    // Gather up to 3 missions: pick the next uncompleted mission from each
    // in-progress block, starting with the one furthest along.
    final List<Map<String, dynamic>> todayItems = [];

    for (final block in trainingBlocks) {
      if (block.status == BlockStatus.inProgress ||
          block.status == BlockStatus.completed) {
        for (final mission in block.missions) {
          if (todayItems.length >= 3) break;
          // Show the completed ones first, then queue up to 1 uncompleted per block
          if (mission.completed ||
              !todayItems.any((t) => t['block'] == block)) {
            todayItems.add({
              'title': mission.title,
              'xp': mission.xp,
              'duration': '${mission.durationMin} min',
              'done': mission.completed,
              'score': mission.score,
              'color': block.color,
              'icon': block.icon,
              'block': block,
              'type': mission.type,
            });
          }
        }
      }
      if (todayItems.length >= 3) break;
    }

    if (todayItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: const Center(
          child: Text(
            'No training tasks yet. Start a block!',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: todayItems.map((task) {
        final Color color = task['color'] as Color;
        final bool done = task['done'] == true;
        final String? score = task['score'] as String?;
        final TrainingBlock block = task['block'] as TrainingBlock;

        return GestureDetector(
          onTap: done ? null : () => _navigateToTrainingDetail(block),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: done ? color.withOpacity(0.3) : AppColors.border,
                width: done ? 1 : 0.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    task['icon'] as IconData,
                    color: done ? color.withOpacity(0.5) : color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task['title'],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: done
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '+${task['xp']} XP • ${task['duration']}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (done && score != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.tealLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.emoji_events_rounded,
                                    size: 10,
                                    color: AppColors.teal,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    score,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.teal,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (done)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 14,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _navigateToTrainingDetail(block),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Start',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _navigateToTrainingDetail(TrainingBlock block) {
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
    Navigator.push(context, _slideRoute(screen));
  }

  void _showEmergencyDetails(BuildContext context, Map<String, dynamic> alert) {
    final bool isHigh = alert['urgency'] == 'high';
    final Color urgencyColor = isHigh ? AppColors.red : AppColors.amber;
    final List<dynamic> responded = alert['volunteersResponded'] ?? [];
    final List<dynamic> skills = alert['requiredSkills'] ?? [];
    final int needed = (alert['volunteersNeeded'] as int?) ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // Urgency colour bar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: urgencyColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: urgencyColor.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: _alertPulse,
                      builder: (_, __) => Transform.scale(
                        scale: _alertPulse.value,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: urgencyColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isHigh ? '🔴  HIGH URGENCY' : '🟡  MEDIUM URGENCY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: urgencyColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      alert['time'],
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable body
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: [
                    // Title row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: isHigh
                                ? AppColors.redLight
                                : AppColors.amberLight,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            alert['type'] == 'Medical'
                                ? Icons.favorite_rounded
                                : Icons.local_fire_department_rounded,
                            color: urgencyColor,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alert['title'],
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                alert['location'],
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Status chip
                    _emergencyInfoRow(
                      Icons.radio_button_checked,
                      'Status',
                      alert['status'] ?? 'Active',
                      AppColors.teal,
                    ),
                    const SizedBox(height: 14),

                    // Description box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        alert['description'] ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Location
                    _emergencyInfoRow(
                      Icons.location_on_outlined,
                      'Address',
                      alert['addressText'] ?? alert['location'],
                      AppColors.red,
                    ),
                    const SizedBox(height: 14),

                    // Reported by
                    _emergencyInfoRow(
                      Icons.report_outlined,
                      'Reported by',
                      alert['reportedBy'] ?? 'Unknown',
                      AppColors.amber,
                    ),
                    const SizedBox(height: 18),

                    // Required skills
                    if (skills.isNotEmpty) ...[
                      const Text(
                        'Skills needed',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: skills
                            .map<Widget>(
                              (s) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.tealLight,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  s as String,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.teal,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Volunteers responded
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Volunteers responded',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: urgencyColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${responded.length} / $needed',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: urgencyColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (responded.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.redLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.person_off_outlined,
                              size: 16,
                              color: AppColors.red,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'No volunteers yet — be the first!',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...responded.map<Widget>(
                        (v) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.tealLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: const BoxDecoration(
                                  color: AppColors.teal,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.person,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  v as String,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.teal,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'En route',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Directions button — opens Google Maps with live routing
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final lat = alert['lat'] as double?;
                          final lng = alert['lng'] as double?;
                          if (lat != null && lng != null) {
                            _openMapsDirections(lat, lng);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Location unavailable — enable GPS and try again.',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.directions_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        label: const Text(
                          'Get Directions',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: urgencyColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // I'll Respond — confirms response and shows snackbar with directions
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmRespond(alert),
                        icon: Icon(
                          Icons.bolt_rounded,
                          color: urgencyColor,
                          size: 18,
                        ),
                        label: Text(
                          "I'll Respond",
                          style: TextStyle(
                            color: urgencyColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: urgencyColor, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
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

  Widget _emergencyInfoRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── FIXED: Live Map Card now navigates to MapScreen tab ──────────────────
  Widget _buildLiveMapCard() {
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = 1), // switch to Map tab
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: AppColors.tealLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.teal.withOpacity(0.3)),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.map_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Live Emergency Map',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.teal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap to view nearby alerts on map',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
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

  Widget _buildAIDetectorCard() {
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = 1),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.redLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.red.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Incident Detector',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap to analyze & classify emergencies using AI',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildSOSButton() {
    return GestureDetector(
      onTap: () => _showAISOSTriage(context),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.red,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.red.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'SOS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  void _showAISOSTriage(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, sc) =>
            VoiceSOSSheet(nearbyVolunteers: AppData.sosVolunteers),
      ),
    );
  }

  Widget _buildBottomNav() {
    final bool isAuth = AppData.loginType == 'authorised';
    // Authorised: Home(0), Detector(1), Map(2), Profile(3)
    // Volunteer:  Home(0), Map(1), Train(2), Profile(3)
    final items = isAuth
        ? [
            {
              'icon': Icons.home_outlined,
              'activeIcon': Icons.home_rounded,
              'label': 'Home',
            },
            {
              'icon': Icons.camera_alt_outlined,
              'activeIcon': Icons.camera_alt_rounded,
              'label': 'Detector',
            },
            {
              'icon': Icons.map_outlined,
              'activeIcon': Icons.map_rounded,
              'label': 'Map',
            },
            {
              'icon': Icons.person_outline,
              'activeIcon': Icons.person_rounded,
              'label': 'Profile',
            },
          ]
        : [
            {
              'icon': Icons.home_outlined,
              'activeIcon': Icons.home_rounded,
              'label': 'Home',
            },
            {
              'icon': Icons.map_outlined,
              'activeIcon': Icons.map_rounded,
              'label': 'Map',
            },
            {
              'icon': Icons.school_outlined,
              'activeIcon': Icons.school_rounded,
              'label': 'Train',
            },
            {
              'icon': Icons.person_outline,
              'activeIcon': Icons.person_rounded,
              'label': 'Profile',
            },
          ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.asMap().entries.map((e) {
              final i = e.key;
              final item = e.value;
              final bool selected = _selectedIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedIndex = i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected
                          ? item['activeIcon'] as IconData
                          : item['icon'] as IconData,
                      color: selected ? AppColors.red : AppColors.textSecondary,
                      size: 24,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item['label'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        color:
                            selected ? AppColors.red : AppColors.textSecondary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showGeminiChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GeminiChatSheet(),
    );
  }

  PageRoute _slideRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, a, __) => page,
      transitionsBuilder: (_, a, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 350),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  NEARBY HEROES SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class NearbyHeroesScreen extends StatelessWidget {
  const NearbyHeroesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Nearby Heroes',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.redLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const _DotWidget(color: Color(0xFF4ADE80)),
                const SizedBox(width: 4),
                Text(
                  '${AppData.nearbyVolunteers.where((v) => v['isOnline'] == true).length} online',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Volunteers section
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Volunteer Heroes',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            ...AppData.nearbyVolunteers.map(
              (hero) => _volunteerCard(context, hero),
            ),

            // Authorised Officers section
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 20, 0, 12),
              child: Text(
                'Authorised Officers',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            ...AppData.authorisedOfficers.map(
              (officer) => _officerCard(context, officer),
            ),
          ],
        ),
      ),
    );
  }

  Widget _volunteerCard(BuildContext context, Map<String, dynamic> hero) {
    final bool isOnline = hero['isOnline'] == true;
    final Color color = Color(hero['color'] as int);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOnline ? color.withOpacity(0.25) : AppColors.border,
          width: isOnline ? 1 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withOpacity(0.15),
                child: Text(
                  hero['initials'],
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isOnline
                        ? const Color(0xFF4ADE80)
                        : Colors.grey.shade400,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hero['name'],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 4,
                  children: (hero['skills'] as List)
                      .map(
                        (s) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            s,
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 11,
                      color: AppColors.textSecondary,
                    ),
                    Text(
                      ' ${hero['distance']}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.shield_outlined, size: 11, color: color),
                    Text(
                      ' Lv.${hero['level']}',
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              _callButton(context, hero['phone'], color),
              const SizedBox(height: 4),
              Text(
                isOnline ? 'Available' : 'Offline',
                style: TextStyle(
                  fontSize: 9,
                  color: isOnline ? const Color(0xFF4ADE80) : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _officerCard(BuildContext context, Map<String, dynamic> officer) {
    final Color color = Color(officer['color'] as int);
    final bool isOnDuty = officer['isOnDuty'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
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
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withOpacity(0.15),
                  child: Text(
                    officer['initials'],
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        officer['name'],
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        officer['role'],
                        style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isOnDuty
                        ? const Color(0xFF4ADE80).withOpacity(0.15)
                        : Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _DotWidget(
                        color: isOnDuty ? const Color(0xFF4ADE80) : Colors.grey,
                        size: 6,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOnDuty ? 'On Duty' : 'Off Duty',
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              isOnDuty ? const Color(0xFF4ADE80) : Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _detailRow(
                  Icons.account_balance_rounded,
                  officer['department'],
                  color,
                ),
                const SizedBox(height: 6),
                _detailRow(
                  Icons.badge_outlined,
                  'Badge: ${officer['badgeId']}',
                  color,
                ),
                const SizedBox(height: 6),
                _detailRow(
                  Icons.location_city_rounded,
                  officer['jurisdiction'],
                  color,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _callButton(
                        context,
                        officer['phone'],
                        color,
                        label: 'Office Line',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _emergencyCallButton(
                        context,
                        officer['emergency'],
                        color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color.withOpacity(0.7)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _callButton(
    BuildContext context,
    String phone,
    Color color, {
    String? label,
  }) {
    return GestureDetector(
      onTap: () => _showCallDialog(context, phone, color),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.call_outlined, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label ?? 'Call',
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emergencyCallButton(
    BuildContext context,
    String number,
    Color color,
  ) {
    return GestureDetector(
      onTap: () => _showCallDialog(context, number, AppColors.red),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.red,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emergency_rounded, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              number,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCallDialog(BuildContext context, String number, Color color) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.call_rounded, color: color, size: 26),
            ),
            const SizedBox(height: 16),
            const Text(
              'Call',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              number,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.call_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Call Now',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
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
//  MISSIONS DONE SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class MissionsDoneScreen extends StatelessWidget {
  const MissionsDoneScreen({super.key});

  int get _totalXp =>
      AppData.completedMissions.fold(0, (sum, m) => sum + (m['xp'] as int));
  double get _avgScore => AppData.completedMissions.isEmpty
      ? 0
      : AppData.completedMissions.fold(
            0.0,
            (sum, m) => sum + (m['score'] as int),
          ) /
          AppData.completedMissions.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Missions Done',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        child: Column(
          children: [
            // Summary card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.teal,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.teal.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _summaryItem(
                    '${AppData.completedMissions.length}',
                    'Total',
                    Icons.check_circle_outline,
                  ),
                  _vDivider(),
                  _summaryItem('+$_totalXp XP', 'Earned', Icons.star_outline),
                  _vDivider(),
                  _summaryItem(
                    '${_avgScore.toStringAsFixed(0)}%',
                    'Avg Score',
                    Icons.bar_chart,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Mission list
            ...AppData.completedMissions.map((m) => _missionCard(m)),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _vDivider() =>
      Container(width: 1, height: 48, color: Colors.white.withOpacity(0.25));

  Widget _missionCard(Map<String, dynamic> m) {
    final Color color = Color(m['color'] as int);
    final int score = m['score'] as int;
    final Color scoreColor = score >= 90
        ? AppColors.teal
        : score >= 75
            ? AppColors.amber
            : AppColors.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(m['icon'] as IconData, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['title'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${m['category']} • ${m['location']}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Score badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scoreColor.withOpacity(0.3)),
                ),
                child: Text(
                  '$score%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: scoreColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Score bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 5,
              backgroundColor: scoreColor.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(scoreColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _pill(
                Icons.calendar_today_outlined,
                m['date'],
                AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              _pill(
                Icons.timer_outlined,
                m['duration'],
                AppColors.textSecondary,
              ),
              const Spacer(),
              _pill(Icons.star_rounded, '+${m['xp']} XP', color),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  RANK & LEADERBOARD SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class RankAndLeaderboardScreen extends StatefulWidget {
  const RankAndLeaderboardScreen({super.key});

  @override
  State<RankAndLeaderboardScreen> createState() =>
      _RankAndLeaderboardScreenState();
}

class _RankAndLeaderboardScreenState extends State<RankAndLeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final DateTime _focusedMonth = DateTime(2026, 4);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Your Rank',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.amber,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.amber,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: '📅  Calendar'),
            Tab(text: '🏆  Leaderboard'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_buildCalendarTab(), _buildLeaderboardTab()],
      ),
    );
  }

  Widget _buildCalendarTab() {
    final user = AppData.volunteerProfile;
    final streak = user['streak'] as int? ?? 5;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        children: [
          // Rank + streak summary
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFBA7517), Color(0xFFE8931C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.amber.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Global Rank',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '#${user['rank'] ?? 42}',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🔥', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 4),
                            Text(
                              '$streak day streak',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          user['initials'] ?? 'U',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${user['totalXp'] ?? 0} XP total',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          // Calendar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'April 2026',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.amberLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${AppData.dailyActivity.values.where((v) => v['done'] == true).length} active days',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.amber,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Weekday headers
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                      .map(
                        (d) => Text(
                          d,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                _buildCalendarGrid(),
                const SizedBox(height: 12),
                // Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _legendDot(AppColors.teal, 'Active day'),
                    const SizedBox(width: 16),
                    _legendDot(AppColors.red, 'Missed'),
                    const SizedBox(width: 16),
                    _legendDot(AppColors.border, 'No data'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          // Daily log
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ...AppData.dailyActivity.entries
                    .take(7)
                    .map((e) => _activityRow(e.key, e.value)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    // April 2026 starts on Wednesday (index 2 in Mon-based week)
    final List<Widget> cells = [];
    // Padding before April 1 (Wednesday = 2 blank cells for Mon-based)
    for (int i = 0; i < 2; i++) {
      cells.add(const SizedBox(width: 36, height: 36));
    }
    // Days 1–30
    for (int day = 1; day <= 30; day++) {
      final key = '2026-04-${day.toString().padLeft(2, '0')}';
      final data = AppData.dailyActivity[key];
      final bool hasData = data != null;
      final bool active = hasData && data['done'] == true;
      final bool today = day == 17;

      cells.add(
        GestureDetector(
          onTap: hasData ? () => _showDayDetail(key, data) : null,
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: today
                  ? AppColors.amber
                  : active
                      ? AppColors.tealLight
                      : hasData
                          ? AppColors.redLight
                          : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border:
                  today ? Border.all(color: AppColors.amber, width: 2) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: today ? FontWeight.w900 : FontWeight.w500,
                    color: today
                        ? AppColors.amber
                        : active
                            ? AppColors.teal
                            : hasData
                                ? AppColors.red
                                : AppColors.textSecondary,
                  ),
                ),
                if (active) const SizedBox(height: 2),
                if (active)
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: AppColors.teal,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1,
      children: cells,
    );
  }

  void _showDayDetail(String dateKey, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              dateKey,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _dayStatItem('${data['xp']} XP', 'Earned', AppColors.amber),
                _dayStatItem('${data['missions']}', 'Missions', AppColors.teal),
                _dayStatItem(
                  data['done'] == true ? 'Active ✅' : 'Missed ❌',
                  'Status',
                  data['done'] == true ? AppColors.teal : AppColors.red,
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _dayStatItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _activityRow(String date, Map<String, dynamic> data) {
    final bool active = data['done'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: active ? AppColors.tealLight : AppColors.redLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              active ? Icons.check_circle_rounded : Icons.cancel_outlined,
              color: active ? AppColors.teal : AppColors.red,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${data['missions']} mission(s)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            active ? '+${data['xp']} XP' : 'No activity',
            style: TextStyle(
              fontSize: 12,
              color: active ? AppColors.teal : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildLeaderboardTab() {
    final userName = (AppData.volunteerProfile['name'] as String? ?? '').isEmpty
        ? 'You'
        : AppData.volunteerProfile['name'];
    final userRank = AppData.volunteerProfile['rank'] as int? ?? 42;
    final userXp = AppData.volunteerProfile['xp'] as int? ?? 680;
    final userStreak = AppData.volunteerProfile['streak'] as int? ?? 5;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        children: [
          // Top 3 podium
          _buildPodium(),
          const SizedBox(height: 20),

          // Your position
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.amberLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.amber.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '#$userRank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.amber,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$userXp XP • 🔥 $userStreak day streak',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          // Full list (4 onwards)
          ...AppData.leaderboard.skip(3).map(
                (entry) =>
                    _leaderboardRow(entry, isUser: entry['rank'] == userRank),
              ),
        ],
      ),
    );
  }

  Widget _buildPodium() {
    final top3 = AppData.leaderboard.take(3).toList();
    // Order: 2nd, 1st, 3rd
    final podiumOrder = [top3[1], top3[0], top3[2]];
    final heights = [90.0, 120.0, 70.0];
    final medals = ['🥈', '🥇', '🥉'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.amber.withOpacity(0.1), AppColors.amberLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.amber.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          const Text(
            'Top Heroes',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: podiumOrder.asMap().entries.map((e) {
              final idx = e.key;
              final p = e.value;
              final Color color = Color(p['color'] as int);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(medals[idx], style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 4),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: color.withOpacity(0.15),
                    child: Text(
                      p['initials'],
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p['name'].toString().split(' ')[0],
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${p['xp']} XP',
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 70,
                    height: heights[idx],
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      border: Border.all(color: color.withOpacity(0.3)),
                    ),
                    child: Center(
                      child: Text(
                        '#${p['rank']}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _leaderboardRow(Map<String, dynamic> entry, {bool isUser = false}) {
    final Color color = Color(entry['color'] as int);
    final int rank = entry['rank'] as int;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isUser ? AppColors.amberLight : AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isUser ? AppColors.amber.withOpacity(0.4) : AppColors.border,
          width: isUser ? 1 : 0.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: rank <= 10 ? AppColors.amber : AppColors.textSecondary,
              ),
            ),
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withOpacity(0.15),
            child: Text(
              entry['initials'],
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry['name'],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (isUser) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.amber,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '🔥 ${entry['streak']} day streak',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${entry['xp']} XP',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.amber,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  GEMINI CHAT SHEET
// ══════════════════════════════════════════════════════════════════════════════
class GeminiChatSheet extends StatefulWidget {
  const GeminiChatSheet({super.key});

  @override
  State<GeminiChatSheet> createState() => _GeminiChatSheetState();
}

class _GeminiChatSheetState extends State<GeminiChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isTyping = false;

  final List<Map<String, String>> _messages = [
    {
      'role': 'assistant',
      'text':
          'Hello! I\'m your Gemini AI Guide. I can help you with emergency procedures, training tips, and mission advice. How can I help you today?',
    },
  ];

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isTyping = true;
    });
    _scrollDown();
    // Use GeminiService (real API call)
    final reply = await GeminiService.generateContent(text, 'basic');
    if (mounted) {
      setState(() {
        _isTyping = false;
        _messages.add({'role': 'assistant', 'text': reply});
      });
      _scrollDown();
    }
  }

  void _scrollDown() {
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.gemini,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gemini AI Guide',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Emergency assistance powered by Gemini',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.close,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, i) {
                if (_isTyping && i == _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.geminiLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: AppColors.gemini,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Gemini is thinking...',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.gemini,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final msg = _messages[i];
                final isUser = msg['role'] == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? AppColors.gemini : AppColors.geminiLight,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: isUser
                            ? const Radius.circular(14)
                            : const Radius.circular(4),
                        bottomRight: isUser
                            ? const Radius.circular(4)
                            : const Radius.circular(14),
                      ),
                    ),
                    child: Text(
                      msg['text']!,
                      style: TextStyle(
                        fontSize: 13,
                        color: isUser ? Colors.white : AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ask about emergency steps...',
                      hintStyle: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _sendMessage(_controller.text),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.gemini,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 18,
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
//  DYNAMIC GEMINI INSIGHT CARD — Personalized, not static
// ══════════════════════════════════════════════════════════════════════════════
class _DynamicGeminiInsightCard extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> nearbyAlerts;
  const _DynamicGeminiInsightCard({
    required this.user,
    required this.nearbyAlerts,
  });

  @override
  State<_DynamicGeminiInsightCard> createState() =>
      _DynamicGeminiInsightCardState();
}

class _DynamicGeminiInsightCardState extends State<_DynamicGeminiInsightCard> {
  String? _insight;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generateInsight();
  }

  Future<void> _generateInsight() async {
    setState(() => _loading = true);
    final name = (widget.user['name'] as String? ?? '').isEmpty
        ? 'Volunteer'
        : widget.user['name'];
    final level = widget.user['level'] ?? 3;
    final xp = widget.user['xp'] ?? 680;
    final xpMax = widget.user['xpMax'] ?? 1000;
    final skills =
        (widget.user['skills'] as List<dynamic>?)?.cast<String>().join(', ') ??
            'General';
    final missions = widget.user['missionsCompleted'] ?? 0;
    final streak = widget.user['streak'] ?? 0;
    final alertTypes = widget.nearbyAlerts.map((a) => a['type']).join(', ');

    final prompt =
        'Volunteer $name is Hero Level $level with $xp/$xpMax XP, $missions missions completed, '
        '$streak day streak, skills: $skills. Nearby emergency types: $alertTypes. '
        'Give ONE short, personalized, motivating insight (1-2 sentences max) about what they should do today to advance — '
        'connecting their skills to the nearby emergencies and their XP progress. Be specific and actionable.';
    final result = await GeminiService.generateContent(prompt, 'basic');
    if (mounted)
      setState(() {
        _insight = result;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.geminiLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.gemini.withOpacity(0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.gemini,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Gemini AI Insight',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gemini,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gemini.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Personalised',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppColors.gemini,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _generateInsight,
                      child: const Icon(
                        Icons.refresh_rounded,
                        size: 14,
                        color: AppColors.gemini,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_loading)
                  const Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gemini,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Generating your insight...',
                        style: TextStyle(fontSize: 12, color: AppColors.gemini),
                      ),
                    ],
                  )
                else
                  Text(
                    _insight ?? 'Keep going — every mission counts!',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const GeminiChatSheet(),
                    );
                  },
                  child: const Row(
                    children: [
                      Text(
                        'Ask Gemini for guidance',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.gemini,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: AppColors.gemini,
                      ),
                    ],
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
//  AI ALERT CARD — Volunteer-to-Task Matching + Predicted Response Time
// ══════════════════════════════════════════════════════════════════════════════
class _AIAlertCard extends StatefulWidget {
  final Map<String, dynamic> alert;
  final Color urgencyColor;
  final Color urgencyBg;
  final bool isHigh;
  final List<String> userSkills;
  final VoidCallback onRespond;

  const _AIAlertCard({
    required this.alert,
    required this.urgencyColor,
    required this.urgencyBg,
    required this.isHigh,
    required this.userSkills,
    required this.onRespond,
  });

  @override
  State<_AIAlertCard> createState() => _AIAlertCardState();
}

class _AIAlertCardState extends State<_AIAlertCard> {
  String? _matchLabel;
  String? _predictedTime;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _runAIMatch();
  }

  Future<void> _runAIMatch() async {
    setState(() => _loading = true);
    final requiredSkills =
        (widget.alert['requiredSkills'] as List<dynamic>?)?.cast<String>() ??
            [];
    final userSkills = widget.userSkills;
    final incidentType = widget.alert['type'] ?? 'Unknown';

    final prompt =
        'A ${widget.isHigh ? "HIGH urgency" : "MEDIUM urgency"} $incidentType incident requires skills: ${requiredSkills.join(", ")}. '
        'Volunteer has skills: ${userSkills.isEmpty ? "General First Aid" : userSkills.join(", ")}. '
        'Return a JSON object (no markdown) with two fields: '
        '"match" (one of: "Strong Match", "Partial Match", "Low Match") and '
        '"eta" (estimated response time like "~4 min" based on urgency and skill fit). '
        'Only return the raw JSON, nothing else.';
    final result = await GeminiService.generateContent(prompt, 'basic');
    if (mounted) {
      try {
        final clean =
            result.replaceAll('```json', '').replaceAll('```', '').trim();
        final json = jsonDecode(clean) as Map<String, dynamic>;
        setState(() {
          _matchLabel = json['match'] as String?;
          _predictedTime = json['eta'] as String?;
          _loading = false;
        });
      } catch (_) {
        setState(() {
          _matchLabel = userSkills.any((s) => requiredSkills.contains(s))
              ? 'Strong Match'
              : 'Partial Match';
          _predictedTime = widget.isHigh ? '~5 min' : '~12 min';
          _loading = false;
        });
      }
    }
  }

  Color get _matchColor {
    switch (_matchLabel) {
      case 'Strong Match':
        return AppColors.teal;
      case 'Partial Match':
        return AppColors.amber;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              widget.isHigh ? AppColors.red.withOpacity(0.3) : AppColors.border,
          width: widget.isHigh ? 1 : 0.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: widget.urgencyBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.alert['type'] == 'Medical'
                      ? Icons.favorite_outline
                      : Icons.local_fire_department_outlined,
                  color: widget.urgencyColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.alert['title'],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.alert['location']} • ${widget.alert['time']}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: widget.onRespond,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: widget.urgencyColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Respond',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // AI Matching Row
          const SizedBox(height: 8),
          if (_loading)
            Row(
              children: [
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.gemini,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'AI matching your skills...',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.gemini.withOpacity(0.8),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 11,
                  color: AppColors.gemini,
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _matchColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _matchColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    _matchLabel ?? 'Checking...',
                    style: TextStyle(
                      fontSize: 10,
                      color: _matchColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.timer_outlined,
                  size: 11,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 3),
                Text(
                  _predictedTime ?? '--',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const Text(
                  'AI matched',
                  style: TextStyle(fontSize: 9, color: AppColors.gemini),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  AI SOS TRIAGE SHEET — Describe incident, get Gemini triage advice
// ══════════════════════════════════════════════════════════════════════════════
// ── Helper widgets ────────────────────────────────────────────────────────────
class _DotWidget extends StatelessWidget {
  final Color color;
  final double size;
  const _DotWidget({required this.color, this.size = 7});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
