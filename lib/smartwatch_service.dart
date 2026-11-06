import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class SmartwatchService {
  SmartwatchService._();

  static final SmartwatchService instance = SmartwatchService._();

  final StreamController<int> _heartRateController =
      StreamController<int>.broadcast();

  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<int>>? _measurementSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<int> get heartRate => _heartRateController.stream;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  Future<void> startScan() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt >= 31) {
      final permissions = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      if (permissions.values.any((status) => !status.isGranted)) {
        throw StateError(
          'Permita o acesso ao Bluetooth nas configurações do Android.',
        );
      }
    } else {
      final locationPermission = await Permission.locationWhenInUse.request();
      if (!locationPermission.isGranted) {
        throw StateError(
          'Permita o acesso à localização para procurar dispositivos Bluetooth.',
        );
      }
    }

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
  }

  Future<void> connect(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    await device.connect(timeout: const Duration(seconds: 15));

    final services = await device.discoverServices();
    final heartRateService = services.where(
      (service) => service.serviceUuid == Guid('180D'),
    );
    if (heartRateService.isEmpty) {
      await device.disconnect();
      throw StateError(
        'Este dispositivo não disponibiliza o serviço padrão de frequência cardíaca.',
      );
    }

    final characteristics = heartRateService.first.characteristics.where(
      (characteristic) => characteristic.characteristicUuid == Guid('2A37'),
    );
    if (characteristics.isEmpty) {
      await device.disconnect();
      throw StateError('Não foi encontrado o sensor de frequência cardíaca.');
    }

    final measurement = characteristics.first;
    await measurement.setNotifyValue(true);
    await _measurementSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _connectedDevice = device;
    _measurementSubscription = measurement.onValueReceived.listen((value) {
      if (value.isEmpty) return;
      final is16Bit = (value[0] & 0x01) == 1;
      if (value.length < (is16Bit ? 3 : 2)) return;
      final bpm = is16Bit ? value[1] | (value[2] << 8) : value[1];
      if (bpm > 0) _heartRateController.add(bpm);
    });
    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected &&
          _connectedDevice == device) {
        _connectedDevice = null;
        _heartRateController.add(0);
        _measurementSubscription?.cancel();
        _measurementSubscription = null;
      }
    });
  }

  Future<void> disconnect() async {
    await _measurementSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _measurementSubscription = null;
    _connectionSubscription = null;
    final device = _connectedDevice;
    _connectedDevice = null;
    if (device != null) await device.disconnect();
    _heartRateController.add(0);
  }
}
