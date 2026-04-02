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
import '../../widgets/post_card.dart';
import '../../widgets/clean_text_field.dart';


class SearchScreen extends StatefulWidget {
  final String? initialSearchQuery;

  const SearchScreen({
    super.key,
    this.initialSearchQuery,
  });

  static final GlobalKey<_SearchScreenState> searchKey = GlobalKey<_SearchScreenState>();

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
  bool _isPostTab = true;
  List<DocumentSnapshot> _allFetchedPosts = [];
  List<DocumentSnapshot> _displayedPosts = [];
  bool _isLoadingPosts = false;
  final Set<String> _availableSkills = {
    'All Skills', 'Flutter', 'React Native', 'Node.js', 'Python', 'UI/UX', 'Photography', 'Marketing', 'Business', 'Fitness', 'Cooking', 'Gardening', 'Music', 'Design', 'Sales', 'Finance',
    'Baking', 'Painting', 'Sketching', 'Fashion Design', 'Public Speaking', 'Yoga', 'Meditation', 'Social Media', 'Content Creation', 'SEO', 'Public Relations', 'Data Science', 'AI'
  };
  final Set<String> _availableRoles = {
    'All Roles', 'Software Engineer', 'Product Designer', 'Marketing Manager', 'Photographer', 'Entrepreneur', 'Fitness Coach', 'Chef', 'Student', 'Accountant', 'Sales Rep', 'Content Creator',
    'Baker', 'Painter', 'Makeup Artist', 'Barber', 'Counselor', 'Architect', 'Social Media Manager', 'Voice Actor', 'Music Producer', 'Financial Analyst', 'Project Manager', 'Lawyer'
  };


