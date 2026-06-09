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
  final Map<String, Timer> _pendingTransmissions = {};

  // Audio Module Delegation
  final PannedAudioService _audioService = PannedAudioService();

  // Telemetry Module (Peripheral Mode)
  final TelemetryService _telemetryService = TelemetryService();

  // --- Core Vital Signs (Current Simulation) ---
  int _hr = 72;
  int _spo2 = 98;
  int _co2 = 20;
  int _resp = 14;
  double _temp = 36.6;
  int _glucose = 110;
  int _sys = 120;
  int _dia = 80;

  // --- Transmitted Vital Signs ---
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
    Instrument(title: 'Glucemia', icon: LucideIcons.droplets),
    Instrument(title: 'FC', icon: LucideIcons.heartPulse),
    Instrument(title: 'SpO2 y FR', icon: LucideIcons.wind),
    Instrument(
        title: 'PANI/PAI', icon: LucideIcons.gauge, isVisibleOnMonitor: false),
    Instrument(title: 'Ruidos Vocales', icon: LucideIcons.mic),
    Instrument(title: 'Fonendoscopio', icon: LucideIcons.stethoscope),
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
      instrumentTitles: ['FC', 'SpO2 y FR', 'Termómetro'],
    ),
    InstrumentalPreset(
      id: '3',
      title: 'Control de Glucosa',
      icon: LucideIcons.droplets,
      instrumentTitles: ['Glucemia'],
    ),
    // Clinical Cases
    InstrumentalPreset(
      id: 'c1',
      title: 'Parada Cardíaca (PCR)',
      icon: LucideIcons.clipboardList,
      instrumentTitles: [
        'FC',
        'SpO2 y FR',
        'Termómetro',
        'PANI/PAI',
        'Ruidos Vocales',
        'Fonendoscopio'
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
        'Glucemia',
        'Termómetro',
        'PANI/PAI',
        'FC',
        'SpO2 y FR'
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
  bool _monitorThemeDark = true;
  final Set<String> _collapsedInstruments = {};

  SimulationState() {
    _loadSettings();
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
    await _audioService.playLeftOnly();
  }

  Future<void> playRight() async {
    await _audioService.playRightOnly();
  }

  Future<void> playBothRight() async {
    await _audioService.playBothOnRight();
  }

  Future<void> stopLeftSound() async {
    await _audioService.stopLeft();
  }

  Future<void> stopRightSound() async {
    await _audioService.stopRight();
  }

  Future<void> stopSound() async {
    await _audioService.stop();
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

  void reorderPreset(int oldIndex, int newIndex, {required bool isClinical}) {
    final filtered = _presets.where((p) => p.isClinical == isClinical).toList();
    if (oldIndex < 0 || oldIndex >= filtered.length) return;
    if (newIndex < 0) newIndex = 0;
    if (newIndex > filtered.length) newIndex = filtered.length;

    final preset = filtered[oldIndex];
    final oldGlobalIndex = _presets.indexOf(preset);
    if (oldGlobalIndex == -1) return;

    // Remove from old position
    _presets.removeAt(oldGlobalIndex);

    // Recompute filtered list after removal
    final remainingFiltered =
        _presets.where((p) => p.isClinical == isClinical).toList();

    int insertIndex;
    if (newIndex >= remainingFiltered.length) {
      // Insert after the last occurrence of this group or at the end
      final lastIndex =
          _presets.lastIndexWhere((p) => p.isClinical == isClinical);
      insertIndex = lastIndex == -1 ? _presets.length : lastIndex + 1;
    } else {
      final target = remainingFiltered[newIndex];
      insertIndex = _presets.indexOf(target);
    }

    _presets.insert(insertIndex, preset);
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

    // Ensure telemetry is stopped before starting a new simulation/preset
    try {
      _telemetryService.stop();
    } catch (_) {}
    startSimulation(); // <- este método ahora ocultará todos los instrumentos
    notifyListeners();
  }

  MSITheme get theme => appThemes[_themeIndex];
  int get themeIndex => _themeIndex;
  int get hubColumns => _hubColumns;
  bool get monitorThemeDark => _monitorThemeDark;

  void setHubColumns(int count) {
    _hubColumns = count;
    notifyListeners();
  }

  void setMonitorThemeDark(bool dark) {
    if (_monitorThemeDark == dark) return;
    _monitorThemeDark = dark;
    _saveSettings();
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

  void toggleVisibilityOnMonitor(String instrumentTitle) {
    final index = _instruments.indexWhere((i) => i.title == instrumentTitle);
    if (index != -1) {
      _instruments[index].isVisibleOnMonitor =
          !_instruments[index].isVisibleOnMonitor;
      _saveSettings();
      _sendFullStateToMonitor();
      notifyListeners();
    }
  }

  void setInstrumentDelay(String instrumentTitle, int delayMs) {
    final index = _instruments.indexWhere((i) => i.title == instrumentTitle);
    if (index != -1) {
      _instruments[index].transmissionDelayMs = delayMs;
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

  String _canonicalInstrumentTitle(String title) {
    switch (title) {
      case 'Frecuencia Cardíaca':
        return 'FC';
      case 'Sat% y FR':
        return 'SpO2 y FR';
      case 'Tensión Arterial':
        return 'PANI/PAI';
      case 'Glucómetro':
        return 'Glucemia';
      case 'Voz':
      case 'Voice':
      case 'Módulo de Sonido':
        return 'Ruidos Vocales';
      case 'Estetoscopio':
        return 'Fonendoscopio';
      default:
        return title;
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _supervisor = prefs.getString('supervisor') ?? '';
      _student = prefs.getString('student') ?? '';
      _notes = prefs.getString('notes') ?? '';
      _themeIndex = prefs.getInt('themeIndex') ?? 0;
      _monitorThemeDark = prefs.getBool('monitorThemeDark') ?? true;

      final instrumentsJson = prefs.getString('instruments');
      if (instrumentsJson != null) {
        final List<dynamic> list = jsonDecode(instrumentsJson);
        List<Instrument> loaded = [];
        final loadedTitles = <String>{};

        final defaultInstruments = [
          Instrument(title: 'Termómetro', icon: LucideIcons.thermometer),
          Instrument(title: 'Glucemia', icon: LucideIcons.droplets),
          Instrument(title: 'FC', icon: LucideIcons.heartPulse),
          Instrument(title: 'SpO2 y FR', icon: LucideIcons.wind),
          Instrument(
              title: 'PANI/PAI',
              icon: LucideIcons.gauge,
              isVisibleOnMonitor: false),
          Instrument(title: 'Ruidos Vocales', icon: LucideIcons.mic),
          Instrument(title: 'Fonendoscopio', icon: LucideIcons.stethoscope),
        ];

        for (var item in list) {
          final originalTitle = item['title'] ?? '';
          if (originalTitle == 'Pulsioxímetro') continue; // Clean legacy entry
          if (originalTitle == 'Módulo de Sonido')
            continue; // Direct split migration
          final title = _canonicalInstrumentTitle(originalTitle);
          final isEnabled = item['isEnabled'] ?? true;
          final isManual = item['isManualTransmission'] ??
              true; // <-- Cambiado: si no existe, true
          final bool isVisibleFinal;
          if (item.containsKey('isVisibleOnMonitor')) {
            isVisibleFinal = item['isVisibleOnMonitor'] ?? true;
          } else {
            isVisibleFinal = title == 'PANI/PAI' ? false : true;
          }
          if (!loadedTitles.add(title)) continue;
          final delay = ((item['transmissionDelayMs'] ?? 0) as num).toInt();
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
            isVisibleOnMonitor: isVisibleFinal,
            transmissionDelayMs: delay,
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
            if (!preset.instrumentTitles.contains('FC')) {
              preset.instrumentTitles.add('FC');
            }
            if (!preset.instrumentTitles.contains('SpO2 y FR')) {
              preset.instrumentTitles.add('SpO2 y FR');
            }
          }
          final normalizedTitles = <String>[];
          for (final title in preset.instrumentTitles
              .map(_canonicalInstrumentTitle)
              .toList()) {
            if (!normalizedTitles.contains(title)) {
              normalizedTitles.add(title);
            }
          }
          preset.instrumentTitles = normalizedTitles;
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
      await prefs.setBool('monitorThemeDark', _monitorThemeDark);

      final instrumentsData = _instruments
          .map((i) => ({
                'title': i.title,
                'isEnabled': i.isEnabled,
                'textColor': i.textColor?.value,
                'isManualTransmission': i.isManualTransmission,
                'isVisibleOnMonitor': i.isVisibleOnMonitor,
                'transmissionDelayMs': i.transmissionDelayMs,
              }))
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

  void setVital(String type, num value) {
    if (type == 'hr') _hr = value.toInt();
    if (type == 'spo2') _spo2 = value.toInt();
    if (type == 'co2') _co2 = value.toInt();
    if (type == 'resp') _resp = value.toInt();
    if (type == 'temp') _temp = value.toDouble();
    if (type == 'glucose') _glucose = value.toInt();
    if (type == 'sys') {
      _sys = value.toInt();
      _dia = (_sys * 0.67).round();
    }
    if (type == 'dia') {
      _dia = value.toInt();
      _sys = (_dia / 0.67).round();
    }

    String? instrumentTitle;
    if (type == 'hr') {
      instrumentTitle = 'FC';
    } else if (type == 'spo2' || type == 'co2') {
      instrumentTitle = 'SpO2 y FR';
    } else if (type == 'temp') {
      instrumentTitle = 'Termómetro';
    } else if (type == 'glucose') {
      instrumentTitle = 'Glucemia';
    } else if (type == 'sys' || type == 'dia') {
      instrumentTitle = 'PANI/PAI';
    }

    if (instrumentTitle != null) {
      final inst = _instruments.firstWhere((i) => i.title == instrumentTitle,
          orElse: () => Instrument(title: '', icon: LucideIcons.box));
      if (inst.title.isNotEmpty) {
        if (inst.isManualTransmission) {
          inst.hasPendingSync = _checkIfPending(instrumentTitle);
        } else {
          _syncTransmittedValues(instrumentTitle);
          _scheduleTransmission(instrumentTitle);
          _sendVitalsToDevice();
        }
      }
    } else {
      _sendVitalsToDevice();
    }

    notifyListeners();
  }

  void _scheduleTransmission(String instrumentTitle) {
    final inst = _instruments.firstWhere((i) => i.title == instrumentTitle,
        orElse: () => Instrument(title: '', icon: LucideIcons.box));
    if (inst.title.isEmpty) return;

    final delayMs = inst.transmissionDelayMs;
    _pendingTransmissions[instrumentTitle]?.cancel();

    if (delayMs == 0) {
      _sendFullStateToMonitor();
    } else {
      _pendingTransmissions[instrumentTitle] =
          Timer(Duration(milliseconds: delayMs), () {
        _sendFullStateToMonitor();
        _pendingTransmissions.remove(instrumentTitle);
      });
    }
  }

  bool _checkIfPending(String instrumentTitle) {
    if (instrumentTitle == 'FC') return _hr != _txHr;
    if (instrumentTitle == 'SpO2 y FR')
      return _spo2 != _txSpo2 || _co2 != _txCo2;
    if (instrumentTitle == 'Termómetro') return _temp != _txTemp;
    if (instrumentTitle == 'Glucemia') return _glucose != _txGlucose;
    if (instrumentTitle == 'PANI/PAI') return _sys != _txSys || _dia != _txDia;
    return false;
  }

  void _syncTransmittedValues(String instrumentTitle) {
    if (instrumentTitle == 'FC') _txHr = _hr;
    if (instrumentTitle == 'SpO2 y FR') {
      _txSpo2 = _spo2;
      _txCo2 = _co2;
    }
    if (instrumentTitle == 'Termómetro') _txTemp = _temp;
    if (instrumentTitle == 'Glucemia') _txGlucose = _glucose;
    if (instrumentTitle == 'PANI/PAI') {
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
        _sendFullStateToMonitor();
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
      _scheduleTransmission(instrumentTitle);
      _sendVitalsToDevice();
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

  // ===================== MODIFICACIÓN PRINCIPAL =====================
  // Al iniciar cualquier simulación, todos los instrumentos se ocultan en el monitor.
  // ==================================================================
  void startSimulation() async {
    if (_isRunning) return;

    // 🔄 RESET: todos los instrumentos empiezan ocultos en el monitor
    for (var inst in _instruments) {
      inst.isVisibleOnMonitor = false;
    }
    // Notificamos a la UI para que actualice los botones de ojo
    notifyListeners();
    // No guardamos en SharedPreferences para no perder la configuración permanente.

    // Limpiar servicio de telemetría
    try {
      await _telemetryService.stop();
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (_) {}

    // Solicitar permisos
    await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    _isRunning = true;
    for (var timer in _pendingTransmissions.values) {
      timer.cancel();
    }
    _pendingTransmissions.clear();
    _elapsed = Duration.zero;
    _logs.clear();
    _addLog("Simulación Iniciada",
        "Sistema inicializado y flujo de telemetría establecido.");

    if (_supervisor.isNotEmpty) _addLog("Profesor Asignado", _supervisor);
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

    if (_activeEvents.isEmpty) {
      _activeEvents = List.from(_events);
    }
    if (_activeMeasurements.isEmpty) {
      _activeMeasurements = List.from(_measurements);
    }

    for (var m in _activeMeasurements) {
      _completedMeasurements[m] = false;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsed += const Duration(seconds: 1);
      notifyListeners();
    });

    _vitalsTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _sendVitalsToDevice();
    });

    _telemetryService.startSearch();
    _telemetryService.removeListener(_onTelemetryReady);
    _telemetryService.addListener(_onTelemetryReady);
    _onTelemetryReady();

    _logTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkAndLogVitalsChanges();
    });

    notifyListeners();
  }
  // ==================================================================

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

  void _onTelemetryReady() {
    if (_telemetryService.isConnected && _isRunning) {
      _sendFullStateToMonitor();
    }
  }

  Future<void> stopSimulation() async {
    _isRunning = false;
    _timer?.cancel();
    _vitalsTimer?.cancel();
    _logTimer?.cancel();
    _telemetryService.removeListener(_onTelemetryReady);
    for (var timer in _pendingTransmissions.values) {
      timer.cancel();
    }
    _pendingTransmissions.clear();

    try {
      await _telemetryService.updateMonitor([
        {"type": "end_simulation"}
      ]);
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint("Error al enviar fin de simulación: $e");
    }

    await _telemetryService.stop();
    await _audioService.stop();

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
      Instrument(title: 'Glucemia', icon: LucideIcons.droplets),
      Instrument(title: 'FC', icon: LucideIcons.heartPulse),
      Instrument(title: 'SpO2 y FR', icon: LucideIcons.wind),
      Instrument(title: 'PANI/PAI', icon: LucideIcons.gauge),
      Instrument(title: 'Ruidos Vocales', icon: LucideIcons.mic),
      Instrument(title: 'Fonendoscopio', icon: LucideIcons.stethoscope),
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
        instrumentTitles: ['FC', 'SpO2 y FR', 'Termómetro'],
      ),
      InstrumentalPreset(
        id: '3',
        title: 'Control de Glucosa',
        icon: LucideIcons.droplets,
        instrumentTitles: ['Glucemia'],
      ),
      InstrumentalPreset(
        id: 'c1',
        title: 'Parada Cardíaca (PCR)',
        icon: LucideIcons.clipboardList,
        instrumentTitles: [
          'FC',
          'SpO2 y FR',
          'Termómetro',
          'PANI/PAI',
          'Fonendoscopio'
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
          'Glucemia',
          'Termómetro',
          'PANI/PAI',
          'FC',
          'SpO2 y FR'
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

  void reorderMeasurement(int oldIndex, int newIndex,
      {bool useActiveList = true}) {
    final target = useActiveList && _activeMeasurements.isNotEmpty
        ? _activeMeasurements
        : _measurements;

    if (oldIndex < 0 || oldIndex >= target.length) return;
    if (newIndex < 0) return;
    if (newIndex > target.length) newIndex = target.length;
    if (newIndex > oldIndex) newIndex -= 1;

    final item = target.removeAt(oldIndex);
    target.insert(newIndex, item);

    if (identical(target, _measurements)) {
      _saveSettings();
    }
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

  void _sendFullStateToMonitor() {
    if (!_isRunning) return;
    final List<Map<String, dynamic>> payload = [];
    for (var inst in enabledInstruments) {
      if (!inst.isVisibleOnMonitor) continue;
      _addInstrumentToPayload(inst, payload);
    }
    if (payload.isNotEmpty) {
      _telemetryService.updateMonitor(payload);
    } else {
      _telemetryService.updateMonitor([]);
    }
  }

  void _addInstrumentToPayload(
      Instrument inst, List<Map<String, dynamic>> payload) {
    if (inst.title == 'FC') {
      payload.add({
        "id": "hr_01",
        "type": "hr",
        "label": "FC",
        "value": "$_txHr",
        "unit": "LPM",
        "color": _hexFromColor(inst.textColor ?? const Color(0xFF22C55E)),
      });
    } else if (inst.title == 'SpO2 y FR') {
      payload.add({
        "id": "spo2_01",
        "type": "spo2",
        "label": "SpO2",
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
    } else if (inst.title == 'PANI/PAI') {
      payload.add({
        "id": "bp_01",
        "type": "bp",
        "label": "PANI/PAI",
        "value": "$_txSys/$_txDia",
        "unit": "mmHg",
        "color": _hexFromColor(inst.textColor ?? const Color(0xFFEF4444)),
      });
    } else if (inst.title == 'Termómetro') {
      payload.add({
        "id": "temp_01",
        "type": "temp",
        "label": "Temperatura",
        "value": _txTemp.toStringAsFixed(1),
        "unit": "°C",
        "color": _hexFromColor(inst.textColor ?? const Color(0xFF06B6D4)),
      });
    } else if (inst.title == 'Glucemia') {
      payload.add({
        "id": "glu_01",
        "type": "glu",
        "label": "Glucemia",
        "value": "$_txGlucose",
        "unit": "mg/dL",
        "color": _hexFromColor(inst.textColor ?? const Color(0xFFF97316)),
      });
    }
  }

  String _hexFromColor(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  @override
  void dispose() {
    _telemetryService.removeListener(_onTelemetryReady);
    for (var timer in _pendingTransmissions.values) {
      timer.cancel();
    }
    _pendingTransmissions.clear();
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
