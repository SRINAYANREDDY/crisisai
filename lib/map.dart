// map.dart — Real Google Maps with LIVE user location + directions + AI features
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:math' as math;
import 'train.dart' show GeminiService;
import 'disaster_forecast_screen.dart';
import 'home_screen.dart' show AppColors;

// ─── Map Colors ───────────────────────────────────────────────────────────────
class _MC {
  static const Color primary = Color(0xFFB45309);
  static const Color danger = Color(0xFFDC2626);
  static const Color safe = Color(0xFF16A34A);
  static const Color blue = Color(0xFF1D4ED8);
  static const Color warning = Color(0xFFD97706);
  static const Color bg = Color(0xFFF7F5F0);
  static const Color text = Color(0xFF1C1917);
  static const Color muted = Color(0xFF78716C);
}

// ─── Data Models ──────────────────────────────────────────────────────────────
class EmergencyIncident {
  final String id;
  final String title;
  final String description;
  final String type;
  final LatLng location;
  final DateTime reportedAt;
  final int respondersNeeded;
  final int respondersCount;
  final String area;

  const EmergencyIncident({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.location,
    required this.reportedAt,
    required this.respondersNeeded,
    required this.respondersCount,
    required this.area,
  });
}

class NearbyVolunteer {
  final String id;
  final String name;
  final List<String> skills;
  final bool isAvailable;