  @override
  void initState() {
    super.initState();
    if (widget.initialSearchQuery != null && widget.initialSearchQuery!.isNotEmpty) {
      _searchController.text = widget.initialSearchQuery!;
      _searchQuery = widget.initialSearchQuery!;
      _isPostTab = true; // Hashtags usually lead to post discovery
    }
    _searchController.addListener(_onSearchChanged);
    _initLocation();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void switchToListView() {
    if (mounted) {
      setState(() {
        showMap = false;
        _isPostTab = true; // Default to nearby posts in list view
      });
    }
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
        final bio = (user['bio'] as String? ?? '').toLowerCase();
        final status = (user['status'] as String? ?? '').toLowerCase();
        final role = (user['role'] as String? ?? '').toLowerCase();
        
        final normalizedFilter = _selectedSkill!.toLowerCase().replaceAll('_', ' ');
        // Match in skills array OR anywhere else for flexibility
        bool match = userSkills.any((s) => s.toLowerCase().replaceAll('_', ' ').contains(normalizedFilter)) ||
                     bio.replaceAll('_', ' ').contains(normalizedFilter) ||
                     status.replaceAll('_', ' ').contains(normalizedFilter) ||
                     role.replaceAll('_', ' ').contains(normalizedFilter);
        
        if (!match) return false;
      }

      // 4. Search Query Filter
      if (query.isNotEmpty) {
        final name = (user['name'] as String? ?? '').toLowerCase();
        final username = (user['username'] as String? ?? '').toLowerCase();
        final roleStr = (user['role'] as String? ?? '').toLowerCase();
        final skills = List<String>.from(user['skills'] ?? []);
        final rolesArray = List<String>.from(user['roles'] ?? []);
        final bio = (user['bio'] as String? ?? '').toLowerCase();
        final status = (user['status'] as String? ?? '').toLowerCase();

        final normalizedQuery = query.replaceAll('_', ' ');
        bool matches = name.replaceAll('_', ' ').contains(normalizedQuery) || 
                      username.replaceAll('_', ' ').contains(normalizedQuery) || 
                      roleStr.replaceAll('_', ' ').contains(normalizedQuery) || 
                      status.replaceAll('_', ' ').contains(normalizedQuery) ||
                      bio.replaceAll('_', ' ').contains(normalizedQuery) ||
                      skills.any((s) => s.toLowerCase().replaceAll('_', ' ').contains(normalizedQuery)) ||
                      rolesArray.any((r) => r.toLowerCase().replaceAll('_', ' ').contains(normalizedQuery));
        if (!matches) return false;
      }

      return true;
    }).toList();

    setState(() => _displayedUsers = filtered);

    final filteredPosts = _allFetchedPosts.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final content = (data['content'] as String? ?? '').toLowerCase();
      final authorName = (data['authorName'] as String? ?? '').toLowerCase();
      
      // 1. Tag Filters
      final tags = List<String>.from(data['skills'] ?? [])..addAll(List<String>.from(data['roles'] ?? []));
      if (_selectedSkill != null && _selectedSkill != 'All Skills') {
        if (!tags.any((t) => t.toLowerCase().contains(_selectedSkill!.toLowerCase()))) return false;
      }
      
      if (_selectedRole != null && _selectedRole != 'All Roles') {
        if (!tags.any((t) => t.toLowerCase().contains(_selectedRole!.toLowerCase()))) return false;
      }

      // 2. Search Query
      if (query.isNotEmpty) {
        bool matches = content.contains(query) || 
                       authorName.contains(query) || 
                       tags.any((t) => t.toLowerCase().contains(query));
        if (!matches) return false;
      }
      return true;
    }).toList();

    setState(() => _displayedPosts = filteredPosts);
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
        if (showMap && _userLocation != null) {
          try {
            _mapController.move(_userLocation!, 14.0);
          } catch (e) {
            debugPrint("Map move error: $e");
          }
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
      _fetchNearbyPosts();
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
    _fetchNearbyPosts();
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

          // Accurate distance calculation
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

          // Advanced Jittering for overlapping locations
          LatLng finalPosition = userLatLng;
          int overlaps = 0;
          for (var existing in users) {
            // Check if coordinates are identical or extremely close
            if ((existing['location'].latitude - userLat).abs() < 0.000001 &&
                (existing['location'].longitude - userLng).abs() < 0.000001) {
              overlaps++;
            }
          }

          if (overlaps > 0) {
            // Use a spiral pattern for jittering to keep markers distinct
            // 0.00008 is roughly 8-10 meters, visible at most zoom levels
            final double jitterAmount = 0.00008 * overlaps;
            final double angle = overlaps * (2 * pi / 6); // Spiral distribution
            finalPosition = LatLng(
              userLat + (jitterAmount * sin(angle)),
              userLng + (jitterAmount * cos(angle)),
            );
          }

          // Combine role, status, bio for a more complete searchable role/description
          String userRole = data['role'] ?? data['status'] ?? data['bio'] ?? 'Community Member';
          if (data['roles'] is List) {
            final rolesList = List<String>.from(data['roles']);
            if (rolesList.isNotEmpty && userRole == 'Community Member') {
              userRole = rolesList.first;
            }
          }

          users.add({
            'uid': doc.id,
            'name': data['name'] ?? 'Unknown',
            'username': data['username'] ?? '',
            'role': userRole,
            'status': data['status'] ?? '',
            'bio': data['bio'] ?? data['description'] ?? '',
            'skills': List<String>.from(data['skills'] ?? []),
            'roles': List<String>.from(data['roles'] is List ? data['roles'] : (data['role'] != null ? [data['role']] : [])),
            'location': finalPosition,
            'distanceKm': distanceKm,
            'profileImageUrl': data['profileImageUrl'],
          });

          // Add to available filters
          if (data['skills'] is List) {
            _availableSkills.addAll(List<String>.from(data['skills']));
          }
          if (data['roles'] is List) {
            _availableRoles.addAll(List<String>.from(data['roles']));
          }
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

  Future<void> _fetchNearbyPosts() async {
    if (_userLocation == null) return;
    setState(() => _isLoadingPosts = true);
    
    try {
      // Use a more robust check for existence of coordinates
      // Latitude is always between -90 and 90, so isGreaterThan: -91 is a safe way to find all numbers
      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('latitude', isGreaterThan: -91)
          .get();

      final List<Map<String, dynamic>> postsWithDistance = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['latitude'] == null || data['longitude'] == null) continue;
        
        final postLat = (data['latitude'] as num).toDouble();
        final postLng = (data['longitude'] as num).toDouble();

        double distanceKm = _calculateDistance(
          _userLocation!.latitude,
          _userLocation!.longitude,
          postLat,
          postLng,
        );

        // Standard filter by range
        if (_rangeKm > 0 && distanceKm > _rangeKm) continue;
        
        postsWithDistance.add({
          'doc': doc,
          'distanceKm': distanceKm,
        });

        // Add to available filters
        if (data['skills'] is List) {
          _availableSkills.addAll(List<String>.from(data['skills']));
        }
        if (data['roles'] is List) {
          _availableRoles.addAll(List<String>.from(data['roles']));
        }
      }

      // Sort by distance (closest first)
      postsWithDistance.sort((a, b) => (a['distanceKm'] as double).compareTo(b['distanceKm'] as double));

      if (mounted) {
        setState(() {
          _allFetchedPosts = postsWithDistance.map((p) => p['doc'] as DocumentSnapshot).toList();
          _isLoadingPosts = false;
        });
        _applySearchFilter();
      }
    } catch (e) {
      debugPrint('Error fetching nearby posts: $e');
      if (mounted) setState(() => _isLoadingPosts = false);
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
            child: showMap 
                ? _buildMap() 
                : (_isPostTab ? _buildPostList() : _buildUserList()),
          ),

          // Top Elevation/Search Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                bottom: 4,
              ),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          if (Navigator.canPop(context))
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: Icon(Icons.arrow_back_rounded, color: context.textHigh),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ),
                          Expanded(
                            child: CleanTextField(
                                controller: _searchController,
                                hintText: 'Search skills, roles, or users...',
                                prefixIcon: Icons.search_rounded,
                                suffixIcon: _searchQuery.isNotEmpty ? Icons.close_rounded : null,
                                onSuffixTap: () => _searchController.clear(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => setState(() => showMap = !showMap),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: context.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                showMap ? Icons.view_list_rounded : Icons.map_rounded,
                                color: context.primary,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ),
                  const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                 _buildFilterChip(
                                  _selectedSkill ?? context.t('skills'), 
                                  _selectedSkill != null,
                                  icon: Icons.auto_awesome_rounded,
                                  onTap: () => _showFilterOptions('Skills', _availableSkills.toList()),
                                ),
                                _buildFilterChip(
                                  _rangeKm == 0 ? context.t('unlimited') : '${_rangeKm.toInt()} km', 
                                  _rangeKm < 100 && _rangeKm > 0,
                                  onTap: () => _showFilterOptions('Range', ['5 km', '10 km', '25 km', '50 km', '100 km', 'Unlimited']),
                                ),
                                _buildFilterChip(
                                  _selectedRole ?? context.t('roles'), 
                                  _selectedRole != null,
                                  onTap: () => _showFilterOptions('Role', _availableRoles.toList()),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!showMap) ...[
                          _buildToggleSlider(),
                        ],
                      ],
                    ),
                  ),
                ),

          // User count badge (visible only on Map)
          if (showMap)
            Positioned(
              bottom: 25,
              left: 20,
              child: GestureDetector(
                onTap: () => setState(() => showMap = false),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [context.surfaceColor, context.surfaceColor.withOpacity(0.95)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.primary.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 15,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: context.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.format_list_bulleted_rounded,
                          color: context.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_displayedUsers.length} ${_searchQuery.isNotEmpty ? context.t('matched') : (_rangeKm > 25.0 || _rangeKm == 0 ? context.t('in_range') : context.t('nearby'))}',
                            style: TextStyle(
                              color: context.textHigh,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                             context.t('view list'),
                            style: TextStyle(
                              color: context.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
                                boxShadow: [
                                  BoxShadow(
                                    color: context.accent.withOpacity(0.5),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                                color: context.isDark ? Colors.black : const Color(0xFF0F2F6A),
                                border: context.isDark ? Border.all(color: Colors.white, width: 2) : null,
                              ),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.transparent,
                                child: const Icon(
                                  Icons.my_location,
                                  color: Colors.white,
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
                                color: context.isDark ? Colors.black : const Color(0xFF0F2F6A),
                                borderRadius: BorderRadius.circular(8),
                                border: context.isDark ? Border.all(color: Colors.white, width: 0.5) : null,
                              ),
                              child: Text(
                                context.t('you'),
                                style: const TextStyle(
                                  color: Colors.white,
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
                                  boxShadow: [
                                    BoxShadow(
                                      color: context.isDark ? Colors.white24 : Colors.black26,
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  color: context.isDark ? Colors.black : const Color(0xFF0F2F6A),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
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
                                  color: context.textHigh.withOpacity(0.7),
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
      isScrollControlled: true,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Container(
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
              GestureDetector(
                onTap: () {
                  Navigator.pop(context); // Close bottom sheet
                  Navigator.push(
                    this.context, // Use screen context
                    MaterialPageRoute(
                      builder: (context) => UserProfileScreen(userId: user['uid']),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [context.primary, context.primary.withOpacity(0.7)],
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
                            ? context.primary.withOpacity(0.2)
                            : context.surfaceColor,
                        borderRadius: BorderRadius.circular(8),
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
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.directions_rounded, size: 18),
                      label: Text(context.t('direction')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(userId: user['uid'] ?? ''),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.primary.withOpacity(0.1),
                        foregroundColor: context.primary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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
        ),);
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
    return RefreshIndicator(
      onRefresh: _fetchNearbyUsers,
      displacement: MediaQuery.of(context).padding.top + 100,
      color: context.primary,
      backgroundColor: context.surfaceColor,
      child: ListView.builder(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 215,
          bottom: 120,
        ),
        itemCount: _displayedUsers.length,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        itemBuilder: (context, index) {
          final user = _displayedUsers[index];
          final distance = user['distanceKm'] as double;
          final distanceStr = distance < 1
              ? '${(distance * 1000).toInt()} m'
              : '${distance.toStringAsFixed(1)} km';

          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserProfileScreen(userId: user['uid'] ?? '')),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  UserAvatar(
                    imageUrl: user['profileImageUrl'],
                    name: user['name'] ?? '?',
                    radius: 28,
                  ),
                  const SizedBox(width: 14),
                  // User Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '@${user['username']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.textHigh,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                distanceStr,
                                style: TextStyle(
                                  color: context.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          user['name'] ?? '',
                          style: TextStyle(
                            color: context.textMed,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (user['role'] != null && user['role'].toString().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            user['role'],
                            style: TextStyle(
                              color: context.primary.withOpacity(0.8),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // View Button
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => UserProfileScreen(userId: user['uid'] ?? '')),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        side: BorderSide(color: context.border, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'View',
                        style: TextStyle(
                          color: context.textHigh,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: Icon(Icons.more_vert, color: context.textHigh, size: 20),
                    onPressed: () => _showUserOptions(user),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostList() {
    if (_isLoadingPosts) {
      return Center(child: CircularProgressIndicator(color: context.primary));
    }
    if (_displayedPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.post_add_rounded, size: 60, color: context.textSecondary),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty 
                  ? 'No posts found with "$_searchQuery"' 
                  : 'No posts found ${_rangeKm > 25.0 || _rangeKm == 0 ? context.t('in_range') : context.t('nearby')}',
              style: TextStyle(color: context.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchNearbyPosts,
      displacement: MediaQuery.of(context).padding.top + 100,
      color: context.primary,
      backgroundColor: context.surfaceColor,
      child: ListView.builder(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 215,
          bottom: 120,
        ),
        itemCount: _displayedPosts.length,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        itemBuilder: (context, index) {
          return PostCard(doc: _displayedPosts[index], isClickable: true);
        },
      ),
    );
  }

  Widget _buildToggleSlider() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      height: 44,
      decoration: BoxDecoration(
        color: context.surfaceLightColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.fastOutSlowIn,
            alignment: _isPostTab ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: context.primary,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(color: context.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isPostTab = false),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: !_isPostTab ? context.onPrimary : context.textMed,
                        fontWeight: !_isPostTab ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                      child: const Text('Nearby People'),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isPostTab = true),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: _isPostTab ? context.onPrimary : context.textMed,
                        fontWeight: _isPostTab ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                      child: const Text('Nearby Posts'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showUserOptions(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceLightColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.isDark ? Colors.white10 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.share_outlined, color: context.textHigh),
            title: Text('Share this profile', style: TextStyle(color: context.textHigh)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.report_problem_outlined, color: Colors.redAccent),
            title: const Text('Report', style: TextStyle(color: Colors.redAccent)),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isActive, {IconData? icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? context.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? context.primary : context.border.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isActive ? context.primary : context.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isActive ? context.primary : context.textHigh,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isActive ? context.primary : context.textSecondary,
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
        String filterSearchQuery = '';
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

            final normalizedSearch = filterSearchQuery.toLowerCase().replaceAll('_', ' ');
            final filteredOptions = options.where((opt) {
              final normalizedOpt = opt.toLowerCase().replaceAll('_', ' ');
              return normalizedOpt.contains(normalizedSearch);
            }).toList();
            
            // Allow adding any search query as a custom option
            bool showAddCustom = type != 'Range' && 
                                filterSearchQuery.isNotEmpty && 
                                !options.any((opt) => opt.toLowerCase().replaceAll('_', ' ') == filterSearchQuery.toLowerCase().replaceAll('_', ' '));
            
            if (showAddCustom) {
               // Put it at the top so it's easy to select
               filteredOptions.insert(0, filterSearchQuery);
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: context.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
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
                          setModalState(() {
                             filterSearchQuery = '';
                          });
                        },
                        child: Text(
                          context.t('reset'), 
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (type != 'Range') ...[
                    const SizedBox(height: 16),
                    CleanTextField(
                      hintText: 'Search $title...',
                      prefixIcon: Icons.search_rounded,
                      onChanged: (val) {
                        setModalState(() {
                          filterSearchQuery = val.trim();
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredOptions.length,
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) {
                        String option = filteredOptions[index];
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
                                _fetchNearbyPosts();
                              }
                              _applySearchFilter();
                            });
                            setModalState(() {});
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: isSelected ? context.primary.withOpacity(0.1) : context.surfaceLightColor,
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected ? Border.all(color: context.primary.withOpacity(0.3)) : null,
                            ),
                            child: Row(
                              children: [
                                if (showAddCustom && index == 0 && option == filterSearchQuery)
                                   Padding(
                                     padding: const EdgeInsets.only(right: 12),
                                     child: Icon(Icons.add_circle_outline_rounded, color: context.primary, size: 20),
                                   ),
                                Expanded(
                                  child: Text(
                                    option == 'Unlimited' ? context.t('View full map') : option,
                                    style: TextStyle(
                                      color: isSelected ? context.primary : (showAddCustom && index == 0 && option == filterSearchQuery ? context.primary : context.textHigh),
                                      fontWeight: isSelected || (showAddCustom && index == 0 && option == filterSearchQuery) ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (showAddCustom && index == 0 && option == filterSearchQuery)
                                   Text(
                                     'Custom',
                                     style: TextStyle(
                                       color: context.textLow,
                                       fontSize: 12,
                                       fontWeight: FontWeight.normal,
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
                        backgroundColor: context.primary,
                        foregroundColor: context.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
