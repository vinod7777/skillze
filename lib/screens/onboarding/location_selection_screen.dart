import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class LocationSelectionScreen extends StatefulWidget {
  const LocationSelectionScreen({super.key});

  @override
  State<LocationSelectionScreen> createState() => _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen> {
  bool _isLoading = false;

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition();
        // In a real app, use geocoding to get city name. For demo, we'll store coordinates.
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).update({
            'location': GeoPoint(position.latitude, position.longitude),
            'onboardingCompleted': true,
          });
        }
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/main', (route) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _skipLocation() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'onboardingCompleted': true,
      });
    }
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/main', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2F6A).withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 60,
                  color: Color(0xFF0F2F6A),
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                'Enable Location',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F2F6A),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'To show you skills and people around you, we need access to your location.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF71717A),
                  height: 1.5,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _getCurrentLocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F2F6A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Allow Access',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _skipLocation,
                child: const Text(
                  'Maybe Later',
                  style: TextStyle(
                    color: Color(0xFFA1A1AA),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
