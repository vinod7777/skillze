import 'package:flutter/material.dart';
import '../services/call_service.dart';
import '../screens/main/call_screen.dart';

class FloatingCallWidget extends StatefulWidget {
  const FloatingCallWidget({super.key});

  @override
  State<FloatingCallWidget> createState() => _FloatingCallWidgetState();
}

class _FloatingCallWidgetState extends State<FloatingCallWidget> {
  final CallService _callService = CallService();
  Offset _offset = const Offset(20, 100);

  @override
  Widget build(BuildContext context) {
    if (_callService.callState != CallState.connected && _callService.callState != CallState.connecting) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _offset += details.delta;
          });
        },
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CallScreen(isIncoming: false)),
          );
        },
        child: Material(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          color: Colors.green,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Ongoing Call',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
