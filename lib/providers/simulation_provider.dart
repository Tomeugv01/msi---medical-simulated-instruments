import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_session/audio_session.dart';
import '../models/instrumental_models.dart';
import '../services/audio_service.dart';
import '../services/telemetry_service.dart';

/// [SimulationState] is the central data hub of the application.
/// It manages vital signs, Bluetooth connectivity, persistent settings,
/// and the real-time simulation logic.
class SimulationState extends ChangeNotifier {
  final _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanStream;
  StreamSubscription<ConnectionStateUpdate>? _connectionStream;

  // Simulation Control
  bool _isRunning = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  Timer? _vitalsTimer;
  Timer? _logTimer;

  // Audio Module Delegation
  final PannedAudioService _audioService = PannedAudioService();

  // Telemetry Module (Peripheral Mode)
  final TelemetryService _telemetryService = TelemetryService();

  // --- Core Vital Signs (Current Simulation) ---
  int _hr = 72; // Heart Rate (BPM)
  int _spo2 = 98; // Oxygen Saturation (%)
  int _co2 = 20; // Repurposed for FR in Sat% y FR (logical rate)
  int _resp = 14; // Respiratory Rate (/min)
  double _temp = 36.6; // Temperature (°C)
  int _glucose = 110; // Blood Glucose (mg/dL)
  int _sys = 120; // Systolic Blood Pressure (mmHg)
  int _dia = 80; // Diastolic Blood Pressure (mmHg)

  // --- Transmitted Vital Signs (What the tablet sees) ---
  int _txHr = 72;
  int _txSpo2 = 98;
  int _txCo2 = 20;
  int _txResp = 14;
  double _txTemp = 36.6;
  int _txGlucose = 110;
  int _txSys = 120;
  int _txDia = 80;

  // Tracking vitals for automated smart logging
  int? _lastHr;
  int? _lastSpo2;
  int? _lastCo2;
  int? _lastResp;
  double? _lastTemp;
  int? _lastGlucose;
  int? _lastSys;
  int? _lastDia;

  // BLE State
  List<DiscoveredDevice> _devices = [];
  bool _isScanning = false;
  DeviceConnectionState _bleStatus = DeviceConnectionState.disconnected;
  String? _connectedDeviceId;

