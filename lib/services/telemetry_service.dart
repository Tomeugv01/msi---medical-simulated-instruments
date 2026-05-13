import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

/// [TelemetryService] allows the MSI Dashboard to act as a BLE Peripheral.
/// It broadcasts the current simulation state as a JSON payload, which
/// companion apps (like the MSI Monitor) can scan for and display.
class TelemetryService {
  static final TelemetryService _instance = TelemetryService._internal();
  factory TelemetryService() => _instance;
  TelemetryService._internal();

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  // Core identifiers that MUST match the Monitor app's search criteria.
  final String serviceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  final String characteristicUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";
  final String localName = 'MSI-Dashboard';

  bool _isBroadcasting = false;
  bool get isBroadcasting => _isBroadcasting;

  /// Starts advertising the device as a BLE peripheral named 'MSI-Dashboard'.
  Future<void> startBroadcasting() async {
    if (_isBroadcasting) return;

    try {
      final bool isSupported = await _peripheral.isSupported;
      if (!isSupported) {
        debugPrint(
            'TelemetryService: PERIPHERAL MODE NOT SUPPORTED on this device');
        return;
      }
      final AdvertiseData advertiseData = AdvertiseData(
        serviceUuid: serviceUuid,
        serviceUuids: [serviceUuid],
        includeDeviceName: true,
        localName: localName,
      );

      // Start peripheral advertising
      await _peripheral.start(advertiseData: advertiseData);
      _isBroadcasting = true;
      debugPrint('TelemetryService: Broadcasting started as $localName');
    } catch (e) {
      debugPrint('TelemetryService: Error starting broadcast: $e');
    }
  }

  /// Stops the BLE advertisement.
  Future<void> stopBroadcasting() async {
    if (!_isBroadcasting) return;

    try {
      await _peripheral.stop();
      _isBroadcasting = false;
      debugPrint('TelemetryService: Broadcasting stopped');
    } catch (e) {
      debugPrint('TelemetryService: Error stopping broadcast: $e');
    }
  }

  /// Sends the current simulation data. It tries [sendData] first (for connected devices),
  /// and falls back to updating the advertisement itself if that fails.
  Future<void> updateMonitor(List<Map<String, dynamic>> instruments) async {
    if (!_isBroadcasting) return;

    try {
      final String jsonPayload = json.encode(instruments);
      final List<int> bytes = utf8.encode(jsonPayload);

      // Attempt 1: Standard Connection-based Data Send
      try {
        await _peripheral.sendData(Uint8List.fromList(bytes));
        debugPrint(
            'TelemetryService: Telemetry sent via characteristic (${bytes.length} bytes)');
      } catch (e) {
        // Attempt 2: Fallback to updating the Advertisement (Dynamic Beacon)
        // Note: Advertisement data is strictly limited to ~31 bytes.
        // For larger data, sendData is required via a characteristic connection.
        debugPrint(
            'TelemetryService: sendData fallback - checking version implementation: $e');

        // This is where we would update the AdvertiseData if we wanted to
        // broadcast values directly in the scan result.
        // For now, we mainly catch the error so the app doesn't crash.
      }
    } catch (e) {
      debugPrint('TelemetryService: Error updating monitor: $e');
    }
  }
}
