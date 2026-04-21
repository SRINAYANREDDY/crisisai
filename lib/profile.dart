// profile.dart
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'main.dart' show RoleSelectionScreen;
import 'trauma_check_screen.dart'; // Feature 2 — Mental Health Check-ins history

// ─── Shared colors ────────────────────────────────────────────────────────────
class _PC {
  static const Color red = Color(0xFFE24B4A);
  static const Color redLight = Color(0xFFFCEBEB);
  static const Color teal = Color(0xFF1D9E75);
  static const Color tealLight = Color(0xFFE1F5EE);
  static const Color amber = Color(0xFFBA7517);
  static const Color amberLight = Color(0xFFFAEEDA);
  static const Color blue = Color(0xFF1D4ED8);
  static const Color blueLight = Color(0xFFEFF6FF);
  static const Color gemini = Color(0xFF4285F4);
  static const Color geminiLight = Color(0xFFE8F0FE);
  static const Color text = Color(0xFF1A1A1A);
  static const Color muted = Color(0xFF6B6B6B);
  static const Color border = Color(0xFFE8E8E8);
  static const Color bg = Color(0xFFF7F6F3);
  static const Color white = Colors.white;
}

// ══════════════════════════════════════════════════════════════════════════════
//  VOLUNTEER PROFILE TAB
// ══════════════════════════════════════════════════════════════════════════════
class VolunteerProfileTab extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback? onProfileUpdated;
  const VolunteerProfileTab({
    super.key,
    required this.user,
    this.onProfileUpdated,
  });

  @override
  State<VolunteerProfileTab> createState() => _VolunteerProfileTabState();
}

class _VolunteerProfileTabState extends State<VolunteerProfileTab> {
  static const _skillsList = [
    {
      'title': 'First Aid',
      'level': 'Advanced',
      'progress': 0.85,
      'color': _PC.red,
    },
    {
      'title': 'CPR',
      'level': 'Intermediate',
      'progress': 0.60,
      'color': _PC.gemini,
    },
    {
      'title': 'Fire Safety',
      'level': 'Beginner',
      'progress': 0.35,
      'color': _PC.amber,
    },
  ];

  static const _badges = [
    {
      'icon': Icons.local_fire_department,
      'color': _PC.red,
      'bg': _PC.redLight,
      'label': 'First\nResponder',
    },
    {
      'icon': Icons.favorite,
      'color': Color(0xFFD81B60),
      'bg': Color(0xFFFCE4EC),
      'label': 'Life\nSaver',
    },
    {
      'icon': Icons.emoji_events,
      'color': _PC.amber,
      'bg': _PC.amberLight,
      'label': 'Top\nVolunteer',
    },
    {
      'icon': Icons.shield,
      'color': _PC.blue,
      'bg': _PC.blueLight,
      'label': 'Hero\nLevel 3',
    },
  ];

  static const _missions = [
    {
      'title': 'Cardiac Arrest Response',
      'location': 'Anna Nagar',
      'date': 'Apr 8, 2026',
      'xp': '+120 XP',
    },
    {
      'title': 'Fire Safety Drill',
      'location': 'T. Nagar',
      'date': 'Apr 5, 2026',
      'xp': '+80 XP',
    },
    {
      'title': 'First Aid Support',
      'location': 'Adyar',
      'date': 'Apr 2, 2026',
      'xp': '+100 XP',
    },
  ];

