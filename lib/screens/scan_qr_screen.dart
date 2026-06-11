import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  bool _isProcessing = false;
  MobileScannerController cameraController = MobileScannerController();
  bool _isFlashOn = false;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  Future<void> _handleQrDetected(String rawValue) async {
    if (_isProcessing) return;
    _isProcessing = true;

    // Haptic feedback for discovery
    HapticFeedback.mediumImpact();

    if (!rawValue.contains('|')) {
      _showError('Invalid QR Code Format');
      _isProcessing = false;
      return;
    }

    final parts = rawValue.split('|');
    if (parts.length < 2) {
      _showError('Incomplete QR Metadata');
      _isProcessing = false;
      return;
    }

    final String driverId = parts[0].trim();
    final String sessionId = parts[1].trim();

    try {
      final driverDoc = await FirebaseFirestore.instance.collection('drivers').doc(driverId).get();
      
      if (!driverDoc.exists) {
        _showError('Driver record not found in system');
        _isProcessing = false;
        return;
      }

      final driverData = driverDoc.data()!;
      final String driverName = driverData['name'] ?? 'Unknown Driver';
      final String vehicleId = driverData['vehicleId'] ?? 'No Vehicle';

      if (!mounted) return;

      _showApprovalSheet(driverId, sessionId, driverName, vehicleId);

    } catch (e) {
      _showError('System error: $e');
      _isProcessing = false;
    }
  }

  void _showApprovalSheet(String driverId, String sessionId, String name, String vehicle) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Text('Approve Duty Start', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF1A237E), child: Icon(Icons.person, color: Colors.white)),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('ID: $driverId'),
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.local_shipping, color: Colors.white)),
              title: Text(vehicle, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Assigned Vehicle'),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _isProcessing = false);
                    },
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _finalApproval(driverId, sessionId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Confirm Start'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _finalApproval(String driverId, String sessionId) async {
    Navigator.pop(context);
    
    try {
      await FirebaseFirestore.instance.collection('drivers').doc(driverId).update({
        'isTrackingEnabled': true,
        'activeSessionId': sessionId,
        'approvedByGovt': true,
        'lastApprovedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      HapticFeedback.lightImpact();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Duty Started Successfully!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } catch (e) {
      _showError('Approval failed: $e');
      setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: cameraController,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? code = barcodes.first.rawValue;
                if (code != null) _handleQrDetected(code);
              }
            },
          ),
          
          _buildScannerOverlay(),

          Positioned(
            top: 50,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black45,
              child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ),
          ),

          Positioned(
            top: 50,
            right: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black45,
              child: IconButton(
                icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off, color: Colors.yellow),
                onPressed: () {
                  cameraController.toggleTorch();
                  setState(() => _isFlashOn = !_isFlashOn);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return Stack(
      children: [
        // Simple semi-transparent overlay
        Container(color: Colors.black.withOpacity(0.4)),
        
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Cutout area (just a frame here, simpler than ColorFiltered complex cutout)
              Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    _cornerLabel(Alignment.topLeft),
                    _cornerLabel(Alignment.topRight),
                    _cornerLabel(Alignment.bottomLeft),
                    _cornerLabel(Alignment.bottomRight),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
                child: const Text('ALIGN QR WITHIN FRAME', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13, color: Colors.black)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cornerLabel(Alignment align) {
    return Align(
      alignment: align,
      child: Container(width: 40, height: 40, decoration: BoxDecoration(
        border: Border(
          top: align == Alignment.topLeft || align == Alignment.topRight ? const BorderSide(color: Colors.blue, width: 5) : BorderSide.none,
          bottom: align == Alignment.bottomLeft || align == Alignment.bottomRight ? const BorderSide(color: Colors.blue, width: 5) : BorderSide.none,
          left: align == Alignment.topLeft || align == Alignment.bottomLeft ? const BorderSide(color: Colors.blue, width: 5) : BorderSide.none,
          right: align == Alignment.topRight || align == Alignment.bottomRight ? const BorderSide(color: Colors.blue, width: 5) : BorderSide.none,
        ),
      )),
    );
  }
}