  const NearbyVolunteer({
    required this.id,
    required this.name,
    required this.skills,
    required this.isAvailable,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
//  MAP SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // ── Google Maps controller ──────────────────────────────────────────────
  final Completer<GoogleMapController> _mapController = Completer();

  // Default fallback only if GPS fails completely
  static const LatLng _fallbackCentre = LatLng(
    20.5937,
    78.9629,
  ); // India centre

  // ── User location ────────────────────────────────────────────────────────
  Position? _userPosition;
  String _userAddress = 'Getting location...';
  bool _locationLoading = true;
  String? _locationError;

  // ── Incidents — generated relative to live location ──────────────────────
  List<EmergencyIncident> _incidents = [];

  final List<NearbyVolunteer> _volunteers = [
    NearbyVolunteer(
      id: 'v1',
      name: 'Arun K.',
      skills: ['CPR', 'First Aid'],
      isAvailable: true,
    ),
    NearbyVolunteer(
      id: 'v2',
      name: 'Meena R.',
      skills: ['Fire Safety'],
      isAvailable: true,
    ),
    NearbyVolunteer(
      id: 'v3',
      name: 'Karthik S.',
      skills: ['CPR'],
      isAvailable: false,
    ),
    NearbyVolunteer(
      id: 'v4',
      name: 'Priya L.',
      skills: ['First Aid'],
      isAvailable: true,
    ),
    NearbyVolunteer(
      id: 'v5',
      name: 'Vijay T.',
      skills: ['Flood Response'],
      isAvailable: false,
    ),
    NearbyVolunteer(
      id: 'v6',
      name: 'Divya M.',
      skills: ['First Aid', 'CPR'],
      isAvailable: true,
    ),
    NearbyVolunteer(
      id: 'v7',
      name: 'Rahul P.',
      skills: ['Fire Safety'],
      isAvailable: false,
    ),
  ];

  // ── State ──────────────────────────────────────────────────────────────────
  EmergencyIncident? _selectedIncident;
  String _activeFilter = 'All';
  bool _showVolunteers = true;
  bool _showVolunteerList = false;
  Set<Marker> _markers = {};

  Map<String, List<NearbyVolunteer>> _aiRecommendedVolunteers = {};
  Map<String, String> _aiPredictedTimes = {};
  String? _aiFilterExplanation;
  bool _loadingAIRecommendations = false;

  final List<String> _filters = ['All', 'Medical', 'Fire', 'Flood', 'Accident'];

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  // ── Generate incidents offset from user's real lat/lng ───────────────────
  List<EmergencyIncident> _generateIncidents(double lat, double lng) {
    // Small offsets (~0.5–5 km) so they appear near the user's real location
    return [
      EmergencyIncident(
        id: '1',
        title: 'Cardiac Arrest Reported',
        description:
            'Person collapsed near the main road. CPR-trained volunteer needed immediately.',
        type: 'Medical',
        location: LatLng(lat + 0.007, lng + 0.010),
        reportedAt: DateTime.now().subtract(const Duration(minutes: 3)),
        respondersNeeded: 3,
        respondersCount: 1,
        area: '~0.8 km away',
      ),
      EmergencyIncident(
        id: '2',
        title: 'Building Fire',
        description:
            'Small fire reported at top floor apartment. Fire brigade en route.',
        type: 'Fire',
        location: LatLng(lat - 0.018, lng - 0.034),
        reportedAt: DateTime.now().subtract(const Duration(minutes: 11)),
        respondersNeeded: 5,
        respondersCount: 4,
        area: '~2.1 km away',
      ),
      EmergencyIncident(
        id: '3',
        title: 'Road Accident',
        description: 'Two-vehicle collision. First aid required for injured.',
        type: 'Accident',
        location: LatLng(lat - 0.040, lng - 0.015),
        reportedAt: DateTime.now().subtract(const Duration(minutes: 42)),
        respondersNeeded: 3,
        respondersCount: 3,
        area: '~4.3 km away',
      ),
      EmergencyIncident(
        id: '4',
        title: 'Flash Flood Warning',
        description:
            'Low-lying streets flooding. Evacuation assistance needed.',
        type: 'Flood',
        location: LatLng(lat + 0.032, lng + 0.020),
        reportedAt: DateTime.now().subtract(const Duration(minutes: 22)),
        respondersNeeded: 6,
        respondersCount: 2,
        area: '~3.5 km away',
      ),
    ];
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'Location services are disabled. Please enable GPS.';
          _locationLoading = false;
          _incidents = _generateIncidents(
            _fallbackCentre.latitude,
            _fallbackCentre.longitude,
          );
        });
        _buildMarkers();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() {
          _locationError = 'Location permission denied.';
          _locationLoading = false;
          _incidents = _generateIncidents(
            _fallbackCentre.latitude,
            _fallbackCentre.longitude,
          );
        });
        _buildMarkers();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Reverse-geocode to get a human-readable address
      String address = 'Your location';
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ].where((s) => s != null && s.isNotEmpty).toList();
          if (parts.isNotEmpty) address = parts.join(', ');
        }
      } catch (_) {
        // Geocoding failed — just show coordinates
        address =
            '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      }

      setState(() {
        _userPosition = pos;
        _userAddress = address;
        _locationLoading = false;
        _incidents = _generateIncidents(pos.latitude, pos.longitude);
      });

      // Move camera to user's REAL location
      final controller = await _mapController.future;
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 14.0),
      );
    } catch (e) {
      setState(() {
        _locationError = 'Could not get location: $e';
        _locationLoading = false;
        _incidents = _generateIncidents(
          _fallbackCentre.latitude,
          _fallbackCentre.longitude,
        );
      });
    }
    _buildMarkers();
  }

  void _buildMarkers() {
    final markers = <Marker>{};

    for (final incident in _filteredIncidents) {
      markers.add(
        Marker(
          markerId: MarkerId(incident.id),
          position: incident.location,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _incidentHue(incident.type),
          ),
          infoWindow: InfoWindow(title: incident.title, snippet: incident.area),
          onTap: () => _selectIncident(incident),
        ),
      );
    }

    setState(() => _markers = markers);
    _fetchAIRecommendations();
  }

  Future<void> _fetchAIRecommendations() async {
    setState(() => _loadingAIRecommendations = true);
    final Map<String, List<NearbyVolunteer>> recommended = {};
    final Map<String, String> times = {};

    for (final incident in _filteredIncidents) {
      final skillMap = {
        'Medical': ['CPR', 'First Aid', 'Medical'],
        'Fire': ['Fire Safety', 'Rescue'],
        'Flood': ['Flood Response', 'Rescue'],
        'Accident': ['First Aid', 'CPR'],
      };
      final needed = skillMap[incident.type] ?? [];
      final matched = _volunteers
          .where(
            (v) => v.isAvailable && v.skills.any((s) => needed.contains(s)),
          )
          .toList();
      recommended[incident.id] = matched.isNotEmpty
          ? matched
          : _volunteers.where((v) => v.isAvailable).toList();

      final count = recommended[incident.id]!.length;
      if (incident.respondersCount >= incident.respondersNeeded) {
        times[incident.id] = 'Covered ✓';
      } else if (count >= 2) {
        times[incident.id] = '~${3 + (incident.id.hashCode % 5)} min';
      } else {
        times[incident.id] = '~${8 + (incident.id.hashCode % 7)} min';
      }
    }

    if (mounted) {
      setState(() {
        _aiRecommendedVolunteers = recommended;
        _aiPredictedTimes = times;
        _loadingAIRecommendations = false;
      });
    }
  }

  Future<void> _fetchAIFilterExplanation(String filter) async {
    if (filter == 'All') {
      setState(() => _aiFilterExplanation = null);
      return;
    }
    final count = _incidents.where((i) => i.type == filter).length;
    final prompt =
        'There are $count $filter incidents in the area. In one concise sentence, '
        'explain what volunteers with $filter response skills should prioritise right now.';
    final result = await GeminiService.generateContent(prompt, 'basic');
    if (mounted) setState(() => _aiFilterExplanation = result);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  List<EmergencyIncident> get _filteredIncidents => _activeFilter == 'All'
      ? _incidents
      : _incidents.where((i) => i.type == _activeFilter).toList();

  double _incidentHue(String type) {
    switch (type) {
      case 'Medical':
        return BitmapDescriptor.hueGreen;
      case 'Fire':
        return BitmapDescriptor.hueRed;
      case 'Flood':
        return BitmapDescriptor.hueBlue;
      case 'Accident':
        return BitmapDescriptor.hueOrange;
      default:
        return BitmapDescriptor.hueViolet;
    }
  }

  Color _incidentColor(String type) {
    switch (type) {
      case 'Medical':
        return _MC.safe;
      case 'Fire':
        return _MC.danger;
      case 'Flood':
        return _MC.blue;
      case 'Accident':
        return _MC.warning;
      default:
        return _MC.muted;
    }
  }

  IconData _incidentIcon(String type) {
    switch (type) {
      case 'Medical':
        return Icons.medical_services_rounded;
      case 'Fire':
        return Icons.local_fire_department_rounded;
      case 'Flood':
        return Icons.water_rounded;
      case 'Accident':
        return Icons.car_crash_rounded;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }

  void _selectIncident(EmergencyIncident incident) async {
    setState(() {
      _selectedIncident = incident;
      _showVolunteerList = false;
    });
    final controller = await _mapController.future;
    controller.animateCamera(
      CameraUpdate.newLatLngZoom(incident.location, 15.0),
    );
  }

  void _dismissSheet() => setState(() => _selectedIncident = null);

  void _setFilter(String f) {
    setState(() => _activeFilter = f);
    _buildMarkers();
    _fetchAIFilterExplanation(f);
    if (_selectedIncident != null &&
        f != 'All' &&
        _selectedIncident!.type != f) {
      _dismissSheet();
    }
  }

  Future<void> _openDirections(EmergencyIncident incident) async {
    final lat = incident.location.latitude;
    final lng = incident.location.longitude;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    }
  }

  void _respondToIncident(EmergencyIncident incident) {
    _dismissSheet();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Responding to: ${incident.title}'),
        backgroundColor: _incidentColor(incident.type),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _goToMyLocation() async {
    if (_userPosition == null) return;
    final controller = await _mapController.future;
    controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(_userPosition!.latitude, _userPosition!.longitude),
        15.0,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Use live position if available, otherwise fallback
    final initialTarget = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : _fallbackCentre;

    return Scaffold(
      backgroundColor: _MC.bg,
      body: Stack(
        children: [
          // ── Google Map centred on LIVE location ─────────────────────────
          GoogleMap(
            onMapCreated: (controller) {
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
              _buildMarkers();
              // If we already have location by the time map is created, move now
              if (_userPosition != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(_userPosition!.latitude, _userPosition!.longitude),
                    14.0,
                  ),
                );
              }
            },
            initialCameraPosition: CameraPosition(
              target: initialTarget,
              zoom: 14.0,
            ),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
            onTap: (_) {
              if (_selectedIncident != null) _dismissSheet();
              if (_showVolunteerList)
                setState(() => _showVolunteerList = false);
            },
          ),

          // ── Location loading overlay ─────────────────────────────────────
          if (_locationLoading)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Getting your live location...',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Location address chip (shows after location resolved) ────────
          if (!_locationLoading &&
              _locationError == null &&
              _userPosition != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.my_location_rounded,
                        size: 13,
                        color: _MC.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _userAddress,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _MC.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Location error ───────────────────────────────────────────────
          if (_locationError != null && !_locationLoading)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCEBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _MC.danger.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_off, color: _MC.danger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _locationError!,
                        style: const TextStyle(fontSize: 12, color: _MC.danger),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _locationError = null;
                          _locationLoading = true;
                        });
                        _initLocation();
                      },
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          fontSize: 12,
                          color: _MC.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Top bar ──────────────────────────────────────────────────────
          SafeArea(child: _buildTopBar()),

          // ── Filter bar ───────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 0,
            right: 0,
            child: Column(
              children: [
                _buildFilterBar(),
                if (_aiFilterExplanation != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF4285F4).withOpacity(0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 13,
                          color: Color(0xFF4285F4),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _aiFilterExplanation!,
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

          // ── Map controls ─────────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: _selectedIncident != null ? 290 : 110,
            child: _buildMapControls(),
          ),

          // ── Legend ───────────────────────────────────────────────────────
          Positioned(
            left: 16,
            bottom: _selectedIncident != null ? 290 : 110,
            child: _buildLegend(),
          ),

          // ── Incident pill ─────────────────────────────────────────────────
          if (!_showVolunteerList)
            Positioned(
              bottom: _selectedIncident != null ? 272 : 94,
              left: 0,
              right: 0,
              child: Center(child: _buildIncidentPill()),
            ),

          // ── Volunteer pill ────────────────────────────────────────────────
          if (_showVolunteers &&
              !_showVolunteerList &&
              _selectedIncident == null)
            Positioned(
              bottom: 138,
              left: 0,
              right: 0,
              child: Center(child: _buildVolunteerPill()),
            ),

          // ── Volunteer list sheet ──────────────────────────────────────────
          if (_showVolunteerList)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildVolunteerSheet(),
            ),

          // ── Incident detail sheet ─────────────────────────────────────────
          if (_selectedIncident != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildIncidentDetailSheet(),
            ),
        ],
      ),
    );
  }

  // ── Top Bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.search_rounded, color: _MC.muted, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search areas or incidents...',
                  hintStyle: TextStyle(color: _MC.muted, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: TextStyle(color: _MC.text, fontSize: 14),
              ),
            ),
            Container(width: 1, height: 24, color: const Color(0xFFE5E5E5)),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => setState(() => _showVolunteers = !_showVolunteers),
              child: Icon(
                Icons.layers_rounded,
                color: _showVolunteers ? _MC.primary : _MC.muted,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () =>
                  setState(() => _showVolunteerList = !_showVolunteerList),
              child: Icon(
                Icons.people_rounded,
                color: _showVolunteerList ? _MC.primary : _MC.muted,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Feature 4 — 48-Hour Forecast button
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DisasterForecastScreen(),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D4ED8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.radar_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      '48H',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  // ── Filter Bar ─────────────────────────────────────────────────────────────
  Widget _buildFilterBar() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = _filters[i];
          final sel = _activeFilter == f;
          return GestureDetector(
            onTap: () => _setFilter(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? _MC.primary : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                f,
                style: TextStyle(
                  color: sel ? Colors.white : _MC.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Map Controls ───────────────────────────────────────────────────────────
  Widget _buildMapControls() {
    return Column(
      children: [
        _mapFab(Icons.my_location_rounded, 'My location', _goToMyLocation),
        const SizedBox(height: 10),
        _mapFab(Icons.add_rounded, 'Zoom in', () async {
          final c = await _mapController.future;
          c.animateCamera(CameraUpdate.zoomIn());
        }),
        const SizedBox(height: 10),
        _mapFab(Icons.remove_rounded, 'Zoom out', () async {
          final c = await _mapController.future;
          c.animateCamera(CameraUpdate.zoomOut());
        }),
      ],
    );
  }

  Widget _mapFab(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: _MC.text, size: 20),
        ),
      ),
    );
  }

  // ── Legend ─────────────────────────────────────────────────────────────────
  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendItem(Colors.blue, 'You'),
          const SizedBox(height: 5),
          _legendItem(_MC.safe, 'Medical'),
          const SizedBox(height: 5),
          _legendItem(_MC.danger, 'Fire'),
          const SizedBox(height: 5),
          _legendItem(_MC.warning, 'Accident'),
          const SizedBox(height: 5),
          _legendItem(_MC.blue, 'Flood'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10, color: _MC.text)),
      ],
    );
  }

  // ── Incident Pill ──────────────────────────────────────────────────────────
  Widget _buildIncidentPill() {
    final count = _filteredIncidents.length;
    return GestureDetector(
      onTap: () {
        if (_filteredIncidents.isNotEmpty) {
          _selectIncident(_filteredIncidents.first);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFDC2626),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count incident${count == 1 ? '' : 's'} near you',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _MC.text,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 16,
              color: _MC.muted,
            ),
          ],
        ),
      ),
    );
  }

  // ── Volunteer Pill ─────────────────────────────────────────────────────────
  Widget _buildVolunteerPill() {
    final available = _volunteers.where((v) => v.isAvailable).length;
    return GestureDetector(
      onTap: () => setState(() => _showVolunteerList = true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: _MC.safe,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _MC.safe.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_rounded, size: 15, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              '$available volunteers available',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Volunteer Sheet ────────────────────────────────────────────────────────
  Widget _buildVolunteerSheet() {
    return Container(
      height: 340,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _sheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Nearby Volunteers',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _MC.text,
                  ),
                ),
                Text(
                  '${_volunteers.where((v) => v.isAvailable).length} available',
                  style: const TextStyle(fontSize: 12, color: _MC.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _volunteers.length,
              itemBuilder: (_, i) => _buildVolunteerTile(_volunteers[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolunteerTile(NearbyVolunteer v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: v.isAvailable
            ? _MC.safe.withOpacity(0.05)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: v.isAvailable
              ? _MC.safe.withOpacity(0.25)
              : const Color(0xFFE5E5E5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: v.isAvailable ? _MC.safe : _MC.muted,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _MC.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  v.skills.join(' • '),
                  style: const TextStyle(fontSize: 11, color: _MC.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: v.isAvailable
                  ? _MC.safe.withOpacity(0.15)
                  : const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              v.isAvailable ? 'Available' : 'Busy',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: v.isAvailable ? _MC.safe : _MC.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Incident Detail Sheet ──────────────────────────────────────────────────
  Widget _buildIncidentDetailSheet() {
    final incident = _selectedIncident!;
    final color = _incidentColor(incident.type);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type badge + time
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _incidentIcon(incident.type),
                            size: 13,
                            color: color,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            incident.type,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _timeAgo(incident.reportedAt),
                      style: const TextStyle(fontSize: 11, color: _MC.muted),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _dismissSheet,
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: _MC.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  incident.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _MC.text,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 13,
                      color: _MC.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      incident.area,
                      style: const TextStyle(fontSize: 12, color: _MC.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // AI predicted time + recommended volunteers
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF4285F4).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: Color(0xFF4285F4),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'AI Predicted Response: ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4285F4),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _aiPredictedTimes[incident.id] ?? 'Calculating...',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _MC.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (_loadingAIRecommendations)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Color(0xFF4285F4),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if ((_aiRecommendedVolunteers[incident.id]?.isNotEmpty ??
                    false)) ...[
                  const Text(
                    'AI-Recommended Responders',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _MC.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _aiRecommendedVolunteers[incident.id]!
                          .take(4)
                          .map(
                            (v) => Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _MC.safe.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _MC.safe.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: _MC.safe,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.person,
                                      color: Colors.white,
                                      size: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    v.name,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _MC.text,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  incident.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _MC.muted,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                // Responders progress
                Row(
                  children: [
                    const Icon(
                      Icons.people_rounded,
                      size: 14,
                      color: _MC.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${incident.respondersCount}/${incident.respondersNeeded} responders',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _MC.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: incident.respondersNeeded > 0
                              ? incident.respondersCount /
                                    incident.respondersNeeded
                              : 0,
                          backgroundColor: const Color(0xFFF0EDE8),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openDirections(incident),
                        icon: const Icon(Icons.directions_rounded, size: 16),
                        label: const Text('Directions'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _MC.text,
                          side: const BorderSide(color: Color(0xFFE5E5E5)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => _respondToIncident(incident),
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('Respond Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 11),
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
        ],
      ),
    );
  }

  Widget _sheetHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E5E5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
