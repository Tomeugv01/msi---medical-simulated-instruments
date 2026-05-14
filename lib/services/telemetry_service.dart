import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class TelemetryService extends ChangeNotifier {
  static final TelemetryService _instance = TelemetryService._internal();
  factory TelemetryService() => _instance;
  TelemetryService._internal();

  final FlutterReactiveBle _ble = FlutterReactiveBle();

  final Uuid serviceUuid = Uuid.parse("0000ffe0-0000-1000-8000-00805f9b34fb");
  final Uuid characteristicUuid =
      Uuid.parse("0000ffe1-0000-1000-8000-00805f9b34fb");
  final String monitorNamePrefix = 'MSI-MONITOR';

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;

  final List<DiscoveredDevice> _discoveredDevices = [];
  String? _connectedDeviceId;
  bool _isSearching = false;
  bool _isReady = false;
  bool _isSending = false; // prevent overlapping sends

  List<DiscoveredDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);
  bool get isSearching => _isSearching;
  bool get isConnected => _connectedDeviceId != null;
  String? get connectedDeviceId => _connectedDeviceId;

  Future<bool> requestPermissions() async {
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();

    return permissions[Permission.bluetoothScan]!.isGranted &&
        permissions[Permission.bluetoothConnect]!.isGranted &&
        permissions[Permission.location]!.isGranted;
  }

  Future<void> startSearch() async {
    if (_isSearching) return;
    if (!await requestPermissions()) {
      debugPrint('❌ Missing BLE permissions – cannot scan');
      return;
    }

    _isSearching = true;
    _discoveredDevices.clear();
    notifyListeners();
    debugPrint('🔍 Searching for devices...');

    _scanSubscription?.cancel();
    _scanSubscription = _ble.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (device.name.contains(monitorNamePrefix) ||
          device.serviceUuids.contains(serviceUuid)) {
        final index = _discoveredDevices.indexWhere((d) => d.id == device.id);
        if (index == -1) {
          _discoveredDevices.add(device);
          debugPrint('✅ Discovered: ${device.name} (${device.id})');
          notifyListeners();
        }
      }
    }, onError: (e) {
      debugPrint('❌ Scan error: $e');
      _isSearching = false;
      notifyListeners();
    });
  }

  void stopSearch() {
    _scanSubscription?.cancel();
    _isSearching = false;
    notifyListeners();
  }

  void connectToMonitor(String deviceId) async {
    debugPrint("🔌 Connecting to $deviceId...");
    stopSearch();
    _isReady = false;

    if (!await requestPermissions()) {
      debugPrint("❌ Cannot connect – missing permissions");
      return;
    }

    await _connectionSubscription?.cancel();
    await Future.delayed(const Duration(milliseconds: 300));

    _connectionSubscription = _ble
        .connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 20),
    )
        .listen((state) async {
      debugPrint("📡 Connection state: ${state.connectionState}");
      if (state.connectionState == DeviceConnectionState.connected) {
        _connectedDeviceId = deviceId;
        notifyListeners();
        debugPrint("✅ Connected to Monitor!");

        debugPrint("⏳ Waiting 2 seconds for bonding...");
        await Future.delayed(const Duration(seconds: 2));

        try {
          final services = await _ble.discoverServices(deviceId);
          debugPrint("📋 Discovered ${services.length} services");
          final mtu = await _ble.requestMtu(deviceId: deviceId, mtu: 512);
          debugPrint("📏 MTU: $mtu");

          _isReady = true;
          debugPrint("✅ Monitor ready for writes");
        } catch (e) {
          debugPrint("⚠️ Discovery/MTU error: $e");
          _connectedDeviceId = null;
          _isReady = false;
          notifyListeners();
        }
      } else if (state.connectionState == DeviceConnectionState.disconnected) {
        debugPrint("❌ Disconnected from Monitor");
        _connectedDeviceId = null;
        _isReady = false;
        notifyListeners();
      }
    }, onError: (error) {
      debugPrint("❌ Connection error: $error");
      _connectedDeviceId = null;
      _isReady = false;
      notifyListeners();
    });
  }

  Future<void> stop() async {
    stopSearch();
    await _connectionSubscription?.cancel();
    _connectedDeviceId = null;
    _isReady = false;
    debugPrint("TelemetryService stopped");
    notifyListeners();
  }

  Future<void> updateMonitor(List<Map<String, dynamic>> instruments) async {
    if (_connectedDeviceId == null || !_isReady || _isSending) {
      debugPrint(
          "⚠️ Not connected or not ready or already sending – cannot send data");
      return;
    }

    _isSending = true;
    try {
      final String jsonPayload = json.encode(instruments);
      final List<int> bytes = utf8.encode(jsonPayload);
      debugPrint("📤 Total payload size: ${bytes.length} bytes");

      final characteristic = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: characteristicUuid,
        deviceId: _connectedDeviceId!,
      );

      // Split into safe chunks (480 bytes)
      const int chunkSize = 480;
      for (int i = 0; i < bytes.length; i += chunkSize) {
        final end =
            (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = bytes.sublist(i, end);
        debugPrint(
            "📤 Sending chunk ${(i ~/ chunkSize) + 1}: ${chunk.length} bytes");
        await _ble.writeCharacteristicWithResponse(characteristic,
            value: chunk);
        await Future.delayed(const Duration(milliseconds: 60)); // small delay
      }
      debugPrint("✅ All chunks sent successfully");
    } catch (e) {
      debugPrint("❌ Write error: $e");
      if (e.toString().contains('disconnected')) {
        _connectedDeviceId = null;
        _isReady = false;
        notifyListeners();
      }
    } finally {
      _isSending = false;
    }
  }
}
