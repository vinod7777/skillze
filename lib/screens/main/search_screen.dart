import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/localization_service.dart';
import '../../services/profanity_filter_service.dart';
import '../../widgets/user_avatar.dart';
import 'user_profile_screen.dart';
import '../../theme/app_theme.dart';
import 'main_navigation.dart';


class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _searchController = TextEditingController();
  final MapController _mapController = MapController();

  bool showMap = true;
  LatLng? _userLocation;
  bool _isLoadingLocation = true;

  // All fetched users (unfiltered, only distance-filtered)
  List<Map<String, dynamic>> _allFetchedUsers = [];
  // Users currently displayed (after search + distance filter)
  List<Map<String, dynamic>> _displayedUsers = [];
  bool _isLoadingUsers = true;
  String _searchQuery = '';
  String? _selectedRole;
  String? _selectedSkill;
  double _rangeKm = 25.0;


  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _initLocation();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    
    // Check for profanity in search query
    if (ProfanityFilterService.hasProfanity(query)) {
      // Quietly ignore or clear search if profane
      setState(() => _displayedUsers = []);
      return;
    }

    if (query == _searchQuery) return;
    setState(() => _searchQuery = query);
    _applySearchFilter();
  }

  void _applySearchFilter() {
    final query = _searchQuery.toLowerCase();
    
    final filtered = _allFetchedUsers.where((user) {
      // 1. Distance Filter (already handled in _fetchNearbyUsers, but re-checking here)
      if (_rangeKm > 0 && (user['distanceKm'] as double) > _rangeKm) return false;

      // 2. Role Filter
      if (_selectedRole != null && _selectedRole != 'All Roles') {
        final userRole = (user['role'] as String? ?? '').toLowerCase();
        if (!userRole.contains(_selectedRole!.toLowerCase())) return false;
      }

      // 3. Skill Filter
      if (_selectedSkill != null && _selectedSkill != 'All Skills') {
        final userSkills = List<String>.from(user['skills'] ?? []);
        if (!userSkills.any((s) => s.toLowerCase() == _selectedSkill!.toLowerCase())) return false;
      }

      // 4. Search Query Filter
      if (query.isNotEmpty) {
        final name = (user['name'] as String? ?? '').toLowerCase();
        final username = (user['username'] as String? ?? '').toLowerCase();
        final role = (user['role'] as String? ?? '').toLowerCase();
        final skills = List<String>.from(user['skills'] ?? []);

        bool matches = name.contains(query) || 
                      username.contains(query) || 
                      role.contains(query) || 
                      skills.any((s) => s.toLowerCase().contains(query));
        if (!matches) return false;
      }

      return true;
    }).toList();

    setState(() => _displayedUsers = filtered);
  }

  Future<void> _initLocation() async {
    try {
      // 1. Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          final shouldOpen = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: context.surfaceColor,
              title: Text(
                'Location Services Disabled',
                style: TextStyle(color: context.textHigh),
              ),
              content: Text(
                'Please enable location services to see nearby developers on the map.',
                style: TextStyle(color: context.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.t('cancel'), style: TextStyle(color: context.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(context.t('open_settings')),
                ),
              ],
            ),
          );
          if (shouldOpen == true) {
            await Geolocator.openLocationSettings();
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) {
              _initLocation();
            }
            return;
          }
        }
        _setFallbackLocation();
        return;
      }

      // 2. Try to get last known position first (fast)
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() {
          _userLocation = LatLng(lastKnown.latitude, lastKnown.longitude);
          _isLoadingLocation = false;
        });
      }

      // 3. Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.t('location_permission_denied'),
                ),
              ),
            );
          }
          _setFallbackLocation();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          final shouldOpen = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
            backgroundColor: context.surfaceColor,
            title: Text(
              'Location Permission Required',
              style: TextStyle(color: context.textHigh),
            ),
              content: Text(
                'Location permission is permanently denied. Please enable it from app settings to discover nearby developers.',
                style: TextStyle(color: context.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.t('cancel'), style: TextStyle(color: context.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(context.t('open_settings')),
                ),
              ],
            ),
          );
          if (shouldOpen == true) {
            await Geolocator.openAppSettings();
          }
        }
        _setFallbackLocation();
        return;
      }

      // 4. Get accurate position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10,
          timeLimit: Duration(seconds: 30),
        ),
      );

      if (mounted) {
        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });
        // Center map to new accurate position if on map
        if (showMap) {
          _mapController.move(_userLocation!, 14.0);
        }
      }

      // 5. Update user's location in Firestore
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      _fetchNearbyUsers();
    } catch (e) {
      debugPrint('Location error: $e');
      _setFallbackLocation();
    }
  }

  void _setFallbackLocation() {
    if (mounted) {
      setState(() {
        _userLocation = const LatLng(17.3850, 78.4867);
        _isLoadingLocation = false;
      });
    }
    _fetchNearbyUsers();
  }

  Future<void> _fetchNearbyUsers() async {
    try {
      // Fetch all users who have registered a location (latitude != 0)
      // Note: In a production app with many users, you would use Geohashing.
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('latitude', isNotEqualTo: 0)
          .get();

      final currentUser = FirebaseAuth.instance.currentUser;
      final List<Map<String, dynamic>> users = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['latitude'] != null && data['longitude'] != null) {
          if (currentUser != null && doc.id == currentUser.uid) continue;

          // Skip users with ghost mode enabled
          if (data['ghostMode'] == true) continue;

          final userLat = (data['latitude'] as num).toDouble();
          final userLng = (data['longitude'] as num).toDouble();
          final userLatLng = LatLng(userLat, userLng);

          double distanceKm = 0;
          if (_userLocation != null) {
            distanceKm = _calculateDistance(
              _userLocation!.latitude,
              _userLocation!.longitude,
              userLat,
              userLng,
            );
          }

          // Filter by range (0 = unlimited)
          if (_rangeKm > 0 && distanceKm > _rangeKm) continue;

          users.add({
            'uid': doc.id,
            'name': data['name'] ?? 'Unknown',
            'username': data['username'] ?? '',
            'role': data['bio'] ?? 'Developer',
            'skills': List<String>.from(data['skills'] ?? []),
            'location': userLatLng,
            'distanceKm': distanceKm,
            'profileImageUrl': data['profileImageUrl'],
          });
        }
      }

      users.sort(
        (a, b) =>
            (a['distanceKm'] as double).compareTo(b['distanceKm'] as double),
      );

      if (mounted) {
        setState(() {
          _allFetchedUsers = users;
          _isLoadingUsers = false;
        });
        _applySearchFilter();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295;
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  void _openDirections(LatLng destination) async {
    final url =
        'https://www.google.com/maps/dir/?api=1'
        '&origin=${_userLocation!.latitude},${_userLocation!.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&travelmode=driving';

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(
        children: [
          // Content (Map or List)
          Positioned.fill(
            child: showMap ? _buildMap() : _buildUserList(),
          ),

          // Top Elevation/Search Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    context.bg,
                    context.bg.withValues(alpha: 0.9),
                    context.bg.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.7, 1.0],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: context.surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded, color: context.primary, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  style: TextStyle(color: context.textHigh, fontSize: 15, fontWeight: FontWeight.w500),
                                    decoration: InputDecoration(
                                      hintText: context.t('discover'),
                                      hintStyle: TextStyle(color: context.textLow, fontSize: 15, fontWeight: FontWeight.w400),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                ),
                              ),
                              if (_searchQuery.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    // _onSearchChanged will be called automatically due to the listener
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: context.textLow.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.close_rounded, size: 14, color: context.textMed),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => setState(() => showMap = !showMap),
                        child: Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            color: context.primary,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: context.primary.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            showMap ? Icons.list_rounded : Icons.map_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildFilterChip(
                          _selectedSkill ?? context.t('skills'), 
                          _selectedSkill != null,
                          onTap: () => _showFilterOptions('Skills', ['All Skills', 'Flutter', 'React Native', 'Node.js', 'Python', 'UI/UX', 'Dart', 'Javascript']),
                        ),
                        _buildFilterChip(
                          _rangeKm == 0 ? context.t('unlimited') : '${_rangeKm.toInt()} km', 
                          _rangeKm < 100 && _rangeKm > 0,
                          onTap: () => _showFilterOptions('Range', ['5 km', '10 km', '25 km', '50 km', '100 km', 'Unlimited']),
                        ),
                        _buildFilterChip(
                          _selectedRole ?? context.t('roles'), 
                          _selectedRole != null,
                          onTap: () => _showFilterOptions('Role', ['All Roles', 'Frontend Dev', 'Backend Dev', 'Full Stack', 'Designer', 'Product Manager']),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // User count badge (visible only on Map)
          if (showMap)
            Positioned(
              bottom: 20,
              left: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_rounded,
                      color: context.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_displayedUsers.length} ${_searchQuery.isNotEmpty ? context.t('matched') : context.t('nearby')}',
                      style: TextStyle(
                        color: context.textHigh,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_isLoadingLocation) {
      return const Center(child: CircularProgressIndicator());
    }
    return SizedBox.expand(
      child: Stack(
        children: [
          Listener(
            onPointerDown: (_) {
              context.findAncestorStateOfType<MainNavigationState>()?.toggleSwipe(false);
            },
            onPointerUp: (_) {
              context.findAncestorStateOfType<MainNavigationState>()?.toggleSwipe(true);
            },
            onPointerCancel: (_) {
              context.findAncestorStateOfType<MainNavigationState>()?.toggleSwipe(true);
            },
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _userLocation ?? const LatLng(17.3850, 78.4867),
                initialZoom: _rangeKm <= 5
                    ? 14.0
                    : (_rangeKm <= 10 ? 12.0 : (_rangeKm <= 25 ? 10.0 : 6.0)),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.feedFlutter',
                ),
                MarkerLayer(
                  markers: [
                    // Current user marker
                    if (_userLocation != null)
                      Marker(
                        point: _userLocation!,
                        width: 70,
                        height: 90,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: context.bg, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.accent.withOpacity(0.5),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                                color: context.accent,
                              ),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.transparent,
                                child: Icon(
                                  Icons.my_location,
                                  color: context.onAccent,
                                  size: 22,
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: context.accent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                context.t('you'),
                                style: TextStyle(
                                  color: context.onAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Filtered nearby user markers (only _displayedUsers)
                    ..._displayedUsers.map((user) {
                      final profileImageUrl = (user['profileImageUrl'] is String)
                          ? user['profileImageUrl'] as String
                          : null;
                      return Marker(
                        point: user['location'] as LatLng,
                        width: 70,
                        height: 90,
                        child: GestureDetector(
                          onTap: () => _showUserBottomSheet(user),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: context.bg,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black45.withValues(alpha: 0.5),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  gradient: LinearGradient(
                                    colors: [
                                      context.primary,
                                      context.primary.withValues(alpha: 0.7),
                                    ],
                                  ),
                                ),
                                child: UserAvatar(
                                  imageUrl: profileImageUrl,
                                  name: user['name'] ?? '?',
                                  radius: 20,
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: context.textHigh.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  (user['name'] as String).split(' ').first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.bg,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
          // User count badge
          Positioned(
            bottom: 20,
            left: 20,
            child: Container(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Icon(
                    Icons.people_rounded,
                    color: context.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_displayedUsers.length} ${_searchQuery.isNotEmpty ? context.t('matched') : context.t('nearby')}',
                    style: TextStyle(
                      color: context.textHigh,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // My location button
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'my_location_btn',
              backgroundColor: context.primary,
              onPressed: () {
                _initLocation();
                ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(
                    content: Text(context.t('relocating')),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: Icon(
                Icons.gps_fixed_rounded,
                color: context.onPrimary,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserBottomSheet(Map<String, dynamic> user) {
    final distance = (user['distanceKm'] as double);
    final distanceStr = distance < 1
        ? '${(distance * 1000).toInt()} m ${context.t('away')}'
        : '${distance.toStringAsFixed(1)} km ${context.t('away')}';
    final skills = List<String>.from(user['skills'] ?? []);

    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.textSecondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [context.primary, context.primary.withValues(alpha: 0.7)],
                      ),
                    ),
                    child: UserAvatar(
                      imageUrl: user['profileImageUrl'],
                      name: user['name'] ?? '?',
                      radius: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['name'] ?? 'User',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textHigh,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@${user['username']}',
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: context.accent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              distanceStr,
                              style: TextStyle(
                                color: context.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (user['role'] != null)
                Text(
                  user['role'],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              if (skills.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: skills.map((skill) {
                    final isMatched = _searchQuery.isNotEmpty &&
                        skill.toLowerCase().contains(_searchQuery);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isMatched
                            ? context.primary.withValues(alpha: 0.2)
                            : context.surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isMatched
                              ? context.primary
                              : context.border,
                        ),
                      ),
                      child: Text(
                        skill,
                        style: TextStyle(
                          color: isMatched
                              ? context.primary
                              : context.textSecondary,
                          fontSize: 12,
                          fontWeight: isMatched ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _openDirections(user['location'] as LatLng);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.primary,
                        foregroundColor: context.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.directions_rounded, size: 18),
                      label: Text(context.t('direction')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(userId: user['uid'] ?? ''),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.primary,
                        side: BorderSide(color: context.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.person_outline_rounded, size: 18),
                      label: Text(context.t('profile')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserList() {
    if (_isLoadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_displayedUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 60, color: context.textSecondary),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty 
                  ? '${context.t('no_users_found')} "$_searchQuery"' 
                  : context.t('no_users_nearby'),
              style: TextStyle(color: context.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 130,
        left: 16,
        right: 16,
        bottom: 100,
      ),
      itemCount: _displayedUsers.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        final user = _displayedUsers[index];
        final distance = user['distanceKm'] as double;
        final distanceStr = distance < 1
            ? '${(distance * 1000).toInt()} m'
            : '${distance.toStringAsFixed(1)} km';
        final skills = List<String>.from(user['skills'] ?? []);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.border),
          ),
          child: InkWell(
            onTap: () => _showUserBottomSheet(user),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        imageUrl: user['profileImageUrl'],
                        name: user['name'] ?? '?',
                        radius: 25,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user['name'] ?? 'Unknown',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: context.textHigh,
                              ),
                            ),
                            Text(
                              '@${user['username']}',
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 14, color: context.accent),
                              const SizedBox(width: 4),
                              Text(
                                distanceStr,
                                style: TextStyle(
                                  color: context.accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user['role'] ?? '',
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (skills.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: skills.take(3).map((skill) {
                           final isMatched = _searchQuery.isNotEmpty &&
                        skill.toLowerCase().contains(_searchQuery);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isMatched ? context.primary.withValues(alpha: 0.1) : context.surfaceColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              skill,
                              style: TextStyle(
                                color: isMatched ? context.primary : context.textSecondary,
                                fontSize: 10,
                                fontWeight: isMatched ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, bool isActive, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? context.primary : context.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? context.primary : context.border,
          ),
          boxShadow: isActive ? [
             BoxShadow(
              color: context.primary.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? context.onPrimary : context.textHigh,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isActive ? context.onPrimary : context.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterOptions(String type, List<String> options) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            String title = '';
            if (type == 'Skills') {
              title = context.t('skills');
            } else if (type == 'Range') {
              title = context.t('range');
            } else if (type == 'Role') {
              title = context.t('roles');
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${context.t('filter')} $title',
                        style: TextStyle(
                          fontSize: 22, 
                          fontWeight: FontWeight.bold,
                          color: context.textHigh,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (type == 'Skills') _selectedSkill = null;
                            if (type == 'Range') _rangeKm = 25.0;
                            if (type == 'Role') _selectedRole = null;
                            _applySearchFilter();
                          });
                          setModalState(() {});
                        },
                        child: Text(
                          context.t('reset'), 
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: options.length,
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) {
                        String option = options[index];
                        bool isSelected = false;
                        
                        if (type == 'Skills') {
                          isSelected = (option == 'All Skills' && _selectedSkill == null) || (_selectedSkill == option);
                        } else if (type == 'Role') {
                          isSelected = (option == 'All Roles' && _selectedRole == null) || (_selectedRole == option);
                        } else if (type == 'Range') {
                          if (option == 'Unlimited') {
                            isSelected = _rangeKm == 0;
                          } else {
                            isSelected = _rangeKm == double.tryParse(option.split(' ')[0]);
                          }
                        }

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (type == 'Skills') {
                                _selectedSkill = option == 'All Skills' ? null : option;
                              } else if (type == 'Role') {
                                _selectedRole = option == 'All Roles' ? null : option;
                              } else if (type == 'Range') {
                                if (option == 'Unlimited') {
                                  _rangeKm = 0;
                                } else {
                                  _rangeKm = double.tryParse(option.split(' ')[0]) ?? 25.0;
                                }
                                _fetchNearbyUsers();
                              }
                              _applySearchFilter();
                            });
                            setModalState(() {});
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: isSelected ? context.primary.withValues(alpha: 0.05) : context.surfaceLightColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? context.primary : context.border,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option == 'Unlimited' ? context.t('unlimited') : option,
                                    style: TextStyle(
                                      color: isSelected ? context.primary : context.textHigh,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check_circle_rounded, color: context.primary),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F2F6A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text(
                        context.t('apply'), 
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
