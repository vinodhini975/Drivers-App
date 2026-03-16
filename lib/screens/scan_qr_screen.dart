import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Driver QR'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        onDetect: (capture) async {
          if (_isProcessing) return;
          _isProcessing = true;

          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isEmpty) { _isProcessing = false; return; }
          
          final String? rawValue = barcodes.first.rawValue;
          if (rawValue == null || !rawValue.contains('|')) { 
            _isProcessing = false; 
            return; 
          }

          // rawValue format: "98800xxxxx|SESS_17123456"
          final parts = rawValue.split('|');
          final String driverId = parts[0];
          final String sessionId = parts[1];

          try {
            final driverRef = FirebaseFirestore.instance.collection('drivers').doc(driverId);
            
            // STEP 3: Activate Driver & Bind to current session
            await driverRef.update({
              'isTrackingEnabled': true,
              'activeSessionId': sessionId, // Locks tracking to this specific QR session
              'approvedByGovt': true,
              'lastApprovedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Driver $driverId approved for this session!'), backgroundColor: Colors.green),
              );
              Navigator.pop(context);
            }
          } catch (e) {
            debugPrint('Activation error: $e');
            if (mounted) setState(() => _isProcessing = false);
          }
        },
      ),
    );
  }
}
