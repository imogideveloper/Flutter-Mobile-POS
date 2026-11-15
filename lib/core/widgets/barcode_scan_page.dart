import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/platform_perangkat.dart';

/// Pindai barcode dan kembalikan nilainya (null bila dibatalkan).
/// Android/iOS: buka kamera ([BarcodeScanPage]). Desktop (Windows, tanpa
/// dukungan kamera di `mobile_scanner`): dialog ketik/scan - pemindai USB
/// atau Bluetooth terbaca sebagai keyboard sehingga cukup diarahkan ke kolom.
Future<String?> pindaiBarcode(BuildContext context) {
  if (adaKameraPemindai) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const BarcodeScanPage()),
    );
  }
  return showDialog<String>(context: context, builder: (context) => const _DialogBarcodeManual());
}

class _DialogBarcodeManual extends StatefulWidget {
  const _DialogBarcodeManual();

  @override
  State<_DialogBarcodeManual> createState() => _DialogBarcodeManualState();
}

class _DialogBarcodeManualState extends State<_DialogBarcodeManual> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selesai() {
    final nilai = _controller.text.trim();
    Navigator.of(context).pop(nilai.isEmpty ? null : nilai);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('barcodeManual.dialog'),
      title: const Text('Barcode'),
      content: TextField(
        key: const Key('barcodeManual.input'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Ketik atau scan dengan pemindai',
          helperText: 'Kamera tidak tersedia di perangkat ini.',
        ),
        onSubmitted: (_) => _selesai(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
        FilledButton(key: const Key('barcodeManual.ok'), onPressed: _selesai, child: const Text('OK')),
      ],
    );
  }
}

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
