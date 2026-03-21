import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_profile_screen.dart';
import '../../widgets/user_avatar.dart';

class ConnectionsListScreen extends StatefulWidget {
  const ConnectionsListScreen({super.key});

  @override
  State<ConnectionsListScreen> createState() => _ConnectionsListScreenState();
}

class _ConnectionsListScreenState extends State<ConnectionsListScreen> {
  List<Map<String, dynamic>> _connections = [];
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};

      // Fetch connections (following list)
      List followingList = userData['followingList'] ?? [];
      List<Map<String, dynamic>> connections = [];
      for (String uid in followingList) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (doc.exists) {
          connections.add({'uid': uid, ...doc.data()!});
        }
      }

      // Fetch pending connection requests
      final requestsSnapshot = await FirebaseFirestore.instance
          .collection('connection_requests')
          .where('toUserId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      List<Map<String, dynamic>> requests = [];
      for (var reqDoc in requestsSnapshot.docs) {
        final reqData = reqDoc.data();
        final fromUserDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(reqData['fromUserId'])
            .get();
        if (fromUserDoc.exists) {
          requests.add({
            'requestId': reqDoc.id,
            'fromUserId': reqData['fromUserId'],
            ...fromUserDoc.data()!,
          });
        }
      }

      if (mounted) {
        setState(() {
          _connections = connections;
          _requests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptRequest(Map<String, dynamic> request) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final fromUserId = request['fromUserId'];
      final requestId = request['requestId'];

      // Update request status
      await FirebaseFirestore.instance
          .collection('connection_requests')
          .doc(requestId)
          .update({'status': 'accepted'});

      // Add to both users' following lists
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {
          'followingList': FieldValue.arrayUnion([fromUserId]),
        },
      );
      await FirebaseFirestore.instance
          .collection('users')
          .doc(fromUserId)
          .update({
            'followingList': FieldValue.arrayUnion([user.uid]),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected with ${request['name'] ?? 'user'}'),
          ),
        );
      }
      _fetchData(); // Refresh
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _declineRequest(Map<String, dynamic> request) async {
    try {
      await FirebaseFirestore.instance
          .collection('connection_requests')
          .doc(request['requestId'])
          .update({'status': 'declined'});

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request declined')));
      }
      _fetchData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _unfollowUser(String uid, String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Unfollow',
          style: TextStyle(color: const Color(0xFF18181B)),
        ),
        content: Text(
          'Are you sure you want to unfollow $name?',
          style: TextStyle(color: const Color(0xFF71717A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Unfollow'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'followingList': FieldValue.arrayRemove([uid]),
            });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Unfollowed $name')));
        }
        _fetchData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FB),
        appBar: AppBar(
          title: Text('My Network'),
          bottom: TabBar(
            dividerColor: const Color(0xFFE4E4E7),
            indicatorColor: const Color(0xFF0F2F6A),
            labelColor: const Color(0xFF0F2F6A),
            unselectedLabelColor: const Color(0xFF71717A),
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            tabs: [
              Tab(text: 'Connections'),
              Tab(text: 'Requests'),
            ],
          ),
        ),
        body: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: Color(0xFF0F2F6A)),
                  )
                : TabBarView(
                    children: [_buildConnectionsTab(), _buildRequestsTab()],
                  ),
      ),
    );
  }

  Widget _buildConnectionsTab() {
    if (_connections.isEmpty) {
      return Center(
        child: Text(
          'No connections yet.\nStart following people!',
          textAlign: TextAlign.center,
          style: TextStyle(color: const Color(0xFF71717A)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      physics: const BouncingScrollPhysics(),
      itemCount: _connections.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final conn = _connections[index];
        final name = conn['name'] ?? 'Unknown';
        final bio = conn['bio'] ?? 'Developer';
        final uid = conn['uid'] ?? '';

        return Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE4E4E7))),  
          padding: const EdgeInsets.all(16),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(userId: uid),
                  ),
                );
              },
              child: UserAvatar(
                imageUrl: conn['profileImageUrl'],
                name: name,
                radius: 25,
              ),
            ),
            title: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(userId: uid),
                  ),
                );
              },
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF18181B),
                  fontSize: 16,
                ),
              ),
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 4.0),
              child: Text(
                bio,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFF71717A),
                  fontSize: 13,
                ),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.person_remove_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    onPressed: () => _unfollowUser(uid, name),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRequestsTab() {
    if (_requests.isEmpty) {
      return Center(
        child: Text(
          'No pending requests.',
          style: TextStyle(color: const Color(0xFF71717A)),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(24),
      physics: BouncingScrollPhysics(),
      itemCount: _requests.length,
      separatorBuilder: (context, index) => SizedBox(height: 16),
      itemBuilder: (context, index) {
        final req = _requests[index];
        final name = req['name'] ?? 'Unknown';
        final bio = req['bio'] ?? 'Developer';

        return Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE4E4E7))),  
          padding: EdgeInsets.all(16),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: UserAvatar(
              imageUrl: req['profileImageUrl'],
              name: name,
              radius: 25,
            ),
            title: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF18181B),
                fontSize: 16,
              ),
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 4.0),
              child: Text(
                bio,
                style: TextStyle(
                  color: const Color(0xFF71717A),
                  fontSize: 13,
                ),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.check_rounded,
                      color: Colors.green,
                      size: 20,
                    ),
                    onPressed: () => _acceptRequest(req),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.red,
                      size: 20,
                    ),
                    onPressed: () => _declineRequest(req),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


