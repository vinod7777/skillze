import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import '../../theme/app_theme.dart';
import '../../services/localization_service.dart';
import '../../widgets/user_avatar.dart';

class AboutAccountScreen extends StatelessWidget {
  final String userId;

  const AboutAccountScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Text(
          context.t('about_this_account'),
          style: TextStyle(fontWeight: FontWeight.bold, color: context.textHigh),
        ),
        backgroundColor: context.bg,
        foregroundColor: context.textHigh,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: context.primary));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text(context.t('user_not_found'), style: TextStyle(color: context.textHigh)));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final String name = userData['name'] ?? 'Unknown';
          final String username = userData['username'] ?? '';
          final Timestamp? createdAt = userData['createdAt'] as Timestamp?;
          final String profileImageUrl = userData['profileImageUrl'] ?? '';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                UserAvatar(
                  imageUrl: profileImageUrl,
                  name: name,
                  radius: 50,
                  fontSize: 32,
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: context.textHigh,
                  ),
                ),
                Text(
                  '@$username',
                  style: TextStyle(
                    fontSize: 16,
                    color: context.textMed,
                  ),
                ),
                const SizedBox(height: 40),
                _buildInfoItem(
                  context,
                  Icons.calendar_today_outlined,
                  context.t('date_joined'),
                  createdAt != null 
                    ? DateFormat('MMMM yyyy').format(createdAt.toDate())
                    : context.t('unknown'),
                ),
                const Divider(height: 32),
                FutureBuilder<String>(
                  future: _getLocationText(context, userData),
                  builder: (context, locSnap) {
                    return _buildInfoItem(
                      context,
                      Icons.location_on_outlined,
                      context.t('account_based_in'),
                      locSnap.data ?? context.t('loading'),
                    );
                  }
                ),
                const Divider(height: 32),
                _buildInfoItem(
                  context,
                  Icons.verified_user_outlined,
                  context.t('account_transparency'),
                  context.t('account_transparency_desc'),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.surfaceLightColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.border),
                  ),
                  child: Text(
                    context.t('about_account_privacy_notice'),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textMed,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<String> _getLocationText(BuildContext context, Map<String, dynamic> userData) async {
    dynamic location = userData['location'];
    double? lat;
    double? lon;

    if (location is GeoPoint) {
      lat = location.latitude;
      lon = location.longitude;
    } else if (userData['latitude'] != null && userData['longitude'] != null) {
      lat = (userData['latitude'] as num).toDouble();
      lon = (userData['longitude'] as num).toDouble();
    }

    if (lat == null || lon == null) {
      return location is String ? location : context.t('not_specified');
    }

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        List<String> parts = [];
        
        // Exact location pieces
        if (p.subLocality != null && p.subLocality!.isNotEmpty) {
          parts.add(p.subLocality!);
        } else if (p.name != null && p.name!.isNotEmpty) {
          parts.add(p.name!);
        }
        
        if (p.locality != null && p.locality!.isNotEmpty) {
          parts.add(p.locality!);
        }
        
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) {
          parts.add(p.administrativeArea!);
        }
        
        if (p.country != null && p.country!.isNotEmpty) {
          parts.add(p.country!);
        }
        
        if (parts.isNotEmpty) {
          return parts.toSet().join(", "); // Use Set to avoid duplicates like "New York, New York"
        }
      }
      return "${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}";
    } catch (e) {
      return "${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}";
    }
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String title, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: context.primary, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textHigh,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: context.textMed,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