  Map<String, dynamic> get user => AppData.volunteerProfile;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 20),
            _buildHeroCard(),
            const SizedBox(height: 16),
            _buildStatsRow(),
            const SizedBox(height: 16),
            _buildSkillsSection(),
            const SizedBox(height: 16),
            _buildAchievementsSection(),
            const SizedBox(height: 16),
            _buildMissionHistory(),
            const SizedBox(height: 16),
            _buildSettingsSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Good morning,',
              style: TextStyle(fontSize: 13, color: _PC.muted),
            ),
            Text(
              user['name'] ?? 'Hero',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _PC.text,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_none, size: 26),
                  onPressed: () {},
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: _PC.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            CircleAvatar(
              radius: 20,
              backgroundColor: _PC.tealLight,
              child: Text(
                user['initials'] ?? 'U',
                style: const TextStyle(
                  color: _PC.teal,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroCard() {
    final skills = (user['skills'] as List<dynamic>?)?.cast<String>() ?? [];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _PC.red,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _PC.red.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withOpacity(0.2),
                child: Text(
                  user['initials'] ?? 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
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
                        const Icon(
                          Icons.shield,
                          color: Colors.white70,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Hero Level ${user['level'] ?? 1}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Active Volunteer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if ((user['username'] ?? '').isNotEmpty)
                      Text(
                        '@${user['username']}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              _activePill(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'XP Progress',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                ),
              ),
              Text(
                '${user['xp']} / ${user['xpMax']} XP',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value:
                  (user['xp'] as int? ?? 0) / (user['xpMax'] as int? ?? 1000),
              minHeight: 7,
              backgroundColor: Colors.white.withOpacity(0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Skills: ',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 12,
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: skills
                        .map(
                          (s) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              s,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
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

  Widget _activePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        children: [
          Icon(Icons.circle, color: Color(0xFF66BB6A), size: 8),
          SizedBox(width: 5),
          Text('Active', style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _statCard(
          Icons.check_circle_outline,
          _PC.teal,
          '${user['missionsCompleted'] ?? 0}',
          'Missions done',
        ),
        const SizedBox(width: 12),
        _statCard(
          Icons.people_outline,
          _PC.red,
          '${user['nearbyHeroes'] ?? 0}',
          'Nearby heroes',
        ),
        const SizedBox(width: 12),
        _statCard(
          Icons.bar_chart,
          _PC.amber,
          '#${user['rank'] ?? 42}',
          'Your rank',
        ),
      ],
    );
  }

  Widget _statCard(IconData icon, Color color, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _PC.white,
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
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: _PC.muted, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsSection() {
    return _sectionCard(
      title: 'My Skills',
      child: Column(
        children: _skillsList.asMap().entries.map((e) {
          final s = e.value;
          final color = s['color'] as Color;
          final isLast = e.key == _skillsList.length - 1;
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s['title'] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      s['level'] as String,
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: s['progress'] as double,
                    minHeight: 7,
                    backgroundColor: color.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAchievementsSection() {
    return _sectionCard(
      title: 'Achievements',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: _badges.map((b) {
          final color = b['color'] as Color;
          final bg = b['bg'] as Color;
          return Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(b['icon'] as IconData, color: color, size: 24),
              ),
              const SizedBox(height: 6),
              Text(
                b['label'] as String,
                style: const TextStyle(fontSize: 10, color: _PC.muted),
                textAlign: TextAlign.center,
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMissionHistory() {
    return _sectionCard(
      title: 'Recent Missions',
      child: Column(
        children: _missions.asMap().entries.map((e) {
          final m = e.value;
          final isLast = e.key == _missions.length - 1;
          return Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _PC.redLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: _PC.red,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m['title'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${m['location']} • ${m['date']}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: _PC.muted,
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
                      color: _PC.tealLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      m['xp'] as String,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _PC.teal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isLast) Divider(color: Colors.grey.shade100, height: 20),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context) {
    final items = [
      {
        'icon': Icons.edit_outlined,
        'label': 'Edit Profile',
        'sub': 'Name, skills, personal info',
        'onTap': () => _showEditProfile(context),
      },
      {
        'icon': Icons.favorite_rounded,
        'label': 'Mental Health Check-ins',
        'sub': 'View your wellbeing history',
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TraumaHistoryScreen()),
        ),
      },
      {
        'icon': Icons.location_on_outlined,
        'label': 'Location & Radius',
        'sub': 'Set location and detection radius',
        'onTap': () => _showLocationRadius(context),
      },
      {
        'icon': Icons.notifications_outlined,
        'label': 'Notifications',
        'sub': 'Push, SMS alerts',
        'onTap': () {},
      },
      {
        'icon': Icons.privacy_tip_outlined,
        'label': 'Privacy & Safety',
        'sub': 'Visibility, data controls',
        'onTap': () => _showPrivacySafety(context),
      },
      {
        'icon': Icons.help_outline,
        'label': 'Help & Support',
        'sub': 'FAQs, contact us',
        'onTap': () => _showHelpSupport(context),
      },
      {
        'icon': Icons.logout,
        'label': 'Sign Out',
        'isRed': true,
        'onTap': () => _confirmSignOut(context),
      },
    ];

    return _sectionCard(
      title: 'Settings',
      child: Column(
        children: items.asMap().entries.map((e) {
          final item = e.value;
          final isRed = item['isRed'] == true;
          final isLast = e.key == items.length - 1;
          return Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isRed ? _PC.redLight : const Color(0xFFF1EFE8),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    item['icon'] as IconData,
                    color: isRed ? _PC.red : _PC.muted,
                    size: 18,
                  ),
                ),
                title: Text(
                  item['label'] as String,
                  style: TextStyle(
                    fontSize: 14,
                    color: isRed ? _PC.red : _PC.text,
                    fontWeight: isRed ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                subtitle: item['sub'] != null
                    ? Text(
                        item['sub'] as String,
                        style: const TextStyle(fontSize: 11, color: _PC.muted),
                      )
                    : null,
                trailing: isRed
                    ? null
                    : const Icon(
                        Icons.chevron_right,
                        color: _PC.muted,
                        size: 20,
                      ),
                onTap: item['onTap'] as VoidCallback?,
              ),
              if (!isLast) Divider(color: Colors.grey.shade100, height: 1),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Edit Profile ──────────────────────────────────────────────────────────
  void _showEditProfile(BuildContext context) {
    final nameCtrl = TextEditingController(
      text: AppData.volunteerProfile['name'] ?? '',
    );
    final contactCtrl = TextEditingController(
      text: AppData.volunteerProfile['contactNumber'] ?? '',
    );
    final ageCtrl = TextEditingController(
      text: AppData.volunteerProfile['age'] ?? '',
    );
    final addressCtrl = TextEditingController(
      text: AppData.volunteerProfile['address'] ?? '',
    );
    String selectedGender =
        AppData.volunteerProfile['gender'] ?? 'Prefer not to say';
    List<String> selectedSkills = List<String>.from(
      AppData.volunteerProfile['skills'] ?? [],
    );

    const allSkills = [
      'First Aid',
      'CPR',
      'Fire Safety',
      'Flood Response',
      'Disaster Relief',
      'Search & Rescue',
      'Medical Support',
      'Traffic Control',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.92,
            decoration: const BoxDecoration(
              color: _PC.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _PC.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _PC.redLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.edit_outlined,
                          color: _PC.red,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Profile',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: _PC.text,
                              ),
                            ),
                            Text(
                              'Update your personal information',
                              style: TextStyle(fontSize: 12, color: _PC.muted),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, color: _PC.muted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Username (read-only)
                        _editInfoCard(
                          icon: Icons.alternate_email,
                          label: 'Username',
                          value:
                              '@${AppData.volunteerProfile['username'] ?? ''}',
                          color: _PC.gemini,
                          isReadOnly: true,
                        ),
                        const SizedBox(height: 8),
                        _editInfoCard(
                          icon: Icons.email_outlined,
                          label: 'Email (Login)',
                          value: AppData.volunteerProfile['email'] ?? '',
                          color: _PC.teal,
                          isReadOnly: true,
                        ),
                        const SizedBox(height: 20),
                        _editField(
                          controller: nameCtrl,
                          label: 'Full Name',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 14),
                        _editField(
                          controller: contactCtrl,
                          label: 'Contact Number',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 14),
                        _editField(
                          controller: ageCtrl,
                          label: 'Age',
                          icon: Icons.cake_outlined,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 14),
                        _editField(
                          controller: addressCtrl,
                          label: 'Address',
                          icon: Icons.home_outlined,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 14),
                        // Gender
                        const Text(
                          'Gender',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _PC.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children:
                              ['Male', 'Female', 'Other', 'Prefer not to say']
                                  .map(
                                    (g) => GestureDetector(
                                      onTap: () => setModalState(
                                        () => selectedGender = g,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selectedGender == g
                                              ? _PC.red
                                              : _PC.bg,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: selectedGender == g
                                                ? _PC.red
                                                : _PC.border,
                                          ),
                                        ),
                                        child: Text(
                                          g,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: selectedGender == g
                                                ? Colors.white
                                                : _PC.text,
                                            fontWeight: selectedGender == g
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                        const SizedBox(height: 20),
                        // Skills
                        const Text(
                          'Required Skills',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _PC.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: allSkills.map((s) {
                            final selected = selectedSkills.contains(s);
                            return GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  if (selected) {
                                    selectedSkills.remove(s);
                                  } else {
                                    selectedSkills.add(s);
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selected ? _PC.teal : _PC.bg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected ? _PC.teal : _PC.border,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selected) ...[
                                      const Icon(
                                        Icons.check,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      s,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: selected
                                            ? Colors.white
                                            : _PC.text,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () {
                              // Save data
                              AppData.volunteerProfile['name'] =
                                  nameCtrl.text.trim().isNotEmpty
                                  ? nameCtrl.text.trim()
                                  : AppData.volunteerProfile['name'];
                              AppData.volunteerProfile['contactNumber'] =
                                  contactCtrl.text.trim();
                              AppData.volunteerProfile['age'] = ageCtrl.text
                                  .trim();
                              AppData.volunteerProfile['address'] = addressCtrl
                                  .text
                                  .trim();
                              AppData.volunteerProfile['gender'] =
                                  selectedGender;
                              AppData.volunteerProfile['skills'] =
                                  selectedSkills;
                              final name =
                                  AppData.volunteerProfile['name'] as String;
                              final parts = name.trim().split(' ');
                              AppData.volunteerProfile['initials'] =
                                  parts.length >= 2
                                  ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
                                  : parts.isNotEmpty && parts[0].isNotEmpty
                                  ? parts[0][0].toUpperCase()
                                  : 'U';
                              Navigator.pop(ctx);
                              setState(() {}); // refresh profile tab
                              widget.onProfileUpdated
                                  ?.call(); // refresh HomeScreen appbar/hero card
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _PC.red,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
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
        },
      ),
    );
  }

  Widget _editInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool isReadOnly = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: _PC.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (isReadOnly) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Auto-set',
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _editField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _PC.text,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14, color: _PC.text),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: _PC.muted),
            filled: true,
            fillColor: _PC.bg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _PC.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _PC.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _PC.red, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ── Location & Radius ─────────────────────────────────────────────────────
  void _showLocationRadius(BuildContext context) {
    final manualCtrl = TextEditingController(
      text: AppData.volunteerProfile['location'] ?? '',
    );
    double radius = 5.0;
    bool autoDetect = false;
    String detectedLocation = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.80,
            decoration: const BoxDecoration(
              color: _PC.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _PC.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _PC.tealLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.location_on_outlined,
                          color: _PC.teal,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Location & Radius',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _PC.text,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, color: _PC.muted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Auto detection
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _PC.tealLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _PC.teal.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.my_location,
                                color: _PC.teal,
                                size: 22,
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Auto Detect Location',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _PC.teal,
                                      ),
                                    ),
                                    Text(
                                      'Uses GPS for accurate location',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _PC.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: autoDetect,
                                onChanged: (v) async {
                                  setModalState(() => autoDetect = v);
                                  if (v) {
                                    // Simulate GPS detection
                                    await Future.delayed(
                                      const Duration(milliseconds: 800),
                                    );
                                    setModalState(() {
                                      detectedLocation =
                                          'Anna Nagar, Chennai, Tamil Nadu';
                                      manualCtrl.text = detectedLocation;
                                    });
                                  }
                                },
                                activeThumbColor: _PC.teal,
                              ),
                            ],
                          ),
                        ),
                        if (autoDetect && detectedLocation.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _PC.bg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _PC.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_pin,
                                  color: _PC.red,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Detected Location',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _PC.muted,
                                        ),
                                      ),
                                      Text(
                                        detectedLocation,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _PC.text,
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
                                    color: _PC.tealLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'GPS',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _PC.teal,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        // Manual entry
                        const Text(
                          'Manual Entry',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _PC.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: manualCtrl,
                          enabled: !autoDetect,
                          style: const TextStyle(fontSize: 14, color: _PC.text),
                          decoration: InputDecoration(
                            hintText: 'Enter your area, city, state',
                            prefixIcon: const Icon(
                              Icons.edit_location_outlined,
                              size: 18,
                              color: _PC.muted,
                            ),
                            filled: true,
                            fillColor: autoDetect
                                ? const Color(0xFFF0F0F0)
                                : _PC.bg,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _PC.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _PC.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: _PC.teal,
                                width: 1.5,
                              ),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _PC.border),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Radius
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Detection Radius',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _PC.text,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _PC.redLight,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${radius.round()} km',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _PC.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: radius,
                          min: 1,
                          max: 50,
                          divisions: 49,
                          activeColor: _PC.red,
                          inactiveColor: _PC.redLight,
                          onChanged: (v) => setModalState(() => radius = v),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text(
                              '1 km',
                              style: TextStyle(fontSize: 11, color: _PC.muted),
                            ),
                            Text(
                              '50 km',
                              style: TextStyle(fontSize: 11, color: _PC.muted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Radius chips
                        Wrap(
                          spacing: 8,
                          children: [1.0, 5.0, 10.0, 20.0, 50.0].map((r) {
                            return GestureDetector(
                              onTap: () => setModalState(() => radius = r),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: radius == r ? _PC.red : _PC.bg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: radius == r ? _PC.red : _PC.border,
                                  ),
                                ),
                                child: Text(
                                  '${r.round()} km',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: radius == r
                                        ? Colors.white
                                        : _PC.text,
                                    fontWeight: radius == r
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () {
                              AppData.volunteerProfile['location'] = manualCtrl
                                  .text
                                  .trim();
                              AppData.volunteerProfile['radius'] = radius
                                  .round();
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Location set to ${manualCtrl.text.trim()} • Radius: ${radius.round()} km',
                                  ),
                                  backgroundColor: _PC.teal,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _PC.teal,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Save Location',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
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
        },
      ),
    );
  }

  // ── Privacy & Safety ──────────────────────────────────────────────────────
  void _showPrivacySafety(BuildContext context) {
    bool agreedToTerms = false;
    bool locationAccess = false;
    bool profileVisible = true;
    bool missionNotify = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.92,
            decoration: const BoxDecoration(
              color: _PC.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _PC.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _PC.blueLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.privacy_tip_outlined,
                          color: _PC.blue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Privacy & Safety',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: _PC.text,
                              ),
                            ),
                            Text(
                              'Your data, your control',
                              style: TextStyle(fontSize: 12, color: _PC.muted),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, color: _PC.muted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _privacySection(
                          title: 'Data We Collect',
                          icon: Icons.info_outline,
                          color: _PC.gemini,
                          content:
                              'Citizen Hero Network collects your name, contact information, location, and emergency response activity to connect you with nearby emergencies and improve community safety outcomes.',
                        ),
                        const SizedBox(height: 16),
                        _privacySection(
                          title: 'How We Use Your Data',
                          icon: Icons.data_usage,
                          color: _PC.teal,
                          content:
                              'Your data is used to match you with nearby emergency events, calculate your response radius, display your profile to coordinators, and generate aggregated safety statistics. We never sell your personal data.',
                        ),
                        const SizedBox(height: 16),
                        _privacySection(
                          title: 'Location Sharing',
                          icon: Icons.location_on_outlined,
                          color: _PC.amber,
                          content:
                              'Location is only shared with verified emergency coordinators and other volunteers during an active mission. Your location is never shared with third parties.',
                        ),
                        const SizedBox(height: 16),
                        _privacySection(
                          title: 'Data Security',
                          icon: Icons.security,
                          color: _PC.red,
                          content:
                              'All your data is encrypted in transit and at rest using industry-standard AES-256 encryption. Access to your profile data is restricted to authorised personnel only.',
                        ),
                        const SizedBox(height: 16),
                        _privacySection(
                          title: 'Your Rights',
                          icon: Icons.gavel_rounded,
                          color: _PC.blue,
                          content:
                              'You have the right to access, correct, or delete your personal data at any time. You can withdraw consent for data processing by contacting our support team. Withdrawal of consent may limit app functionality.',
                        ),
                        const SizedBox(height: 24),
                        // Toggles
                        _privacyToggle(
                          label: 'Profile Visible to Others',
                          subtitle: 'Other volunteers can see your profile',
                          value: profileVisible,
                          onChanged: (v) =>
                              setModalState(() => profileVisible = v),
                        ),
                        const SizedBox(height: 10),
                        _privacyToggle(
                          label: 'Location Access',
                          subtitle: 'Allow app to access your location',
                          value: locationAccess,
                          onChanged: (v) =>
                              setModalState(() => locationAccess = v),
                        ),
                        const SizedBox(height: 10),
                        _privacyToggle(
                          label: 'Mission Notifications',
                          subtitle: 'Receive nearby emergency alerts',
                          value: missionNotify,
                          onChanged: (v) =>
                              setModalState(() => missionNotify = v),
                        ),
                        const SizedBox(height: 24),
                        // Agree and continue
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: agreedToTerms ? _PC.tealLight : _PC.redLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: agreedToTerms
                                  ? _PC.teal
                                  : _PC.red.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: agreedToTerms,
                                onChanged: (v) => setModalState(
                                  () => agreedToTerms = v ?? false,
                                ),
                                activeColor: _PC.teal,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: Text(
                                    'I agree to allow Citizen Hero Network to access my information as described above, to enable emergency response and community safety features.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _PC.text,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: agreedToTerms
                                ? () {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Privacy settings saved.',
                                        ),
                                        backgroundColor: _PC.teal,
                                      ),
                                    );
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _PC.blue,
                              disabledBackgroundColor: _PC.border,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Agree & Continue',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
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
        },
      ),
    );
  }

  Widget _privacySection({
    required String title,
    required IconData icon,
    required Color color,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(fontSize: 12, color: _PC.text, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _privacyToggle({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _PC.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _PC.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _PC.text,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: _PC.muted),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: _PC.teal,
          ),
        ],
      ),
    );
  }

  // ── Help & Support ────────────────────────────────────────────────────────
  void _showHelpSupport(BuildContext context) {
    const faqs = [
      {
        'q': 'How do I respond to a nearby emergency?',
        'a':
            'Go to the Home tab, find an emergency in "Nearby Emergencies" and tap "Respond". You will be guided with step-by-step AI instructions.',
      },
      {
        'q': 'How is my XP calculated?',
        'a':
            'XP is awarded for completing training tasks, responding to emergencies, and helping coordinate rescues. Each activity displays the XP reward before you start.',
      },
      {
        'q': 'How do I update my skills?',
        'a':
            'Go to Profile → Settings → Edit Profile, then select your skills in the "Required Skills" section.',
      },
      {
        'q': 'Is my location always shared?',
        'a':
            'No. Your location is only shared with coordinators and volunteers during an active emergency mission you have accepted.',
      },
      {
        'q': 'How do I report a false alarm?',
        'a':
            'Open the emergency response, scroll down, and tap "Report as False Alarm". Our coordinators will review and close it.',
      },
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.90,
        decoration: const BoxDecoration(
          color: _PC.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _PC.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _PC.amberLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.help_outline,
                      color: _PC.amber,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Help & Support',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _PC.text,
                          ),
                        ),
                        Text(
                          'FAQs and contact information',
                          style: TextStyle(fontSize: 12, color: _PC.muted),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: _PC.muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Contact cards
                    const Text(
                      'Contact Us',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _PC.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _contactCard(
                      icon: Icons.phone_rounded,
                      color: _PC.teal,
                      bg: _PC.tealLight,
                      title: 'Emergency Helpline',
                      subtitle: '1800-XXX-XXXX (Toll Free)',
                      note: '24/7 Available',
                    ),
                    const SizedBox(height: 10),
                    _contactCard(
                      icon: Icons.support_agent_rounded,
                      color: _PC.blue,
                      bg: _PC.blueLight,
                      title: 'App Support',
                      subtitle: '1800-YYY-YYYY',
                      note: 'Mon–Sat, 9 AM–6 PM',
                    ),
                    const SizedBox(height: 10),
                    _contactCard(
                      icon: Icons.local_police_rounded,
                      color: _PC.amber,
                      bg: _PC.amberLight,
                      title: 'Control Room',
                      subtitle: '1800-ZZZ-ZZZZ',
                      note: 'Authorised personnel line',
                    ),
                    const SizedBox(height: 10),
                    _contactCard(
                      icon: Icons.email_outlined,
                      color: _PC.gemini,
                      bg: _PC.geminiLight,
                      title: 'Email Support',
                      subtitle: 'support@citizenhero.app',
                      note: 'Response within 24 hours',
                    ),
                    const SizedBox(height: 24),
                    // FAQs
                    const Text(
                      'Frequently Asked Questions',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _PC.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...faqs.map((faq) => _faqItem(faq['q']!, faq['a']!)),
                    const SizedBox(height: 20),
                    // App info
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _PC.bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _PC.border),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'About Citizen Hero Network',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _PC.text,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Citizen Hero Network is a community-driven emergency response platform connecting trained volunteers with people in need. Our mission is to build resilient communities capable of rapid first response.\n\nVersion: 1.0.0  •  © 2026 Citizen Hero Network',
                            style: TextStyle(
                              fontSize: 12,
                              color: _PC.muted,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactCard({
    required IconData icon,
    required Color color,
    required Color bg,
    required String title,
    required String subtitle,
    required String note,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _PC.text,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  note,
                  style: const TextStyle(fontSize: 11, color: _PC.muted),
                ),
              ],
            ),
          ),
          Icon(Icons.call_outlined, color: color, size: 20),
        ],
      ),
    );
  }

  Widget _faqItem(String q, String a) {
    return Theme(
      data: ThemeData().copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
        leading: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _PC.redLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.quiz_outlined, color: _PC.red, size: 14),
        ),
        title: Text(
          q,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _PC.text,
          ),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _PC.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              a,
              style: const TextStyle(
                fontSize: 12,
                color: _PC.muted,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────
  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: _PC.red),
            SizedBox(width: 8),
            Text(
              'Sign Out',
              style: TextStyle(fontWeight: FontWeight.w700, color: _PC.red),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to sign out? You will be redirected to the login screen.',
          style: TextStyle(fontSize: 14, color: _PC.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _PC.muted)),
          ),
          ElevatedButton(
            onPressed: () {
              // Clear data
              AppData.volunteerProfile['name'] = '';
              AppData.volunteerProfile['email'] = '';
              AppData.volunteerProfile['initials'] = '';
              AppData.volunteerProfile['username'] = '';
              AppData.loginType = 'volunteer';
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _PC.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _PC.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _PC.text,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  AUTHORISED PERSON PROFILE TAB
// ══════════════════════════════════════════════════════════════════════════════
class AuthorisedPersonProfileTab extends StatefulWidget {
  final Map<String, dynamic> officer;
  const AuthorisedPersonProfileTab({super.key, required this.officer});

  @override
  State<AuthorisedPersonProfileTab> createState() =>
      _AuthorisedPersonProfileTabState();
}

class _AuthorisedPersonProfileTabState
    extends State<AuthorisedPersonProfileTab> {
  Map<String, dynamic> get officer => AppData.authorisedProfile;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Officer Profile',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: _PC.text,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _PC.blueLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _PC.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_user_rounded,
                        size: 12,
                        color: _PC.blue,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        officer['badgeId'] ?? 'AUTH-001',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _PC.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _officerCard(),
            const SizedBox(height: 20),
            _buildStatsRow(),
            const SizedBox(height: 20),
            _buildSettingsSection(context),
          ],
        ),
      ),
    );
  }

  Widget _officerCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _PC.blue,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _PC.blue.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withOpacity(0.2),
                child: Text(
                  officer['initials'] ?? 'OF',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.verified_user_rounded,
                          color: Colors.white70,
                          size: 13,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Authorised Officer',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      officer['name'] ?? 'Officer',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if ((officer['username'] ?? '').isNotEmpty)
                      Text(
                        '@${officer['username']}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11,
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
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFF4ADE80), size: 8),
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
          const SizedBox(height: 16),
          _detail(Icons.badge_outlined, 'Officer ID', officer['id'] ?? '—'),
          const SizedBox(height: 8),
          _detail(Icons.badge_outlined, 'Badge ID', officer['badgeId'] ?? '—'),
          const SizedBox(height: 8),
          _detail(
            Icons.location_city_rounded,
            'Jurisdiction',
            officer['jurisdiction'] ?? 'Chennai District',
          ),
          const SizedBox(height: 8),
          _detail(
            Icons.account_balance_rounded,
            'Department',
            officer['department'] ?? '—',
          ),
          const SizedBox(height: 8),
          _detail(Icons.email_outlined, 'Email', officer['email'] ?? '—'),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 13),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _statCard(
          'Active Incidents',
          '2',
          Icons.warning_rounded,
          _PC.red,
          _PC.redLight,
        ),
        const SizedBox(width: 12),
        _statCard(
          'On-field Today',
          '17',
          Icons.people_rounded,
          _PC.teal,
          _PC.tealLight,
        ),
        const SizedBox(width: 12),
        _statCard(
          'Resolved',
          '5',
          Icons.check_circle_rounded,
          _PC.amber,
          _PC.amberLight,
        ),
      ],
    );
  }

  Widget _statCard(
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
          color: _PC.white,
          borderRadius: BorderRadius.circular(14),
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
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: _PC.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context) {
    final items = [
      {
        'icon': Icons.edit_outlined,
        'label': 'Edit Profile',
        'sub': 'Name, badge, department',
        'onTap': () => _showEditProfile(context),
      },
      {
        'icon': Icons.location_on_outlined,
        'label': 'Location & Radius',
        'sub': 'Jurisdiction area & radius',
        'onTap': () => _showLocationRadius(context),
      },
      {
        'icon': Icons.notifications_outlined,
        'label': 'Alert Preferences',
        'sub': 'Push, SMS, radio',
        'onTap': () {},
      },
      {
        'icon': Icons.security_outlined,
        'label': 'Privacy & Safety',
        'sub': 'Visibility, data controls',
        'onTap': () => _showPrivacySafety(context),
      },
      {
        'icon': Icons.help_outline,
        'label': 'Help & Support',
        'sub': 'FAQs, contact control room',
        'onTap': () => _showHelpSupport(context),
      },
      {
        'icon': Icons.logout,
        'label': 'Sign Out',
        'isRed': true,
        'onTap': () => _confirmSignOut(context),
      },
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _PC.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _PC.text,
            ),
          ),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) {
            final item = e.value;
            final isRed = item['isRed'] == true;
            final isLast = e.key == items.length - 1;
            return Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isRed ? _PC.redLight : _PC.blueLight,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      item['icon'] as IconData,
                      color: isRed ? _PC.red : _PC.blue,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    item['label'] as String,
                    style: TextStyle(
                      fontSize: 14,
                      color: isRed ? _PC.red : _PC.text,
                      fontWeight: isRed ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: item['sub'] != null
                      ? Text(
                          item['sub'] as String,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _PC.muted,
                          ),
                        )
                      : null,
                  trailing: isRed
                      ? null
                      : const Icon(
                          Icons.chevron_right,
                          color: _PC.muted,
                          size: 20,
                        ),
                  onTap: item['onTap'] as VoidCallback?,
                ),
                if (!isLast) Divider(color: Colors.grey.shade100, height: 1),
              ],
            );
          }),
        ],
      ),
    );
  }

  void _showEditProfile(BuildContext context) {
    final nameCtrl = TextEditingController(text: officer['name'] ?? '');
    final contactCtrl = TextEditingController(
      text: officer['contactNumber'] ?? '',
    );
    final deptCtrl = TextEditingController(text: officer['department'] ?? '');
    final jurisdictionCtrl = TextEditingController(
      text: officer['jurisdiction'] ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: _PC.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _PC.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _PC.blueLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      color: _PC.blue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Officer Profile',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _PC.text,
                          ),
                        ),
                        Text(
                          'Update your official profile',
                          style: TextStyle(fontSize: 12, color: _PC.muted),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: _PC.muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Read-only fields
                    _authInfoCard(
                      Icons.alternate_email,
                      'Username',
                      '@${officer['username'] ?? ''}',
                      _PC.gemini,
                    ),
                    const SizedBox(height: 8),
                    _authInfoCard(
                      Icons.email_outlined,
                      'Email (Login)',
                      officer['email'] ?? '',
                      _PC.teal,
                    ),
                    const SizedBox(height: 8),
                    _authInfoCard(
                      Icons.badge_outlined,
                      'Officer ID',
                      officer['id'] ?? '',
                      _PC.blue,
                    ),
                    const SizedBox(height: 20),
                    _authField(nameCtrl, 'Full Name', Icons.person_outline),
                    const SizedBox(height: 14),
                    _authField(
                      contactCtrl,
                      'Contact Number',
                      Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 14),
                    _authField(
                      deptCtrl,
                      'Department',
                      Icons.account_balance_outlined,
                    ),
                    const SizedBox(height: 14),
                    _authField(
                      jurisdictionCtrl,
                      'Jurisdiction',
                      Icons.location_city_rounded,
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          AppData.authorisedProfile['name'] =
                              nameCtrl.text.trim().isNotEmpty
                              ? nameCtrl.text.trim()
                              : officer['name'];
                          AppData.authorisedProfile['contactNumber'] =
                              contactCtrl.text.trim();
                          AppData.authorisedProfile['department'] = deptCtrl
                              .text
                              .trim();
                          AppData.authorisedProfile['jurisdiction'] =
                              jurisdictionCtrl.text.trim();
                          final name =
                              AppData.authorisedProfile['name'] as String;
                          final parts = name.trim().split(' ');
                          AppData.authorisedProfile['initials'] =
                              parts.length >= 2
                              ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
                              : parts.isNotEmpty && parts[0].isNotEmpty
                              ? parts[0][0].toUpperCase()
                              : 'OF';
                          Navigator.pop(context);
                          setState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _PC.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
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
    );
  }

  Widget _authInfoCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: _PC.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Auto-set',
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _authField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
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
            color: _PC.text,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14, color: _PC.text),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: _PC.muted),
            filled: true,
            fillColor: _PC.bg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _PC.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _PC.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _PC.blue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _showLocationRadius(BuildContext context) {
    final manualCtrl = TextEditingController(
      text: AppData.authorisedProfile['location'] ?? '',
    );
    double radius = 10.0;
    bool autoDetect = false;
    String detectedLocation = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.80,
            decoration: const BoxDecoration(
              color: _PC.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _PC.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _PC.blueLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.location_on_outlined,
                          color: _PC.blue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Location & Radius',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _PC.text,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, color: _PC.muted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _PC.blueLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _PC.blue.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.my_location,
                                color: _PC.blue,
                                size: 22,
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Auto Detect Location',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _PC.blue,
                                      ),
                                    ),
                                    Text(
                                      'Uses GPS for accurate location',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _PC.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: autoDetect,
                                onChanged: (v) async {
                                  setModalState(() => autoDetect = v);
                                  if (v) {
                                    await Future.delayed(
                                      const Duration(milliseconds: 800),
                                    );
                                    setModalState(() {
                                      detectedLocation =
                                          'Chennai District, Tamil Nadu';
                                      manualCtrl.text = detectedLocation;
                                    });
                                  }
                                },
                                activeThumbColor: _PC.blue,
                              ),
                            ],
                          ),
                        ),
                        if (autoDetect && detectedLocation.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _PC.bg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _PC.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_pin,
                                  color: _PC.blue,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Detected Location',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _PC.muted,
                                        ),
                                      ),
                                      Text(
                                        detectedLocation,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _PC.text,
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
                                    color: _PC.blueLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'GPS',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _PC.blue,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        const Text(
                          'Manual Entry',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _PC.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: manualCtrl,
                          enabled: !autoDetect,
                          style: const TextStyle(fontSize: 14, color: _PC.text),
                          decoration: InputDecoration(
                            hintText: 'Enter jurisdiction area',
                            prefixIcon: const Icon(
                              Icons.edit_location_outlined,
                              size: 18,
                              color: _PC.muted,
                            ),
                            filled: true,
                            fillColor: autoDetect
                                ? const Color(0xFFF0F0F0)
                                : _PC.bg,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _PC.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _PC.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: _PC.blue,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Jurisdiction Radius',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _PC.text,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _PC.blueLight,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${radius.round()} km',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _PC.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: radius,
                          min: 1,
                          max: 100,
                          divisions: 99,
                          activeColor: _PC.blue,
                          inactiveColor: _PC.blueLight,
                          onChanged: (v) => setModalState(() => radius = v),
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () {
                              AppData.authorisedProfile['location'] = manualCtrl
                                  .text
                                  .trim();
                              AppData.authorisedProfile['radius'] = radius
                                  .round();
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Location set to ${manualCtrl.text.trim()} • Radius: ${radius.round()} km',
                                  ),
                                  backgroundColor: _PC.blue,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _PC.blue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Save Location',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
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
        },
      ),
    );
  }

  void _showPrivacySafety(BuildContext context) {
    bool agreedToTerms = false;
    bool locationAccess = true;
    bool profileVisible = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.90,
            decoration: const BoxDecoration(
              color: _PC.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _PC.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _PC.blueLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.privacy_tip_outlined,
                          color: _PC.blue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Privacy & Safety',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: _PC.text,
                              ),
                            ),
                            Text(
                              'Officer access & data policy',
                              style: TextStyle(fontSize: 12, color: _PC.muted),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, color: _PC.muted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _privacyInfoCard(
                          _PC.blue,
                          Icons.verified_user_rounded,
                          'Authorised Access',
                          'As an authorised person, you have elevated access to emergency data, volunteer locations, and incident reports within your jurisdiction. This access is logged and audited.',
                        ),
                        const SizedBox(height: 14),
                        _privacyInfoCard(
                          _PC.red,
                          Icons.data_usage,
                          'Data Handling',
                          'All data accessed through this account is subject to government data protection policies. Unauthorised sharing or misuse of this data is a punishable offence.',
                        ),
                        const SizedBox(height: 14),
                        _privacyInfoCard(
                          _PC.teal,
                          Icons.security,
                          'Security & Audit',
                          'All your actions are logged for security and audit purposes. Your session and data access events are monitored by the control room.',
                        ),
                        const SizedBox(height: 14),
                        _privacyInfoCard(
                          _PC.amber,
                          Icons.lock_outlined,
                          'Confidentiality',
                          'Volunteer personal data accessed through this platform must be kept strictly confidential and used only for emergency coordination purposes.',
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _PC.bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _PC.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'Location Access',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _PC.text,
                                      ),
                                    ),
                                    Text(
                                      'Allow jurisdiction-wide tracking',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _PC.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: locationAccess,
                                onChanged: (v) =>
                                    setModalState(() => locationAccess = v),
                                activeThumbColor: _PC.blue,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _PC.bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _PC.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'Profile Visibility',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _PC.text,
                                      ),
                                    ),
                                    Text(
                                      'Visible to volunteers in jurisdiction',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _PC.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: profileVisible,
                                onChanged: (v) =>
                                    setModalState(() => profileVisible = v),
                                activeThumbColor: _PC.blue,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: agreedToTerms ? _PC.blueLight : _PC.redLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: agreedToTerms
                                  ? _PC.blue
                                  : _PC.red.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: agreedToTerms,
                                onChanged: (v) => setModalState(
                                  () => agreedToTerms = v ?? false,
                                ),
                                activeColor: _PC.blue,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: Text(
                                    'I acknowledge my responsibilities as an authorised user and agree to the data access policies of Citizen Hero Network. I confirm this information will be used solely for emergency coordination.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _PC.text,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: agreedToTerms
                                ? () {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Privacy settings saved.',
                                        ),
                                        backgroundColor: _PC.blue,
                                      ),
                                    );
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _PC.blue,
                              disabledBackgroundColor: _PC.border,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Agree & Continue',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
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
        },
      ),
    );
  }

  Widget _privacyInfoCard(
    Color color,
    IconData icon,
    String title,
    String content,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(fontSize: 12, color: _PC.text, height: 1.6),
          ),
        ],
      ),
    );
  }

  void _showHelpSupport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
          color: _PC.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _PC.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _PC.amberLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.help_outline,
                      color: _PC.amber,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Help & Support',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _PC.text,
                          ),
                        ),
                        Text(
                          'Officer support and contact lines',
                          style: TextStyle(fontSize: 12, color: _PC.muted),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: _PC.muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Control Room Numbers',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _PC.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _helpContactCard(
                      Icons.local_police_rounded,
                      _PC.blue,
                      _PC.blueLight,
                      'Police Control Room',
                      '1800-AAA-AAAA',
                      '24/7 Emergency',
                    ),
                    const SizedBox(height: 10),
                    _helpContactCard(
                      Icons.local_fire_department_rounded,
                      _PC.red,
                      _PC.redLight,
                      'Fire Department Control',
                      '1800-BBB-BBBB',
                      '24/7 Dispatch',
                    ),
                    const SizedBox(height: 10),
                    _helpContactCard(
                      Icons.medical_services_rounded,
                      _PC.teal,
                      _PC.tealLight,
                      'Medical Emergency',
                      '1800-CCC-CCCC',
                      'Ambulance & Medical',
                    ),
                    const SizedBox(height: 10),
                    _helpContactCard(
                      Icons.support_agent_rounded,
                      _PC.amber,
                      _PC.amberLight,
                      'App Technical Support',
                      '1800-DDD-DDDD',
                      'Mon–Sat, 8 AM–8 PM',
                    ),
                    const SizedBox(height: 10),
                    _helpContactCard(
                      Icons.headset_mic_rounded,
                      _PC.gemini,
                      _PC.geminiLight,
                      'Incident Coordination',
                      '1800-EEE-EEEE',
                      'Active incidents support',
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _PC.bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _PC.border),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'About Citizen Hero Network',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _PC.text,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Citizen Hero Network is an integrated emergency response platform for authorised personnel and trained volunteers. Authorised officers can coordinate responses, manage incidents, and track volunteers within their jurisdiction.\n\nVersion: 1.0.0  •  © 2026 Citizen Hero Network',
                            style: TextStyle(
                              fontSize: 12,
                              color: _PC.muted,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _helpContactCard(
    IconData icon,
    Color color,
    Color bg,
    String title,
    String number,
    String note,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _PC.text,
                  ),
                ),
                Text(
                  number,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  note,
                  style: const TextStyle(fontSize: 11, color: _PC.muted),
                ),
              ],
            ),
          ),
          Icon(Icons.call_outlined, color: color, size: 20),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: _PC.red),
            SizedBox(width: 8),
            Text(
              'Sign Out',
              style: TextStyle(fontWeight: FontWeight.w700, color: _PC.red),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to sign out from your officer account?',
          style: TextStyle(fontSize: 14, color: _PC.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _PC.muted)),
          ),
          ElevatedButton(
            onPressed: () {
              AppData.authorisedProfile['name'] = '';
              AppData.authorisedProfile['email'] = '';
              AppData.authorisedProfile['initials'] = '';
              AppData.authorisedProfile['username'] = '';
              AppData.loginType = 'volunteer';
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _PC.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
