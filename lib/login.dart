// login.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_screen.dart'; // AppColors, AppData, HomeScreen
import 'location_presence.dart'; // PresenceService

// ══════════════════════════════════════════════════════════════════════════════
// AUTH SERVICE
// ══════════════════════════════════════════════════════════════════════════════
class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  // ── VOLUNTEER ──────────────────────────────────────────────────────────────
  static Future<void> volunteerRegister({
    required String email,
    required String password,
    required String name,
    required String username,
  }) async {
    UserCredential? cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException {
      rethrow;
    }

    final uid = cred.user!.uid;
    final initials = _initials(name, 'U');

    // Best-effort Firestore write — if it fails, user can still log in; profile saves on next action
    try {
      await _db.collection('volunteers').doc(uid).set({
        'name': name,
        'email': email,
        'username': username,
        'initials': initials,
        'uid': uid,
        'role': 'volunteer',
        'isOnline': false, // will be set true by PresenceService.goOnline()
        'skills': [], // volunteer fills this in profile screen
        'level': 1,
        'xp': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Firestore write failed but Auth account exists — still proceed so user isn't locked out
    }

    _populateVolunteer(
      name: name,
      email: email,
      username: username,
      initials: initials,
    );
  }

  static Future<void> volunteerSignIn({
    required String email,
    required String password,
  }) async {
    UserCredential cred;
    try {
      cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException {
      rethrow;
    }

    final uid = cred.user!.uid;
    final authEmail = cred.user!.email ?? '';
    // Use Firebase Auth displayName if present (set by Google/social login)
    final authDisplayName = cred.user!.displayName ?? '';

    try {
      final doc = await _db.collection('volunteers').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        // Prefer Firestore name → Firebase displayName → friendly email local part
        final resolvedName = _resolvedName(
          firestoreName: data['name'],
          displayName: authDisplayName,
          email: authEmail,
        );
        _populateVolunteer(
          name: resolvedName,
          email: data['email'] ?? authEmail,
          username: data['username'] ?? _emailToUsername(authEmail),
          initials: data['initials'] ?? _initials(resolvedName, 'V'),
        );
      } else {
        // Profile doc missing — derive friendly name from Auth data
        final resolvedName = _resolvedName(
          firestoreName: null,
          displayName: authDisplayName,
          email: authEmail,
        );
        _populateVolunteer(
          name: resolvedName,
          email: authEmail,
          username: _emailToUsername(authEmail),
          initials: _initials(resolvedName, 'V'),
        );
      }
    } catch (e) {
      // Firestore unreachable — still derive a friendly name
      final resolvedName = _resolvedName(
        firestoreName: null,
        displayName: authDisplayName,
        email: authEmail,
      );
      _populateVolunteer(
        name: resolvedName,
        email: authEmail,
        username: _emailToUsername(authEmail),
        initials: _initials(resolvedName, 'V'),
      );
    }
  }

  static void _populateVolunteer({
    required String name,
    required String email,
    required String username,
    required String initials,
  }) {
    AppData.volunteerProfile['name'] = name;
    AppData.volunteerProfile['email'] = email;
    AppData.volunteerProfile['username'] = username;
    AppData.volunteerProfile['initials'] = initials;
    AppData.loginType = 'volunteer';
    // Mark volunteer online and write GPS location to Firestore
    PresenceService.instance.goOnline();
  }

  // ── AUTHORISED ─────────────────────────────────────────────────────────────
  static Future<void> authorisedRegister({
    required String email,
    required String password,
    required String name,
    required String username,
    required String officerId,
    required String department,
  }) async {
    UserCredential? cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException {
      rethrow;
    }

    final uid = cred.user!.uid;
    final initials = _initials(name, 'OF');

    // Best-effort Firestore write — if it fails, user can still log in; profile saves on next action
    try {
      await _db.collection('authorised_officers').doc(uid).set({
        'name': name,
        'email': email,
        'username': username,
        'officerId': officerId,
        'department': department,
        'initials': initials,
        'uid': uid,
        'role': 'authorised',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Firestore write failed but Auth account exists — still proceed so user isn't locked out
    }

    _populateAuthorised(
      name: name,
      email: email,
      username: username,
      officerId: officerId,
      department: department,
      initials: initials,
    );
  }

  static Future<void> authorisedSignIn({
    required String email,
    required String password,
  }) async {
    UserCredential cred;
    try {
      cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException {
      rethrow;
    }

    final uid = cred.user!.uid;
    final authEmail = cred.user!.email ?? '';
    final authDisplayName = cred.user!.displayName ?? '';

    try {
      final doc = await _db.collection('authorised_officers').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final resolvedName = _resolvedName(
          firestoreName: data['name'],
          displayName: authDisplayName,
          email: authEmail,
        );
        _populateAuthorised(
          name: resolvedName,
          email: data['email'] ?? authEmail,
          username: data['username'] ?? _emailToUsername(authEmail),
          officerId: data['officerId'] ?? '',
          department: data['department'] ?? '',
          initials: data['initials'] ?? _initials(resolvedName, 'OF'),
        );
      } else {
        final resolvedName = _resolvedName(
          firestoreName: null,
          displayName: authDisplayName,
          email: authEmail,
        );
        _populateAuthorised(
          name: resolvedName,
          email: authEmail,
          username: _emailToUsername(authEmail),
          officerId: '',
          department: '',
          initials: _initials(resolvedName, 'OF'),
        );
      }
    } catch (e) {
      final resolvedName = _resolvedName(
        firestoreName: null,
        displayName: authDisplayName,
        email: authEmail,
      );
      _populateAuthorised(
        name: resolvedName,
        email: authEmail,
        username: _emailToUsername(authEmail),
        officerId: '',
        department: '',
        initials: _initials(resolvedName, 'OF'),
      );
    }
  }

  static void _populateAuthorised({
    required String name,
    required String email,
    required String username,
    required String officerId,
    required String department,
    required String initials,
  }) {
    AppData.authorisedProfile['name'] = name;
    AppData.authorisedProfile['email'] = email;
    AppData.authorisedProfile['username'] = username;
    AppData.authorisedProfile['id'] = officerId;
    AppData.authorisedProfile['department'] = department;
    AppData.authorisedProfile['initials'] = initials;
    AppData.loginType = 'authorised';
  }

  // ── SIGN OUT ───────────────────────────────────────────────────────────────
  static Future<void> signOut() async {
    // Mark offline in Firestore before clearing local state
    await PresenceService.instance.goOffline();
    await _auth.signOut();
    AppData.volunteerProfile.updateAll((k, v) => '');
    AppData.authorisedProfile.updateAll((k, v) => '');
    AppData.loginType = '';
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────
  static String _initials(String name, String fallback) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (name.isNotEmpty) return name[0].toUpperCase();
    return fallback;
  }

  /// Returns the best available display name in order of preference:
  /// 1. Firestore stored name (non-empty, not an email)
  /// 2. Firebase Auth displayName (set by Google / social login)
  /// 3. Friendly name parsed from email local part (e.g. "nayan.kumar" → "Nayan Kumar")
  static String _resolvedName({
    required String? firestoreName,
    required String displayName,
    required String email,
  }) {
    // Prefer Firestore name if it looks like a real name (not an email address)
    if (firestoreName != null &&
        firestoreName.isNotEmpty &&
        !firestoreName.contains('@')) {
      return firestoreName;
    }
    // Firebase Auth displayName (Google sign-in sets this)
    if (displayName.isNotEmpty && !displayName.contains('@')) {
      return displayName;
    }
    // Parse the local part of the email into a friendly name
    return _emailToFriendlyName(email);
  }

  /// Converts an email local part to a title-cased name.
  /// "nayan.kumar@gmail.com" → "Nayan Kumar"
  /// "ravi_hero@gmail.com"   → "Ravi Hero"
  /// "santhosh123@gmail.com" → "Santhosh"
  static String _emailToFriendlyName(String email) {
    final local = email.split('@').first;
    // Split on dots, underscores, hyphens
    final parts = local.split(RegExp(r'[._\-]'));
    // Strip trailing digits from each part, title-case it
    final words = parts
        .map((p) => p.replaceAll(RegExp(r'\d+$'), ''))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .toList();
    return words.isNotEmpty ? words.join(' ') : email;
  }

  /// Returns the portion before '@' as a username, lowercased.
  static String _emailToUsername(String email) {
    return email.split('@').first.toLowerCase();
  }

  static String friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'user-not-found':
        return 'No account found. Please register first.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'email-already-in-use':
        return 'An account already exists with that email. Please sign in.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LOGIN SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  final String role; // 'volunteer' | 'authorised'
  const LoginScreen({super.key, required this.role});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isRegister = false;

  void _toggle() => setState(() => _isRegister = !_isRegister);

  @override
  Widget build(BuildContext context) {
    final isVolunteer = widget.role == 'volunteer';
    final accentColor = isVolunteer ? AppColors.red : AppColors.blue;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              _buildHeader(isVolunteer, accentColor),
              const SizedBox(height: 20),
              _buildModeToggle(accentColor),
              const SizedBox(height: 28),
              if (isVolunteer)
                _VolunteerForm(
                  key: ValueKey('vol_$_isRegister'),
                  isRegister: _isRegister,
                  onToggle: _toggle,
                )
              else
                _AuthorisedForm(
                  key: ValueKey('auth_$_isRegister'),
                  isRegister: _isRegister,
                  onToggle: _toggle,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isVolunteer, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.arrow_back,
              size: 18,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.3),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(
            isVolunteer
                ? Icons.volunteer_activism_rounded
                : Icons.verified_user_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isVolunteer ? 'Volunteer' : 'Authorised Officer',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isVolunteer
              ? 'Community first responder portal'
              : 'NDRF / SDRF / TNFRS officer portal',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildModeToggle(Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _toggleBtn(
            'Sign In',
            !_isRegister,
            accentColor,
            () => setState(() => _isRegister = false),
          ),
          _toggleBtn(
            'Register',
            _isRegister,
            accentColor,
            () => setState(() => _isRegister = true),
          ),
        ],
      ),
    );
  }

  Widget _toggleBtn(
    String label,
    bool active,
    Color accentColor,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active ? AppColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// VOLUNTEER FORM
// ══════════════════════════════════════════════════════════════════════════════
class _VolunteerForm extends StatefulWidget {
  final bool isRegister;
  final VoidCallback onToggle;
  const _VolunteerForm({
    super.key,
    required this.isRegister,
    required this.onToggle,
  });

  @override
  State<_VolunteerForm> createState() => _VolunteerFormState();
}

class _VolunteerFormState extends State<_VolunteerForm> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (widget.isRegister && (name.isEmpty || username.isEmpty)) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (widget.isRegister) {
        await AuthService.volunteerRegister(
          email: email,
          password: password,
          name: name,
          username: username,
        );
      } else {
        await AuthService.volunteerSignIn(email: email, password: password);
      }
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = AuthService.friendlyError(e));
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoBanner(
          color: AppColors.teal,
          bgColor: AppColors.tealLight,
          icon: Icons.volunteer_activism_outlined,
          text: widget.isRegister
              ? 'Create your volunteer account to start responding to emergencies.'
              : 'Welcome back! Sign in to your volunteer account.',
        ),
        const SizedBox(height: 24),

        if (widget.isRegister) ...[
          _loginField(
            controller: _nameCtrl,
            label: 'Full Name',
            hint: 'e.g. Arjun Kumar',
            icon: Icons.person_outline,
            accentColor: AppColors.red,
          ),
          const SizedBox(height: 14),
          _loginField(
            controller: _usernameCtrl,
            label: 'Username',
            hint: 'e.g. arjun_hero',
            icon: Icons.alternate_email,
            accentColor: AppColors.red,
          ),
          const SizedBox(height: 14),
        ],

        _loginField(
          controller: _emailCtrl,
          label: 'Email',
          hint: 'e.g. arjun@email.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          accentColor: AppColors.red,
        ),
        const SizedBox(height: 14),
        _passwordField(
          controller: _passwordCtrl,
          obscure: _obscure,
          onToggle: () => setState(() => _obscure = !_obscure),
          accentColor: AppColors.red,
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorBanner(_error!),
        ],
        const SizedBox(height: 28),

        _submitButton(
          label: widget.isRegister ? 'Create Account' : 'Sign In',
          color: AppColors.red,
          isLoading: _isLoading,
          onTap: _submit,
        ),
        const SizedBox(height: 16),

        Center(
          child: GestureDetector(
            onTap: widget.onToggle,
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                children: [
                  TextSpan(
                    text: widget.isRegister
                        ? 'Already have an account? '
                        : "Don't have an account? ",
                  ),
                  TextSpan(
                    text: widget.isRegister ? 'Sign In' : 'Register',
                    style: const TextStyle(
                      color: AppColors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// AUTHORISED FORM
// ══════════════════════════════════════════════════════════════════════════════
class _AuthorisedForm extends StatefulWidget {
  final bool isRegister;
  final VoidCallback onToggle;
  const _AuthorisedForm({
    super.key,
    required this.isRegister,
    required this.onToggle,
  });

  @override
  State<_AuthorisedForm> createState() => _AuthorisedFormState();
}

class _AuthorisedFormState extends State<_AuthorisedForm> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _error;

  static const _departments = [
    'NDRF',
    'SDRF',
    'TNFRS',
    'Police',
    'Civil Defence',
    'Medical Services',
  ];
  String _selectedDept = 'NDRF';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _idCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final id = _idCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (widget.isRegister && (name.isEmpty || username.isEmpty || id.isEmpty)) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (widget.isRegister) {
        await AuthService.authorisedRegister(
          email: email,
          password: password,
          name: name,
          username: username,
          officerId: id,
          department: _selectedDept,
        );
      } else {
        await AuthService.authorisedSignIn(email: email, password: password);
      }
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = AuthService.friendlyError(e));
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoBanner(
          color: AppColors.blue,
          bgColor: AppColors.blueLight,
          icon: Icons.verified_user_outlined,
          text: widget.isRegister
              ? 'Register your officer account for NDRF, SDRF, TNFRS and other departments.'
              : 'Welcome back, Officer. Sign in to your account.',
        ),
        const SizedBox(height: 24),

        if (widget.isRegister) ...[
          _loginField(
            controller: _nameCtrl,
            label: 'Full Name',
            hint: 'e.g. Officer Priya Sharma',
            icon: Icons.person_outline,
            accentColor: AppColors.blue,
          ),
          const SizedBox(height: 14),
          _loginField(
            controller: _usernameCtrl,
            label: 'Username',
            hint: 'e.g. priya_auth',
            icon: Icons.alternate_email,
            accentColor: AppColors.blue,
          ),
          const SizedBox(height: 14),
          _loginField(
            controller: _idCtrl,
            label: 'Officer ID',
            hint: 'e.g. NDRF-2024-001',
            icon: Icons.badge_outlined,
            accentColor: AppColors.blue,
          ),
          const SizedBox(height: 14),
          _departmentPicker(),
          const SizedBox(height: 14),
        ],

        _loginField(
          controller: _emailCtrl,
          label: 'Official Email',
          hint: 'e.g. priya@ndrf.gov.in',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          accentColor: AppColors.blue,
        ),
        const SizedBox(height: 14),
        _passwordField(
          controller: _passwordCtrl,
          obscure: _obscure,
          onToggle: () => setState(() => _obscure = !_obscure),
          accentColor: AppColors.blue,
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorBanner(_error!),
        ],
        const SizedBox(height: 28),

        _submitButton(
          label: widget.isRegister
              ? 'Create Officer Account'
              : 'Sign In as Officer',
          color: AppColors.blue,
          isLoading: _isLoading,
          onTap: _submit,
        ),
        const SizedBox(height: 16),

        Center(
          child: GestureDetector(
            onTap: widget.onToggle,
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                children: [
                  TextSpan(
                    text: widget.isRegister
                        ? 'Already registered? '
                        : "Don't have an account? ",
                  ),
                  TextSpan(
                    text: widget.isRegister ? 'Sign In' : 'Register',
                    style: const TextStyle(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _departmentPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Department',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _departments.map((dept) {
            final selected = _selectedDept == dept;
            return GestureDetector(
              onTap: () => setState(() => _selectedDept = dept),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected ? AppColors.blue : AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? AppColors.blue : AppColors.border,
                  ),
                ),
                child: Text(
                  dept,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED HELPER WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

Widget _buildInfoBanner({
  required Color color,
  required Color bgColor,
  required IconData icon,
  required String text,
}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: color, height: 1.5),
          ),
        ),
      ],
    ),
  );
}

Widget _loginField({
  required TextEditingController controller,
  required String label,
  required String hint,
  required IconData icon,
  required Color accentColor,
  TextInputType keyboardType = TextInputType.text,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
          prefixIcon: Icon(icon, size: 18, color: AppColors.textSecondary),
          filled: true,
          fillColor: AppColors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: accentColor, width: 1.5),
          ),
        ),
      ),
    ],
  );
}

Widget _passwordField({
  required TextEditingController controller,
  required bool obscure,
  required VoidCallback onToggle,
  required Color accentColor,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Password',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Enter your password',
          hintStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
          prefixIcon: const Icon(
            Icons.lock_outline,
            size: 18,
            color: AppColors.textSecondary,
          ),
          suffixIcon: GestureDetector(
            onTap: onToggle,
            child: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
          filled: true,
          fillColor: AppColors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: accentColor, width: 1.5),
          ),
        ),
      ),
    ],
  );
}

Widget _errorBanner(String message) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.redLight,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.red.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: AppColors.red, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ),
      ],
    ),
  );
}

Widget _submitButton({
  required String label,
  required Color color,
  required bool isLoading,
  required VoidCallback onTap,
}) {
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: isLoading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withOpacity(0.5),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: isLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
    ),
  );
}
