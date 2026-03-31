import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../theme/app_theme.dart';
import '../../widgets/clean_text_field.dart';

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;

  const LocationPickerScreen({super.key, this.initialLocation});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  LatLng? _selectedLocation;
  String _selectedLocationName = 'Selecting...';
  bool _isLoading = false;
  List<dynamic> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation ?? const LatLng(17.3850, 78.4867); // Default to Hyderabad if none
    if (widget.initialLocation != null) {
      _reverseGeocode(widget.initialLocation!);
    } else {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _selectedLocation = latLng;
      });
      _mapController.move(latLng, 15);
      _reverseGeocode(latLng);
    } catch (e) {
      // Fallback
    }
  }

  Future<void> _reverseGeocode(LatLng location) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(() {
          _selectedLocationName = '${place.name != null && place.name!.isNotEmpty ? '${place.name}, ' : ''}${place.locality ?? ''}${place.locality != null && (place.administrativeArea != null) ? ', ' : ''}${place.administrativeArea ?? ''}';
          if (_selectedLocationName.startsWith(', ')) _selectedLocationName = _selectedLocationName.substring(2);
          if (_selectedLocationName.isEmpty) _selectedLocationName = 'Unknown Location';
        });
      }
    } catch (e) {
      setState(() => _selectedLocationName = 'Coordinates: ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}');
    }
  }

  Future<void> _searchLocation(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isLoading = true);
      try {
        final response = await http.get(
          Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=10'),
          headers: {
            'User-Agent': 'SkillzeApp_Flutter_Picker/1.0',
            'Accept-Language': 'en',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (mounted) {
            setState(() {
              _suggestions = data is List ? data : [];
            });
          }
        }
      } catch (e) {
        debugPrint('Search error: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    });
  }

  void _onSuggestionTap(dynamic suggestion) {
    final lat = double.parse(suggestion['lat'].toString());
    final lon = double.parse(suggestion['lon'].toString());
    final displayAddress = suggestion['display_name'].toString();

    setState(() {
      _selectedLocation = LatLng(lat, lon);
      _selectedLocationName = displayAddress;
      _suggestions = [];
      _searchController.clear();
      FocusScope.of(context).unfocus();
    });
    
    _mapController.move(_selectedLocation!, 15);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Pick Location',
          style: TextStyle(
            color: context.textHigh,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, {
                'name': _selectedLocationName,
                'lat': _selectedLocation?.latitude,
                'lng': _selectedLocation?.longitude,
              });
            },
            child: Text(
              'Confirm',
              style: TextStyle(
                color: context.primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // MAP
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation ?? const LatLng(17.3850, 78.4867),
              initialZoom: 15.0,
              onTap: (tapPosition, latLng) {
                setState(() {
                  _selectedLocation = latLng;
                });
                _reverseGeocode(latLng);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.feedFlutter',
              ),
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      width: 50,
                      height: 50,
                      child: Icon(
                        Icons.location_on_rounded,
                        color: Colors.black, // Dark contrast on light map
                        size: 44,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // SEARCH OVERLAY
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                CleanTextField(
                  controller: _searchController,
                  hintText: 'Search for a place...',
                  prefixIcon: Icons.search_rounded,
                  onChanged: _searchLocation,
                  suffixIcon: _isLoading ? null : (_searchController.text.isNotEmpty ? Icons.close_rounded : null),
                  onSuffixTap: () {
                    _searchController.clear();
                    setState(() => _suggestions = []);
                  },
                  // Add custom widget for loading if needed, but for now we'll use the suffix logic
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                if (_suggestions.isNotEmpty)
                  Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    color: context.surfaceColor,
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: context.border.withOpacity(0.2)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: context.border.withOpacity(0.1),
                        ),
                        itemBuilder: (context, index) {
                          final suggestion = _suggestions[index];
                          final displayName = suggestion['display_name'].toString();
                          
                          return ListTile(
                            leading: Icon(Icons.location_on_outlined, color: context.primary, size: 20),
                            title: Text(
                              displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: context.textHigh, fontSize: 13),
                            ),
                            onTap: () => _onSuggestionTap(suggestion),
                          );
                        },
                      ),
                    ),
                  )
                else if (_searchController.text.length > 2 && !_isLoading)
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: context.textLow),
                          const SizedBox(width: 8),
                          Text('No results found', style: TextStyle(color: context.textMed, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // BOTTOM INFO
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.location_pin, color: context.primary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selected Location',
                          style: TextStyle(
                            color: context.textLow,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedLocationName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textHigh,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
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
    );
  }
}