  // ESP32 UART UUIDs
  final Uuid _uartServiceId =
      Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
  final Uuid _uartTxCharacteristicId =
      Uuid.parse("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
  final Uuid _uartRxCharacteristicId =
      Uuid.parse("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");

  String _supervisor = '';
  String _student = '';
  String _notes = '';

  final List<Map<String, String>> _logs = [];

  final List<Instrument> _instruments = [
    Instrument(title: 'Termómetro', icon: LucideIcons.thermometer),
    Instrument(title: 'Glucómetro', icon: LucideIcons.droplets),
    Instrument(title: 'Frecuencia Cardíaca', icon: LucideIcons.heartPulse),
    Instrument(title: 'Sat% y FR', icon: LucideIcons.wind),
    Instrument(title: 'Tensión Arterial', icon: LucideIcons.gauge),
    Instrument(title: 'Voz', icon: LucideIcons.mic),
    Instrument(title: 'Estetoscopio', icon: LucideIcons.stethoscope),
  ];

  final List<InstrumentalPreset> _presets = [
    InstrumentalPreset(
      id: '1',
      title: 'Termometría Clínica',
      icon: LucideIcons.thermometer,
      instrumentTitles: ['Termómetro'],
    ),
    InstrumentalPreset(
      id: '2',
      title: 'Telemetría Avanzada',
      icon: LucideIcons.activity,
      instrumentTitles: ['Frecuencia Cardíaca', 'Sat% y FR', 'Termómetro'],
    ),
    InstrumentalPreset(
      id: '3',
      title: 'Control de Glucosa',
      icon: LucideIcons.droplets,
      instrumentTitles: ['Glucómetro'],
    ),
    // Clinical Cases
    InstrumentalPreset(
      id: 'c1',
      title: 'Parada Cardíaca (PCR)',
      icon: LucideIcons.clipboardList,
      instrumentTitles: [
        'Frecuencia Cardíaca',
        'Sat% y FR',
        'Termómetro',
        'Tensión Arterial',
        'Voz',
        'Estetoscopio'
      ],
      isClinical: true,
      allowedEvents: [
        ClinicalEvent(
            title: 'Inicio maniobras RCP',
            healthEffects: {'hr': 40, 'spo2': 5}),
        ClinicalEvent(
            title: 'Aplicación Desfibrilación', healthEffects: {'hr': 20}),
        ClinicalEvent(
            title: 'Administración de fármaco',
            healthEffects: {'hr': 30, 'sys': 20}),
        ClinicalEvent(
            title: 'Intubación Orotraqueal', healthEffects: {'spo2': 10}),
      ],
      allowedMeasurements: [
        'Pulso carotídeo detectado',
        'Llenado capilar (< 2s)',
        'Pupilas isocóricas'
      ],
    ),
    InstrumentalPreset(
      id: 'c2',
      title: 'Cetoacidosis Diabética',
      icon: LucideIcons.droplets,
      instrumentTitles: [
        'Glucómetro',
        'Termómetro',
        'Tensión Arterial',
        'Frecuencia Cardíaca',
        'Sat% y FR'
      ],
      isClinical: true,
      allowedEvents: [
        ClinicalEvent(title: 'Canalización de vía IV'),
        ClinicalEvent(
            title: 'Administración de fármaco',
            healthEffects: {'glucose': -50}),
      ],
      allowedMeasurements: [
        'Llenado capilar (< 2s)',
        'Presión Arterial Manual'
      ],
    ),
  ];

  int _themeIndex = 0;
  int _hubColumns = 1;
  final Set<String> _collapsedInstruments = {};

  SimulationState() {
    _loadSettings();
    // Connect to audio service changes
    _audioService.addListener(notifyListeners);
  }

  bool get isHeadsetConnected => _audioService.isHeadsetConnected;
  bool get isPTTActive => _audioService.isPTTActive;
  double get leftVolume => _audioService.leftVolume;
  double get rightVolume => _audioService.rightVolume;

  void setLeftVolume(double volume) {
    _audioService.setLeftVolume(volume);
  }

  void setRightVolume(double volume) {
    _audioService.setRightVolume(volume);
  }

  Future<void> startPTT() async {
    await _audioService.startPTT();
  }

  Future<void> stopPTT() async {
    await _audioService.stopPTT();
  }

  Future<void> playLeft() async {
    await _audioService.playLeftOnly('audio.mp3');
  }

  Future<void> playRight() async {
    await _audioService.playRightOnly('audio2.mp3');
  }

  Future<void> playBothRight() async {
    await _audioService.playBothOnRight('audio.mp3', 'audio2.mp3');
  }

  void stopSound() {
    _audioService.stop();
  }

  List<InstrumentalPreset> get instrumentalPresets =>
      _presets.where((p) => !p.isClinical).toList();
  List<InstrumentalPreset> get clinicalPresets =>
      _presets.where((p) => p.isClinical).toList();

  void addPreset(InstrumentalPreset preset) {
    _presets.add(preset);
    _saveSettings();
    notifyListeners();
  }

  void updatePreset(InstrumentalPreset updated) {
    final index = _presets.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      _presets[index] = updated;
      _saveSettings();
      notifyListeners();
    }
  }

  void deletePreset(String id) {
    _presets.removeWhere((p) => p.id == id);
    _saveSettings();
    notifyListeners();
  }

  List<ClinicalEvent> _activeEvents = [];
  List<String> _activeMeasurements = [];
  Map<String, bool> _completedMeasurements = {};

  List<ClinicalEvent> get activeEvents =>
      _isRunning ? (_activeEvents.isEmpty ? _events : _activeEvents) : _events;
  List<String> get activeMeasurements => _isRunning
      ? (_activeMeasurements.isEmpty ? _measurements : _activeMeasurements)
      : _measurements;

  bool isMeasurementCompleted(String name) =>
      _completedMeasurements[name] ?? false;

  void toggleMeasurement(String name) {
    if (!_completedMeasurements.containsKey(name)) {
      _completedMeasurements[name] = true;
    } else {
      _completedMeasurements[name] = !_completedMeasurements[name]!;
    }
    _addLog("Checklist",
        "$name: ${_completedMeasurements[name]! ? 'COMPLETADO' : 'PENDIENTE'}");
    notifyListeners();
  }

  void applyPreset(InstrumentalPreset preset) {
    // Reorder _instruments to match preset's order
    List<Instrument> reordered = [];
    for (var title in preset.instrumentTitles) {
      final index = _instruments.indexWhere((i) => i.title == title);
      if (index != -1) {
        final inst = _instruments[index];
        inst.isEnabled = true;
        reordered.add(inst);
      }
    }
    // Add remaining disabled instruments at the end
    for (var inst in _instruments) {
      if (!preset.instrumentTitles.contains(inst.title)) {
        inst.isEnabled = false;
        reordered.add(inst);
      }
    }
    _instruments.clear();
    _instruments.addAll(reordered);

    // Setup active actions
    _activeEvents = List.from(preset.allowedEvents);
    _activeMeasurements = List.from(preset.allowedMeasurements);
    _completedMeasurements.clear();
    for (var m in _activeMeasurements) {
      _completedMeasurements[m] = false;
    }

    // If empty (legacy/default), maybe we want to allow all?
    // Usually, if a clinical case is selected, it should have its own.
    // Let's stick to what's in the preset.

    // Ensure telemetry is stopped before starting a new simulation/preset
    try {
      _telemetryService.stop();
    } catch (_) {}
    startSimulation();
    notifyListeners();
  }

