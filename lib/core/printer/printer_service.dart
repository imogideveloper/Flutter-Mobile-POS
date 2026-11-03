import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// Abstraksi printer Bluetooth thermal (tahap 4 bagian D) - dipisah dari
/// implementasi `print_bluetooth_thermal` supaya UI (PengaturanPrinterPage,
/// alur cetak otomatis setelah bayar) bisa ditest dgn Fake tanpa printer
/// sungguhan (tidak ada perangkat Bluetooth di sandbox ini).
abstract class PrinterService {
  Future<bool> izinDiberikan();
  Future<bool> mintaIzin();
  Future<bool> bluetoothAktif();
  Future<List<PerangkatBluetooth>> perangkatTerpasang();
  Future<bool> sambungkan(String macAddress);
  Future<bool> statusTersambung();
  Future<bool> cetakBytes(List<int> bytes);
  Future<void> putuskan();
}

class PerangkatBluetooth {
  const PerangkatBluetooth({required this.nama, required this.macAddress});

  final String nama;
  final String macAddress;
}

class PrintBluetoothThermalService implements PrinterService {
  @override
  Future<bool> izinDiberikan() => PrintBluetoothThermal.isPermissionBluetoothGranted;

  @override
  Future<bool> mintaIzin() async {
    if (!Platform.isAndroid) return izinDiberikan();
    // Android 12+ (API 31+) butuh BLUETOOTH_SCAN+BLUETOOTH_CONNECT runtime -
    // versi lebih lama cukup izin install-time (BLUETOOTH/BLUETOOTH_ADMIN,
    // sudah dideklarasikan di AndroidManifest, tidak perlu minta runtime).
    final hasil = await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    return hasil.values.every((status) => status.isGranted);
  }

  @override
  Future<bool> bluetoothAktif() => PrintBluetoothThermal.bluetoothEnabled;

  @override
  Future<List<PerangkatBluetooth>> perangkatTerpasang() async {
    final daftar = await PrintBluetoothThermal.pairedBluetooths;
    return [for (final d in daftar) PerangkatBluetooth(nama: d.name, macAddress: d.macAdress)];
  }

  @override
  Future<bool> sambungkan(String macAddress) =>
      PrintBluetoothThermal.connect(macPrinterAddress: macAddress);

  @override
  Future<bool> statusTersambung() => PrintBluetoothThermal.connectionStatus;

  @override
  Future<bool> cetakBytes(List<int> bytes) => PrintBluetoothThermal.writeBytes(bytes);

  @override
  Future<void> putuskan() async {
    await PrintBluetoothThermal.disconnect;
  }
}

final printerServiceProvider = Provider<PrinterService>((ref) => PrintBluetoothThermalService());
