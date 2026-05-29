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
  bool _isConnecting = false; // Evita múltiples conexiones simultáneas

  List<DiscoveredDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);
  bool get isSearching => _isSearching;
  bool get isConnected => _connectedDeviceId != null;
  String? get connectedDeviceId => _connectedDeviceId;
  bool get isConnecting => _isConnecting;

  Future<bool> requestPermissions() async {
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();

    final granted = permissions[Permission.bluetoothScan]!.isGranted &&
        permissions[Permission.bluetoothConnect]!.isGranted &&
        permissions[Permission.location]!.isGranted;
    debugPrint("Permisos BLE: $granted");
    return granted;
  }

  Future<void> startSearch() async {
    if (_isSearching) return;
    if (!await requestPermissions()) {
      debugPrint('❌ Sin permisos BLE – no se puede escanear');
      return;
    }

    _isSearching = true;
    _discoveredDevices.clear();
    notifyListeners();
    debugPrint('🔍 Buscando dispositivos...');

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
          debugPrint('✅ Encontrado: ${device.name} (${device.id})');
          notifyListeners();
        }
      }
    }, onError: (e) {
      debugPrint('❌ Error escaneo: $e');
      _isSearching = false;
      notifyListeners();
    });
  }

  void stopSearch() {
    _scanSubscription?.cancel();
    _isSearching = false;
    notifyListeners();
  }

  // Reinicia el estado de conexión por completo
  Future<void> resetConnection() async {
    if (_isConnecting) return;
    _isConnecting = true;
    try {
      debugPrint("🔄 Reiniciando estado de conexión...");
      if (_connectedDeviceId != null) {
        // Intentar desconectar limpiamente
        await _connectionSubscription?.cancel();
        _connectionSubscription = null;
      }
      _connectedDeviceId = null;
      _isReady = false;
      notifyListeners();
      // Pequeña pausa para que el sistema libere recursos
      await Future.delayed(const Duration(milliseconds: 500));
    } finally {
      _isConnecting = false;
    }
  }

  // Conexión manual, un solo intento sin reintentos automáticos
  Future<bool> connectToMonitor(String deviceId) async {
    if (_isConnecting) {
      debugPrint("⚠️ Ya hay un intento de conexión en curso");
      return false;
    }
    _isConnecting = true;
    debugPrint("🔌 Conectando a $deviceId (intento único)...");

    // Limpiar cualquier conexión o escaneo previo
    stopSearch();
    await resetConnection();

    if (!await requestPermissions()) {
      debugPrint("❌ Sin permisos – no se puede conectar");
      _isConnecting = false;
      return false;
    }

    bool success = false;
    final completer = Completer<bool>();

    // Escuchamos el estado de la conexión
    _connectionSubscription = _ble
        .connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 15),
    )
        .listen((state) async {
      debugPrint("📡 Estado conexión: ${state.connectionState}");
      if (state.connectionState == DeviceConnectionState.connected) {
        _connectedDeviceId = deviceId;
        notifyListeners();
        debugPrint("✅ Conectado al monitor!");

        // Esperamos un momento para que el GATT se estabilice
        await Future.delayed(const Duration(milliseconds: 500));

        try {
          final services = await _ble.discoverServices(deviceId);
          debugPrint("📋 Servicios descubiertos: ${services.length}");
          final mtu = await _ble.requestMtu(deviceId: deviceId, mtu: 512);
          debugPrint("📏 MTU: $mtu");
          _isReady = true;
          notifyListeners();
          success = true;
          if (!completer.isCompleted) completer.complete(true);
        } catch (e) {
          debugPrint("⚠️ Error descubriendo servicios/MTU: $e");
          _connectedDeviceId = null;
          _isReady = false;
          success = false;
          if (!completer.isCompleted) completer.complete(false);
        }
      } else if (state.connectionState == DeviceConnectionState.disconnected) {
        debugPrint("❌ Desconectado del monitor");
        if (_connectedDeviceId != null) {
          // Si estábamos conectados y se perdió la conexión, marcamos como error
          _connectedDeviceId = null;
          _isReady = false;
          success = false;
          if (!completer.isCompleted) completer.complete(false);
          notifyListeners();
        } else if (!completer.isCompleted) {
          // Nunca llegó a conectarse
          completer.complete(false);
        }
      }
    }, onError: (error) {
      debugPrint("❌ Error de conexión: $error");
      _connectedDeviceId = null;
      _isReady = false;
      success = false;
      if (!completer.isCompleted) completer.complete(false);
      notifyListeners();
    });

    // Esperamos el resultado (máximo 20 segundos)
    final result = await completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        debugPrint("⏰ Tiempo de conexión agotado");
        _connectionSubscription?.cancel();
        _connectionSubscription = null;
        _connectedDeviceId = null;
        _isReady = false;
        notifyListeners();
        return false;
      },
    );

    _isConnecting = false;
    return result;
  }

  Future<void> setMonitorTheme(bool dark) async {
    if (_connectedDeviceId == null || !_isReady) return;
    final payload = [
      {"type": "set_theme", "theme": dark ? "dark" : "light"}
    ];
    await updateMonitor(payload);
  }

  Future<void> stop() async {
    // Cancelar cualquier conexión en curso
    if (_isConnecting) {
      debugPrint("Esperando a que termine la conexión en curso...");
      await Future.delayed(const Duration(milliseconds: 500));
    }
    stopSearch();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connectedDeviceId = null;
    _isReady = false;
    _isConnecting = false;
    debugPrint("TelemetryService detenido");
    notifyListeners();
  }

  Future<void> updateMonitor(List<Map<String, dynamic>> instruments) async {
    if (_connectedDeviceId == null || !_isReady) {
      debugPrint("⚠️ No conectado o no listo – no se puede enviar datos");
      return;
    }

    try {
      final String jsonPayload = json.encode(instruments);
      final List<int> bytes = utf8.encode(jsonPayload);
      debugPrint("📤 Tamaño payload: ${bytes.length} bytes");

      // Obtener características del servicio para asegurar la correcta
      final services = await _ble.discoverServices(_connectedDeviceId!);
      final targetService = services.firstWhere(
          (s) => s.serviceId == serviceUuid,
          orElse: () => throw Exception("Servicio no encontrado"));
      final characteristics = targetService.characteristics;
      final targetChar = characteristics.firstWhere(
          (c) => c.characteristicId == characteristicUuid,
          orElse: () => throw Exception("Característica no encontrada"));

      final characteristic = QualifiedCharacteristic(
        serviceId: targetService.serviceId,
        characteristicId: targetChar.characteristicId,
        deviceId: _connectedDeviceId!,
      );

      const int chunkSize = 480;
      for (int i = 0; i < bytes.length; i += chunkSize) {
        final end =
            (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = bytes.sublist(i, end);
        debugPrint(
            "📤 Enviando fragmento ${(i ~/ chunkSize) + 1}: ${chunk.length} bytes");
        await _ble.writeCharacteristicWithResponse(characteristic,
            value: chunk);
        await Future.delayed(const Duration(milliseconds: 60));
      }
      debugPrint("✅ Todos los fragmentos enviados");
    } catch (e) {
      debugPrint("❌ Error escritura: $e");
      if (e.toString().contains('disconnected') ||
          e.toString().contains('GATT')) {
        _connectedDeviceId = null;
        _isReady = false;
        notifyListeners();
      }
    }
  }
}
