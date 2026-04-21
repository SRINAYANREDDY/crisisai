import 'package:flutter/material.dart';
import 'home_screen.dart'; // AppColors, AppData, HomeScreen
import 'train.dart'; // GeminiService
import 'map.dart'; // MapScreen
import 'profile.dart'; // AuthorisedPersonProfileTab
import 'detector.dart'; // DetectorScreen
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'login.dart'; // LoginScreen
import 'offline_ai_service.dart'; // OfflineCacheManager
import 'volunteer_repository.dart'; // Live Firestore volunteer feed
import 'location_service.dart'; // GPS singleton

import 'fcm_dispatch_service.dart';
import 'dispatch_notification_banner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GeminiService.init();
  await FCMDispatchService.instance.initialize();
  // Start background cache prewarm — builds offline AI cache while user is on
  // the role-selection screen. Non-blocking; never delays startup.
  OfflineCacheManager.prewarm();

  // Warm up GPS and volunteer feed in parallel — by the time the user logs in
  // and opens the SOS sheet or home panel, both are already populated.
  LocationService.instance.initialize();
  VolunteerRepository.instance.startListening();

  runApp(const CitizenHeroApp());
}

// ══════════════════════════════════════════════════════════════════════════════
//  APP ROOT
// ══════════════════════════════════════════════════════════════════════════════
class CitizenHeroApp extends StatelessWidget {
  const CitizenHeroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) => DispatchNotificationOverlay(child: child!),
      title: 'Citizen Hero Network',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'SF Pro Display',
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.red),
        useMaterial3: true,
      ),
      home: const RoleSelectionScreen(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ROLE SELECTION SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  // AI Readiness Score
  String? _volunteerReadinessScore;
  String? _authorisedReadinessScore;
  bool _loadingScores = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fetchAIReadinessScores();
  }

  Future<void> _fetchAIReadinessScores() async {
    setState(() => _loadingScores = true);
    // Fetch volunteer readiness
    final volPrompt =
        'For a new disaster response volunteer app user with no prior training, '
        'give a current AI readiness score out of 100 and ONE short sentence (under 12 words) '
        'on what to do first. Format: just "Score: XX/100 — [sentence]". Nothing else.';
    final authPrompt =
        'For an authorised emergency officer joining a disaster response network app, '
        'give an AI readiness score out of 100 and ONE short sentence (under 12 words) '
        'on their primary responsibility. Format: just "Score: XX/100 — [sentence]". Nothing else.';

    final results = await Future.wait([
      GeminiService.generateContent(volPrompt, 'basic'),
      GeminiService.generateContent(authPrompt, 'basic'),
    ]);

    if (mounted) {
      setState(() {
        _volunteerReadinessScore = results[0];
        _authorisedReadinessScore = results[1];
        _loadingScores = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _navigate(String role) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => LoginScreen(role: role),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: _blob(200, AppColors.red.withOpacity(0.07)),
          ),
          Positioned(
            bottom: -80,
            left: -50,
            child: _blob(260, AppColors.teal.withOpacity(0.06)),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 56),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.red.withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.shield_outlined,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Citizen Hero\nNetwork',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1.15,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Choose how you want to continue',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _dot(AppColors.red, 32),
                          const SizedBox(width: 6),
                          _dot(AppColors.teal, 10),
                        ],
                      ),
                      const SizedBox(height: 48),
                      // Onboarding: Skill Assessment Prompt
                      GestureDetector(
                        onTap: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const _AISkillAssessmentSheet(),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.teal.withOpacity(0.08),
                                AppColors.tealLight,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.teal.withOpacity(0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.teal,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.quiz_rounded,
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
                                      'New? Take the AI Skill Assessment',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.teal,
                                      ),
                                    ),
                                    Text(
                                      'Gemini will assess your current emergency skills and build your personalised training path.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: AppColors.teal,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ), // closes GestureDetector
                      const SizedBox(height: 24),
                      _roleCard(
                        role: 'volunteer',
                        title: 'Volunteer',
                        subtitle:
                            'Respond to emergencies, complete training missions and earn XP.',
                        icon: Icons.volunteer_activism_rounded,
                        color: AppColors.red,
                        bgColor: AppColors.redLight,
                        aiReadiness: _volunteerReadinessScore,
                        loadingScore: _loadingScores,
                      ),
                      const SizedBox(height: 16),
                      _roleCard(
                        role: 'authorised',
                        title: 'Authorised Person',
                        subtitle:
                            'Manage incidents, verify responders and oversee field operations.',
                        icon: Icons.verified_user_rounded,
                        color: AppColors.blue,
                        bgColor: AppColors.blueLight,
                        aiReadiness: _authorisedReadinessScore,
                        loadingScore: _loadingScores,
                      ),
                      const Spacer(),
                      Center(
                        child: Text(
                          'Citizen Hero Network v1.0',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary.withOpacity(0.6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleCard({
    required String role,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
    String? aiReadiness,
    bool loadingScore = false,
  }) {
    return GestureDetector(
      onTap: () => _navigate(role),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.07),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
              ],
            ),
            // AI Readiness Score
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF4285F4).withOpacity(0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 13,
                    color: Color(0xFF4285F4),
                  ),
                  const SizedBox(width: 6),
                  if (loadingScore)
                    const Expanded(
                      child: Text(
                        'AI calculating readiness score...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF4285F4),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        aiReadiness ?? 'AI Readiness: Tap to check',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF1C1917),
                          height: 1.4,
                        ),
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

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );

  Widget _dot(Color color, double width) => Container(
        width: width,
        height: 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  AUTHORISED HOME SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class AuthorisedHomeScreen extends StatefulWidget {
  const AuthorisedHomeScreen({super.key});

  @override
  State<AuthorisedHomeScreen> createState() => _AuthorisedHomeScreenState();
}

class _AuthorisedHomeScreenState extends State<AuthorisedHomeScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulse;

  Map<String, dynamic> get _officer => AppData.authorisedProfile;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_selectedIndex) {
      case 1:
        body = const DetectorScreen();
        break;
      case 2:
        body = const MapScreen();
        break;
      case 3:
        body = _AuthorisedProfileTab(officer: _officer);
        break;
      default:
        body = _AuthorisedDashboard(officer: _officer, pulse: _pulse);
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(key: ValueKey(_selectedIndex), child: body),
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) => Transform.scale(
          scale: _pulse.value,
          child: FloatingActionButton.extended(
            onPressed: () {},
            backgroundColor: AppColors.blue,
            elevation: 6,
            icon: const Icon(Icons.add_alert_rounded, color: Colors.white),
            label: const Text(
              'Alert',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      color: AppColors.white,
      elevation: 8,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.dashboard_outlined, Icons.dashboard, 'Dashboard', 0),
            _navItem(Icons.radar_outlined, Icons.radar, 'Detector', 1),
            const SizedBox(width: 48),
            _navItem(Icons.map_outlined, Icons.map, 'Map', 2),
            _navItem(
              Icons.manage_accounts_outlined,
              Icons.manage_accounts,
              'Profile',
              3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData out, IconData filled, String label, int i) {
    final bool sel = _selectedIndex == i;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = i),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            sel ? filled : out,
            size: 22,
            color: sel ? AppColors.blue : AppColors.textSecondary,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: sel ? AppColors.blue : AppColors.textSecondary,
              fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Authorised Dashboard ─────────────────────────────────────────────────────
class _AuthorisedDashboard extends StatelessWidget {
  final Map<String, dynamic> officer;
  final Animation<double> pulse;
  const _AuthorisedDashboard({required this.officer, required this.pulse});

  static const _incidents = [
    {
      'title': 'Cardiac Arrest — Anna Nagar',
      'type': 'Medical',
      'status': 'Active',
      'responders': 2,
      'needed': 3,
      'time': '3 min ago',
    },
    {
      'title': 'Building Fire — T. Nagar',
      'type': 'Fire',
      'status': 'Active',
      'responders': 4,
      'needed': 5,
      'time': '11 min ago',
    },
    {
      'title': 'Road Accident — Adyar',
      'type': 'Accident',
      'status': 'Resolved',
      'responders': 3,
      'needed': 3,
      'time': '42 min ago',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Command Centre',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              officer['name'] ?? '',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.blueLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.blue.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.verified_user_rounded,
                              size: 12,
                              color: AppColors.blue,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              officer['badgeId'] ?? '',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _overviewCard(
                        'Active Incidents',
                        '2',
                        Icons.warning_rounded,
                        AppColors.red,
                        AppColors.redLight,
                      ),
                      const SizedBox(width: 12),
                      _overviewCard(
                        'Volunteers On-field',
                        '17',
                        Icons.people_rounded,
                        AppColors.teal,
                        AppColors.tealLight,
                      ),
                      const SizedBox(width: 12),
                      _overviewCard(
                        'Resolved Today',
                        '5',
                        Icons.check_circle_rounded,
                        AppColors.amber,
                        AppColors.amberLight,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_city_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Jurisdiction',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                              Text(
                                officer['jurisdiction'] ?? '',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                officer['department'] ?? '',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              _GreenDot(),
                              SizedBox(width: 5),
                              Text(
                                'On Duty',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildAIDetectorCard(context),
                  const SizedBox(height: 24),
                  const Text(
                    'Active Incidents',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._incidents.map(_buildIncidentRow),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIDetectorCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DetectorScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1D4ED8), Color(0xFF1E3A8A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1D4ED8).withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.radar, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Crisis AI Detector',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Analyse drone/thermal footage\nto detect humans at risk',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Launch',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D4ED8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewCard(
    String label,
    String value,
    IconData icon,
    Color color,
    Color bg,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentRow(Map<String, dynamic> inc) {
    final bool active = inc['status'] == 'Active';
    final Color color = active ? AppColors.red : AppColors.teal;
    final Color bg = active ? AppColors.redLight : AppColors.tealLight;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? AppColors.red.withOpacity(0.25) : AppColors.border,
          width: active ? 1 : 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              inc['type'] == 'Medical'
                  ? Icons.medical_services_rounded
                  : inc['type'] == 'Fire'
                      ? Icons.local_fire_department_rounded
                      : Icons.car_crash_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inc['title'],
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${inc['responders']}/${inc['needed']} responders · ${inc['time']}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              inc['status'] as String,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Authorised Profile Tab ───────────────────────────────────────────────────
class _AuthorisedProfileTab extends StatelessWidget {
  final Map<String, dynamic> officer;
  const _AuthorisedProfileTab({required this.officer});

  @override
  Widget build(BuildContext context) {
    return AuthorisedPersonProfileTab(officer: officer);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  AI SKILL ASSESSMENT SHEET — Onboarding: Gemini interviews the new volunteer
// ══════════════════════════════════════════════════════════════════════════════
class _AISkillAssessmentSheet extends StatefulWidget {
  const _AISkillAssessmentSheet();

  @override
  State<_AISkillAssessmentSheet> createState() =>
      _AISkillAssessmentSheetState();
}

class _AISkillAssessmentSheetState extends State<_AISkillAssessmentSheet> {
  // 5 quick questions Gemini uses to assess skill level
  final List<Map<String, dynamic>> _questions = [
    {
      'q': 'Have you ever performed CPR on a real person?',
      'options': [
        'Yes, successfully',
        'Yes, but unsure',
        'Trained only',
        'Never',
      ],
    },
    {
      'q': 'What is the first step when you find an unconscious person?',
      'options': [
        'Start CPR immediately',
        'Check scene safety first',
        'Call for help and check breathing',
        'Give rescue breaths',
      ],
    },
    {
      'q': 'Have you attended any disaster response or first aid training?',
      'options': ['Yes, certified', 'Yes, informal', 'Online only', 'None yet'],
    },
    {
      'q': 'In a fire evacuation, which floor should you use?',
      'options': [
        'Lift (fastest)',
        'Stairs always',
        'Either, depending on floor',
        'Wait for firefighters',
      ],
    },
    {
      'q': 'How confident are you responding to a road accident scene?',
      'options': [
        'Very confident',
        'Somewhat confident',
        'I know basics',
        'Not confident at all',
      ],
    },
  ];

  int _currentQ = 0;
  final List<int> _answers = [];
  bool _assessing = false;
  String? _assessmentResult;

  void _selectAnswer(int index) {
    if (_answers.length <= _currentQ) {
      _answers.add(index);
    } else {
      _answers[_currentQ] = index;
    }
    if (_currentQ < _questions.length - 1) {
      setState(() => _currentQ++);
    } else {
      _submitAssessment();
    }
  }

  Future<void> _submitAssessment() async {
    setState(() => _assessing = true);
    final qaSummary = _questions.asMap().entries.map((e) {
      final ans = _answers.length > e.key
          ? (e.value['options'] as List)[_answers[e.key]]
          : 'No answer';
      return 'Q: ${e.value['q']} → A: $ans';
    }).join('\n');

    final prompt =
        'A new disaster response volunteer answered these onboarding questions:\n$qaSummary\n\n'
        'Based on these answers, provide:\n'
        '1) An overall skill level: Beginner / Intermediate / Advanced\n'
        '2) A skill score out of 100\n'
        '3) Top 2 certified skills they already seem to have\n'
        '4) Top 2 skill gaps to address urgently\n'
        '5) The single most important training block to start with (from: Basic Training, Survival Skills, Crisis Puzzles, Medical Aid, Fire Department, Rescue Team)\n'
        'Keep it concise and motivating. Format with clear labels.';

    final result = await GeminiService.generateContent(prompt, 'basic');
    if (mounted)
      setState(() {
        _assessmentResult = result;
        _assessing = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Skill Assessment',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Gemini builds your personalised training path',
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
              child: _assessmentResult != null
                  ? _buildResultView(scrollCtrl)
                  : _assessing
                      ? _buildLoadingView()
                      : _buildQuestionView(scrollCtrl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionView(ScrollController scrollCtrl) {
    final q = _questions[_currentQ];
    final options = q['options'] as List<String>;
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        // Progress bar
        Row(
          children: [
            Text(
              'Question ${_currentQ + 1} of ${_questions.length}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${((_currentQ / _questions.length) * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.teal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_currentQ + 1) / _questions.length,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.teal),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.tealLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.teal.withOpacity(0.25)),
          ),
          child: Text(
            q['q'] as String,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...options.asMap().entries.map(
              (e) => GestureDetector(
                onTap: () => _selectAnswer(e.key),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.tealLight,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            ['A', 'B', 'C', 'D'][e.key],
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.teal,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          e.value,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.tealLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.teal,
              size: 30,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Gemini is analysing your skills...',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Building your personalised training path',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(color: AppColors.teal),
        ],
      ),
    );
  }

  Widget _buildResultView(ScrollController scrollCtrl) {
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.teal, AppColors.teal.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.teal.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assessment Complete!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Your AI-powered training path is ready',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.tealLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.teal.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.teal,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Gemini Skill Assessment',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.teal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _assessmentResult!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.teal,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.teal.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.rocket_launch_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  'Start My Training Path',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() {
            _currentQ = 0;
            _answers.clear();
            _assessmentResult = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: 6),
                Text(
                  'Retake Assessment',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tiny reusable green dot ───────────────────────────────────────────────────
class _GreenDot extends StatelessWidget {
  const _GreenDot();
  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF4ADE80),
          shape: BoxShape.circle,
        ),
      );
}