  MSITheme get theme => appThemes[_themeIndex];
  int get themeIndex => _themeIndex;
  int get hubColumns => _hubColumns;

  void setHubColumns(int count) {
    _hubColumns = count;
    notifyListeners();
  }

  bool isCollapsed(String title) => _collapsedInstruments.contains(title);

  void toggleCollapse(String title) {
    if (_collapsedInstruments.contains(title)) {
      _collapsedInstruments.remove(title);
    } else {
      _collapsedInstruments.add(title);
    }
    notifyListeners();
  }

  // Método nuevo para alternar visibilidad en el monitor
  void toggleVisibilityOnMonitor(String instrumentTitle) {
    final index = _instruments.indexWhere((i) => i.title == instrumentTitle);
    if (index != -1) {
      _instruments[index].isVisibleOnMonitor =
          !_instruments[index].isVisibleOnMonitor;
      _saveSettings();
      notifyListeners();
    }
  }

  List<Instrument> get displayInstruments {
    final enabled = enabledInstruments;
    final expanded = enabled.where((i) => !isCollapsed(i.title)).toList();
    final collapsed = enabled.where((i) => isCollapsed(i.title)).toList();
    return [...expanded, ...collapsed];
  }

  void setTheme(int index) {
    _themeIndex = index;
    _saveSettings();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _supervisor = prefs.getString('supervisor') ?? '';
      _student = prefs.getString('student') ?? '';
      _notes = prefs.getString('notes') ?? '';
      _themeIndex = prefs.getInt('themeIndex') ?? 0;

      final instrumentsJson = prefs.getString('instruments');
      if (instrumentsJson != null) {
        final List<dynamic> list = jsonDecode(instrumentsJson);
        List<Instrument> loaded = [];

        final defaultInstruments = [
          Instrument(title: 'Termómetro', icon: LucideIcons.thermometer),
          Instrument(title: 'Glucómetro', icon: LucideIcons.droplets),
          Instrument(
              title: 'Frecuencia Cardíaca', icon: LucideIcons.heartPulse),
          Instrument(title: 'Sat% y FR', icon: LucideIcons.wind),
          Instrument(title: 'Tensión Arterial', icon: LucideIcons.gauge),
          Instrument(title: 'Voz', icon: LucideIcons.mic),
          Instrument(title: 'Estetoscopio', icon: LucideIcons.stethoscope),
        ];

        for (var item in list) {
          final title = item['title'];
          if (title == 'Pulsioxímetro') continue; // Clean legacy entry
          if (title == 'Módulo de Sonido') continue; // Direct split migration
          final isEnabled = item['isEnabled'] ?? true;
          final isManual = item['isManualTransmission'] ??
              true; // <-- Cambiado: si no existe, true
          final isVisible = item['isVisibleOnMonitor'] ?? true;
          final colorVal = item['textColor'];
          final Color? textColor = colorVal != null ? Color(colorVal) : null;
          final original = defaultInstruments.firstWhere(
              (i) => i.title == title,
              orElse: () =>
                  Instrument(title: title, icon: LucideIcons.helpCircle));
          loaded.add(Instrument(
            title: title,
            icon: original.icon,
            isEnabled: isEnabled,
            textColor: textColor,
            isManualTransmission: isManual,
            isVisibleOnMonitor: isVisible,
          ));
        }

        for (var d in defaultInstruments) {
          if (!loaded.any((l) => l.title == d.title)) {
            loaded.add(d);
          }
        }

        _instruments.clear();
        _instruments.addAll(loaded);
      }

      final presetsJson = prefs.getString('presets');
      if (presetsJson != null) {
        final List<dynamic> list = jsonDecode(presetsJson);
        final List<InstrumentalPreset> loadedPresets = list.map((item) {
          final preset = InstrumentalPreset.fromJson(item);
          // Migration: replace legacy Pulsioxímetro with the two new ones
          if (preset.instrumentTitles.contains('Pulsioxímetro')) {
            preset.instrumentTitles.remove('Pulsioxímetro');
            if (!preset.instrumentTitles.contains('Frecuencia Cardíaca'))
              preset.instrumentTitles.add('Frecuencia Cardíaca');
            if (!preset.instrumentTitles.contains('Sat% y FR'))
              preset.instrumentTitles.add('Sat% y FR');
          }
          return preset;
        }).toList();
        _presets.clear();
        _presets.addAll(loadedPresets);
      }

      final eventsJson = prefs.getString('global_events');
      if (eventsJson != null) {
        final List<dynamic> list = jsonDecode(eventsJson);
        _events.clear();
        _events.addAll(list.map((e) => ClinicalEvent.fromJson(e)).toList());
      }

      final measurementsJson = prefs.getString('global_measurements');
      if (measurementsJson != null) {
        _measurements = List<String>.from(jsonDecode(measurementsJson));
      }

      notifyListeners();
    } catch (e) {
      debugPrint("Error loading settings: $e");
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('supervisor', _supervisor);
      await prefs.setString('student', _student);
      await prefs.setString('notes', _notes);
      await prefs.setInt('themeIndex', _themeIndex);

      final instrumentsData = _instruments
          .map((i) => {
                'title': i.title,
                'isEnabled': i.isEnabled,
                'textColor': i.textColor?.value,
                'isManualTransmission': i.isManualTransmission,
                'isVisibleOnMonitor': i.isVisibleOnMonitor,
              })
          .toList();
      await prefs.setString('instruments', jsonEncode(instrumentsData));

      final presetsData = _presets.map((p) => p.toJson()).toList();
      await prefs.setString('presets', jsonEncode(presetsData));

      final eventsData = _events.map((e) => e.toJson()).toList();
      await prefs.setString('global_events', jsonEncode(eventsData));

      await prefs.setString('global_measurements', jsonEncode(_measurements));
    } catch (e) {
      debugPrint("Error saving settings: $e");
    }
  }

  bool get isRunning => _isRunning;
  String get timeString => _elapsed.toString().split('.').first.padLeft(8, '0');
  int get hr => _hr;
  int get spo2 => _spo2;
  int get co2 => _co2;
  int get resp => _resp;
  double get temp => _temp;
  int get glucose => _glucose;
  int get sys => _sys;
  int get dia => _dia;
  List<Map<String, String>> get logs => _logs;
  List<Instrument> get instruments => _instruments;
  List<Instrument> get enabledInstruments =>
      _instruments.where((i) => i.isEnabled).toList();

  String get supervisor => _supervisor;
  String get student => _student;
  String get notes => _notes;

  List<DiscoveredDevice> get devices => _devices;
  bool get isScanning => _isScanning;
  DeviceConnectionState get bleStatus => _bleStatus;
  bool get isConnected => _bleStatus == DeviceConnectionState.connected;

  /// Updates a specific vital sign and triggers necessary side effects.
  /// This includes physiological correlations (like Systolic/Diastolic ratio)
  /// and broadcasting updates to any connected Bluetooth hardware.
  void setVital(String type, num value) {
    if (type == 'hr') _hr = value.toInt();
    if (type == 'spo2') _spo2 = value.toInt();
    if (type == 'co2') _co2 = value.toInt();
    if (type == 'resp') _resp = value.toInt();
    if (type == 'temp') _temp = value.toDouble();
    if (type == 'glucose') _glucose = value.toInt();
    if (type == 'sys') {
      _sys = value.toInt();
      // Physiological correlation: Diastolic is roughly 2/3 of Systolic in healthy adults
      _dia = (_sys * 0.67).round();
    }
    if (type == 'dia') {
      _dia = value.toInt();
      // Reverse correlation logic for bidirectional manual adjustment
      _sys = (_dia / 0.67).round();
    }
    notifyListeners();
    _handleTransmissionUpdate(type);
  }

  void _handleTransmissionUpdate(String vitalKey) {
    String? instrumentTitle;
    if (['hr', 'spo2', 'co2'].contains(vitalKey)) {
      if (vitalKey == 'hr')
        instrumentTitle = 'Frecuencia Cardíaca';
      else
        instrumentTitle = 'Sat% y FR';
    } else if (vitalKey == 'temp')
      instrumentTitle = 'Termómetro';
    else if (vitalKey == 'glucose')
      instrumentTitle = 'Glucómetro';
    else if (['sys', 'dia'].contains(vitalKey))
      instrumentTitle = 'Tensión Arterial';

    if (instrumentTitle != null) {
      final inst = _instruments.firstWhere((i) => i.title == instrumentTitle,
          orElse: () => Instrument(title: '', icon: LucideIcons.box));
      if (inst.title.isNotEmpty) {
        if (inst.isManualTransmission) {
          inst.hasPendingSync = _checkIfPending(instrumentTitle);
        } else {
          _syncTransmittedValues(instrumentTitle);
          _sendVitalsToDevice();
        }
      }
    } else {
      _sendVitalsToDevice();
    }
  }

  bool _checkIfPending(String instrumentTitle) {
    if (instrumentTitle == 'Frecuencia Cardíaca') return _hr != _txHr;
    if (instrumentTitle == 'Sat% y FR')
      return _spo2 != _txSpo2 || _co2 != _txCo2;
    if (instrumentTitle == 'Termómetro') return _temp != _txTemp;
    if (instrumentTitle == 'Glucómetro') return _glucose != _txGlucose;
    if (instrumentTitle == 'Tensión Arterial')
      return _sys != _txSys || _dia != _txDia;
    return false;
  }

  void _syncTransmittedValues(String instrumentTitle) {
    if (instrumentTitle == 'Frecuencia Cardíaca') _txHr = _hr;
    if (instrumentTitle == 'Sat% y FR') {
      _txSpo2 = _spo2;
      _txCo2 = _co2;
    }
    if (instrumentTitle == 'Termómetro') _txTemp = _temp;
    if (instrumentTitle == 'Glucómetro') _txGlucose = _glucose;
    if (instrumentTitle == 'Tensión Arterial') {
      _txSys = _sys;
      _txDia = _dia;
    }
  }

  void toggleTransmissionMode(String instrumentTitle) {
    final idx = _instruments.indexWhere((i) => i.title == instrumentTitle);
    if (idx != -1) {
      _instruments[idx].isManualTransmission =
          !_instruments[idx].isManualTransmission;
      if (!_instruments[idx].isManualTransmission) {
        _syncTransmittedValues(instrumentTitle);
        _instruments[idx].hasPendingSync = false;
        _sendVitalsToDevice();
      }
      notifyListeners();
    }
  }

  void syncInstrument(String instrumentTitle) {
    final idx = _instruments.indexWhere((i) => i.title == instrumentTitle);
    if (idx != -1) {
      _syncTransmittedValues(instrumentTitle);
      _instruments[idx].hasPendingSync = false;
      // Enviar solo este instrumento al monitor
      _sendSingleInstrumentToMonitor(instrumentTitle);
      _sendVitalsToDevice(); // Para hardware externo
      notifyListeners();
    }
  }

  void setSessionInfo({String? supervisor, String? student, String? notes}) {
    if (supervisor != null) _supervisor = supervisor;
    if (student != null) _student = student;
    if (notes != null) _notes = notes;
    _saveSettings();
    notifyListeners();
  }

  void toggleInstrument(int index) {
    _instruments[index].isEnabled = !_instruments[index].isEnabled;
    _saveSettings();
    notifyListeners();
  }

  void setInstrumentColor(int index, Color? color) {
    _instruments[index].textColor = color;
    _saveSettings();
    notifyListeners();
  }

  void reorderInstruments(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _instruments.removeAt(oldIndex);
    _instruments.insert(newIndex, item);
    _saveSettings();
    notifyListeners();
  }

  void startSimulation() async {
    if (_isRunning) return;
    // Ensure telemetry service is stopped and clean before starting
    try {
      await _telemetryService.stop();
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (_) {}

    // Request Peripheral and Scanning Permissions
    await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    _isRunning = true;
    _elapsed = Duration.zero;
    _logs.clear();
    _addLog("Simulación Iniciada",
        "Sistema inicializado y flujo de telemetría establecido.");

    if (_supervisor.isNotEmpty) _addLog("Supervisor Asignado", _supervisor);
    if (_student.isNotEmpty) _addLog("Estudiante Asignado", _student);
    if (_notes.isNotEmpty) _addLog("Notas de la Sesión", _notes);

    _lastHr = _hr;
    _lastSpo2 = _spo2;
    _lastCo2 = _co2;
    _lastResp = _resp;
    _lastTemp = _temp;
    _lastGlucose = _glucose;
    _lastSys = _sys;
    _lastDia = _dia;
    _completedMeasurements.clear();
    _collapsedInstruments.clear();
    _collapsedInstruments.addAll(enabledInstruments.map((i) => i.title));

    // If it's a "Quick Start" (no active events/measurements set by a preset),
    // we use the global ones.
    if (_activeEvents.isEmpty) {
      _activeEvents = List.from(_events);
    }
    if (_activeMeasurements.isEmpty) {
      _activeMeasurements = List.from(_measurements);
    }

    // Initialize completion status
    for (var m in _activeMeasurements) {
      _completedMeasurements[m] = false;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsed += const Duration(seconds: 1);
      notifyListeners();
    });

    _vitalsTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _sendVitalsToDevice();
      _broadcastToMonitor();
    });

    // Start searching for monitors after ensuring telemetry was reset
    _telemetryService.startSearch();

    _logTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkAndLogVitalsChanges();
    });

    notifyListeners();
  }

  void _checkAndLogVitalsChanges() {
    List<String> changes = [];
    if (_hr != _lastHr) changes.add("FC: $_hr BPM");
    if (_spo2 != _lastSpo2) changes.add("Sat%: $_spo2%");
    if (_co2 != _lastCo2) changes.add("FR: $_co2 rpm");
    if (_temp != _lastTemp) changes.add("Temp: ${_temp.toStringAsFixed(1)}°C");
    if (_glucose != _lastGlucose) changes.add("Glucosa: $_glucose mg/dL");
    if (_sys != _lastSys || _dia != _lastDia)
      changes.add("TA: $_sys/$_dia mmHg");

    if (changes.isNotEmpty) {
      _addLog(
          "Ajuste de Parámetros", "Cambio detectado: ${changes.join(', ')}");
      _lastHr = _hr;
      _lastSpo2 = _spo2;
      _lastCo2 = _co2;
      _lastResp = _resp;
      _lastTemp = _temp;
      _lastGlucose = _glucose;
      _lastSys = _sys;
      _lastDia = _dia;
      notifyListeners();
    }
  }

  void stopSimulation() {
    _isRunning = false;
    _timer?.cancel();
    _vitalsTimer?.cancel();
    _logTimer?.cancel();
    _telemetryService.stop();

    // Final checklist summary
    if (_completedMeasurements.isNotEmpty) {
      int total = _completedMeasurements.length;
      int completed = _completedMeasurements.values.where((v) => v).length;

      String summary = "Desempeño Checklist ($completed/$total):\n";
      summary += _completedMeasurements.entries
          .map((e) => "${e.value ? '✅' : '❌'} ${e.key}")
          .join("\n");
      _addLog("Evaluación Final", summary);
    }

    _activeEvents = [];
    _activeMeasurements = [];
    _completedMeasurements.clear();

    _addLog("Simulación Finalizada", "Sesión finalizada por el operador.");
    notifyListeners();
  }

  void resetToDefaults() {
    _instruments.clear();
    _instruments.addAll([
      Instrument(title: 'Termómetro', icon: LucideIcons.thermometer),
      Instrument(title: 'Glucómetro', icon: LucideIcons.droplets),
      Instrument(title: 'Frecuencia Cardíaca', icon: LucideIcons.heartPulse),
      Instrument(title: 'Sat% y FR', icon: LucideIcons.wind),
      Instrument(title: 'Tensión Arterial', icon: LucideIcons.gauge),
      Instrument(title: 'Voz', icon: LucideIcons.mic),
      Instrument(title: 'Estetoscopio', icon: LucideIcons.stethoscope),
    ]);

    _presets.clear();
    _presets.addAll([
      InstrumentalPreset(
        id: '1',
        title: 'Termometría Clínica',
        icon: LucideIcons.thermometer,
        instrumentTitles: ['Termómetro'],
      ),
      InstrumentalPreset(
        id: '2',
        title: 'Telemetría Avanzada',
        icon: LucideIcons.activity,
        instrumentTitles: ['Frecuencia Cardíaca', 'Sat% y FR', 'Termómetro'],
      ),
      InstrumentalPreset(
        id: '3',
        title: 'Control de Glucosa',
        icon: LucideIcons.droplets,
        instrumentTitles: ['Glucómetro'],
      ),
      InstrumentalPreset(
        id: 'c1',
        title: 'Parada Cardíaca (PCR)',
        icon: LucideIcons.clipboardList,
        instrumentTitles: [
          'Frecuencia Cardíaca',
          'Sat% y FR',
          'Termómetro',
          'Tensión Arterial',
          'Estetoscopio'
        ],
        isClinical: true,
        allowedEvents: [
          ClinicalEvent(
              title: 'Inicio maniobras RCP',
              healthEffects: {'hr': 40, 'spo2': 5}),
          ClinicalEvent(
              title: 'Aplicación Desfibrilación', healthEffects: {'hr': 20}),
          ClinicalEvent(
              title: 'Administración de fármaco (Adrenalina)',
              healthEffects: {'hr': 30, 'sys': 20}),
          ClinicalEvent(
              title: 'Intubación Orotraqueal', healthEffects: {'spo2': 10}),
        ],
        allowedMeasurements: [
          'Pulso carotídeo detectado',
          'Llenado capilar (< 2s)',
          'Pupilas isocóricas'
        ],
      ),
      InstrumentalPreset(
        id: 'c2',
        title: 'Cetoacidosis Diabética',
        icon: LucideIcons.droplets,
        instrumentTitles: [
          'Glucómetro',
          'Termómetro',
          'Tensión Arterial',
          'Frecuencia Cardíaca',
          'Sat% y FR'
        ],
        isClinical: true,
        allowedEvents: [
          ClinicalEvent(title: 'Canalización de vía IV'),
          ClinicalEvent(
              title: 'Administración de fármaco (Insulina)',
              healthEffects: {'glucose': -50}),
        ],
        allowedMeasurements: [
          'Llenado capilar (< 2s)',
          'Presión Arterial Manual'
        ],
      ),
    ]);

    _themeIndex = 0;
    _hubColumns = 1;
    _collapsedInstruments.clear();
    _saveSettings();
    notifyListeners();
  }

  List<ClinicalEvent> _events = [
    ClinicalEvent(title: 'Apertura de vía aérea', healthEffects: {'spo2': 2}),
    ClinicalEvent(title: 'Sondaje Vesical'),
    ClinicalEvent(title: 'Intubación Orotraqueal', healthEffects: {'spo2': 15}),
    ClinicalEvent(title: 'Canalización de vía IV'),
    ClinicalEvent(title: 'Administración de fármaco'),
    ClinicalEvent(title: 'Posición Lateral de Seguridad'),
    ClinicalEvent(
        title: 'Inicio maniobras RCP', healthEffects: {'hr': 50, 'spo2': 5}),
    ClinicalEvent(title: 'Aplicación Desfibrilación'),
  ];
  List<ClinicalEvent> get events => _events;

  List<String> _measurements = [
    'Pulso carotídeo detectado',
    'Pulso radial detectado',
    'Llenado capilar (< 2s)',
    'Pupilas isocóricas',
    'Escala de Glasgow evaluada',
    'Presión Arterial Manual',
    'Auscultación pulmonar bilateral',
  ];
  List<String> get measurements => _measurements;

  void addEvent(ClinicalEvent event) {
    _events.add(event);
    _saveSettings();
    notifyListeners();
  }

  void deleteEvent(int index) {
    _events.removeAt(index);
    _saveSettings();
    notifyListeners();
  }

  void updateEvent(int index, ClinicalEvent event) {
    _events[index] = event;
    _saveSettings();
    notifyListeners();
  }

  void addMeasurement(String name) {
    _measurements.add(name);
    _saveSettings();
    notifyListeners();
  }

  void deleteMeasurement(int index) {
    _measurements.removeAt(index);
    _saveSettings();
    notifyListeners();
  }

  void updateMeasurement(int index, String name) {
    _measurements[index] = name;
    _saveSettings();
    notifyListeners();
  }

  void recordEvent(ClinicalEvent event) {
    _addLog("Evento Clínico", event.title);

    // Apply effects
    event.healthEffects.forEach((vital, change) {
      if (vital == 'hr') setVital('hr', _hr + change);
      if (vital == 'spo2') setVital('spo2', (_spo2 + change).clamp(0, 100));
      if (vital == 'resp') setVital('resp', _resp + change);
      if (vital == 'temp') setVital('temp', _temp + change);
      if (vital == 'glucose') setVital('glucose', _glucose + change);
      if (vital == 'sys') setVital('sys', _sys + change);
      if (vital == 'dia') setVital('dia', _dia + change);
    });

    notifyListeners();
  }

  void recordAction(String title, String description) {
    _addLog(title, description);
    notifyListeners();
  }

  void _addLog(String title, String desc) {
    _logs.insert(0, {
      "time": timeString,
      "title": title,
      "desc": desc,
    });
  }

  Future<void> startScan() async {
    if (_isScanning) return;
    final status = await Permission.bluetoothScan.request();
    final locationStatus = await Permission.location.request();
    final connectStatus = await Permission.bluetoothConnect.request();

    if (status.isDenied || locationStatus.isDenied || connectStatus.isDenied) {
      _addLog("Error de BLE", "Permisos denegados.");
      return;
    }

    _devices = [];
    _isScanning = true;
    notifyListeners();

    _scanStream = _ble.scanForDevices(withServices: []).listen((device) {
      final index = _devices.indexWhere((d) => d.id == device.id);
      if (index == -1) {
        _devices.add(device);
        notifyListeners();
      }
    });

    Timer(const Duration(seconds: 10), stopScan);
  }

  void stopScan() {
    _scanStream?.cancel();
    _isScanning = false;
    notifyListeners();
  }

  void connect(String deviceId) {
    _connectionStream?.cancel();
    _bleStatus = DeviceConnectionState.connecting;
    notifyListeners();

    _connectionStream =
        _ble.connectToDevice(id: deviceId).listen((state) async {
      _bleStatus = state.connectionState;
      _connectedDeviceId = deviceId;
      if (state.connectionState == DeviceConnectionState.connected) {
        _addLog("BLE Conectado", "Dispositivo: $deviceId");
        try {
          await _ble.requestMtu(deviceId: deviceId, mtu: 512);
        } catch (e) {
          _addLog("Error MTU", e.toString());
        }
      } else if (state.connectionState == DeviceConnectionState.disconnected) {
        _addLog("BLE Desconectado", "Dispositivo: $deviceId");
      }
      notifyListeners();
    }, onError: (e) {
      _bleStatus = DeviceConnectionState.disconnected;
      _addLog("Error de BLE", e.toString());
      notifyListeners();
    });
  }

  void disconnect() {
    _connectionStream?.cancel();
    _bleStatus = DeviceConnectionState.disconnected;
    _connectedDeviceId = null;
    notifyListeners();
  }

  void _sendVitalsToDevice() {
    if (_bleStatus != DeviceConnectionState.connected ||
        _connectedDeviceId == null) return;
    final data = {
      "hr": _txHr,
      "spo2": _txSpo2,
      "co2": _txCo2,
      "resp": _txResp,
      "temp": _txTemp,
      "glucose": _txGlucose,
      "sys": _txSys,
      "dia": _txDia
    };
    final payload = "${jsonEncode(data)}\n";
    final characteristic = QualifiedCharacteristic(
      serviceId: _uartServiceId,
      characteristicId: _uartRxCharacteristicId,
      deviceId: _connectedDeviceId!,
    );
    try {
      _ble.writeCharacteristicWithoutResponse(characteristic,
          value: utf8.encode(payload));
    } catch (e) {
      _addLog("Error de Envío", e.toString());
    }
  }

  /// Converts current simulation state to a JSON format the MSI Monitor app expects.
  /// Converts current simulation state to a JSON format the MSI Monitor app expects.
  void _broadcastToMonitor() {
    if (!_isRunning) return;
    final List<Map<String, dynamic>> payload = [];
    for (var inst in enabledInstruments) {
      if (!inst.isVisibleOnMonitor) continue;
      // YA NO SALTAMOS LOS MANUALES: se incluyen con sus valores transmitidos (_tx)
      _addInstrumentToPayload(inst, payload);
    }
    if (payload.isNotEmpty) {
      _telemetryService.updateMonitor(payload);
    }
  }

  // Nuevo helper para añadir instrumento al payload
  void _addInstrumentToPayload(
      Instrument inst, List<Map<String, dynamic>> payload) {
    if (inst.title == 'Frecuencia Cardíaca') {
      payload.add({
        "id": "hr_01",
        "type": "hr",
        "label": "Heart Rate",
        "value": "$_txHr",
        "unit": "bpm",
        "color": _hexFromColor(inst.textColor ?? const Color(0xFF22C55E)),
      });
    } else if (inst.title == 'Sat% y FR') {
      payload.add({
        "id": "spo2_01",
        "type": "spo2",
        "label": "Sat%",
        "value": "$_txSpo2",
        "unit": "%",
        "color": _hexFromColor(inst.textColor ?? const Color(0xFF3B82F6)),
      });
      payload.add({
        "id": "co2_01",
        "type": "resp",
        "label": "FR",
        "value": "$_txCo2",
        "unit": "rpm",
        "color": _hexFromColor(inst.textColor ?? const Color(0xFFEAB308)),
      });
    } else if (inst.title == 'Tensión Arterial') {
      payload.add({
        "id": "bp_01",
        "type": "bp",
        "label": "Blood Pressure",
        "value": "$_txSys/$_txDia",
        "unit": "mmHg",
        "color": _hexFromColor(inst.textColor ?? const Color(0xFFEF4444)),
      });
    } else if (inst.title == 'Termómetro') {
      payload.add({
        "id": "temp_01",
        "type": "temp",
        "label": "Temperature",
        "value": _txTemp.toStringAsFixed(1),
        "unit": "°C",
        "color": _hexFromColor(inst.textColor ?? const Color(0xFF06B6D4)),
      });
    } else if (inst.title == 'Glucómetro') {
      payload.add({
        "id": "glu_01",
        "type": "glu",
        "label": "Glucose",
        "value": "$_txGlucose",
        "unit": "mg/dL",
        "color": _hexFromColor(inst.textColor ?? const Color(0xFFF97316)),
      });
    }
  }

  // Nuevo método para enviar un solo instrumento al monitor
  void _sendSingleInstrumentToMonitor(String instrumentTitle) {
    if (!_isRunning) return;
    final inst = _instruments.firstWhere((i) => i.title == instrumentTitle,
        orElse: () => Instrument(title: '', icon: LucideIcons.box));
    if (inst.title.isEmpty || !inst.isVisibleOnMonitor) return;
    final List<Map<String, dynamic>> payload = [];
    _addInstrumentToPayload(inst, payload);
    if (payload.isNotEmpty) {
      _telemetryService.updateMonitor(payload);
    }
  }

  String _hexFromColor(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  @override
  void dispose() {
    _audioService.removeListener(notifyListeners);
    _audioService.dispose();
    _telemetryService.stop();
    _scanStream?.cancel();
    _connectionStream?.cancel();
    _timer?.cancel();
    _vitalsTimer?.cancel();
    _logTimer?.cancel();
    super.dispose();
  }
}
