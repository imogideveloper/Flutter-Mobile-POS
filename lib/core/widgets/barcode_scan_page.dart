import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Halaman scan barcode generik - pop dengan nilai barcode begitu terbaca.
/// Dipakai dari field barcode di form produk; scanner Bluetooth tetap bisa
/// dipakai langsung di TextField manapun karena terbaca sebagai keyboard,
/// halaman ini khusus untuk scan pakai kamera HP.
class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});

  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  bool _sudahDapat = false;

  void _onDetect(BarcodeCapture capture) {
    if (_sudahDapat) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    _sudahDapat = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan barcode')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}

extension on List<Barcode> {
  Barcode? get firstOrNull => isEmpty ? null : first;
}
