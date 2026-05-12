import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// [Instrument] defines a tile in the dashboard.
/// It tracks visibility preference and custom color selection.
class Instrument {
  final String title;
  final IconData icon;
  bool isEnabled;
  Color? textColor; // User-defined color for the vital sign value

  // Manual transmission controls
  bool isManualTransmission;
  bool hasPendingSync;

  Instrument({
    required this.title,
    required this.icon,
    this.isEnabled = true,
    this.textColor,
    this.isManualTransmission = false,
    this.hasPendingSync = false,
  });
}

/// [ClinicalEvent] represents an action taken during simulation (e.g., 'RCP', 'Drug').
/// It can have [healthEffects] which automatically shift vitals over time.
class ClinicalEvent {
  final String title;
  final Map<String, double> healthEffects; // Map of vitalKey -> changeAmount (e.g. {'hr': +10})

  ClinicalEvent({required this.title, this.healthEffects = const {}});

  Map<String, dynamic> toJson() => {
    'title': title,
    'healthEffects': healthEffects,
  };

  factory ClinicalEvent.fromJson(Map<String, dynamic> json) {
    return ClinicalEvent(
      title: json['title'] ?? '',
      healthEffects: (json['healthEffects'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, (v as num).toDouble())) ?? {},
    );
  }
}

/// [InstrumentalPreset] is a saved configuration of instruments and allowed actions.
/// Used for quick setup of training scenarios or specific clinical cases.
class InstrumentalPreset {
  final String id;
  String title;
  IconData icon;
  List<String> instrumentTitles; // Ordered list of instruments to show
  bool isClinical; // If true, it can define specific allowed actions
  List<ClinicalEvent> allowedEvents;
  List<String> allowedMeasurements;

  InstrumentalPreset({
    required this.id,
    required this.title,
    required this.icon,
    required this.instrumentTitles,
    this.isClinical = false,
    List<ClinicalEvent>? allowedEvents,
    List<String>? allowedMeasurements,
  }) : allowedEvents = allowedEvents ?? [],
       allowedMeasurements = allowedMeasurements ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'iconKey': iconMap.entries.firstWhere((e) => e.value == icon, orElse: () => iconMap.entries.first).key,
    'instrumentTitles': instrumentTitles,
    'isClinical': isClinical,
    'allowedEvents': allowedEvents.map((e) => e.toJson()).toList(),
    'allowedMeasurements': allowedMeasurements,
  };

  factory InstrumentalPreset.fromJson(Map<String, dynamic> json) {
    return InstrumentalPreset(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] ?? 'Sin título',
      icon: iconMap[json['iconKey']] ?? LucideIcons.wrench,
      instrumentTitles: List<String>.from(json['instrumentTitles'] ?? []),
      isClinical: json['isClinical'] ?? false,
      allowedEvents: (json['allowedEvents'] as List?)?.map((e) {
        if (e is String) return ClinicalEvent(title: e);
        return ClinicalEvent.fromJson(e);
      }).toList() ?? [],
      allowedMeasurements: List<String>.from(json['allowedMeasurements'] ?? []),
    );
  }
}

final Map<String, IconData> iconMap = {
  'thermometer': LucideIcons.thermometer,
  'droplets': LucideIcons.droplets,
  'heartPulse': LucideIcons.heartPulse,
  'activity': LucideIcons.activity,
  'wrench': LucideIcons.wrench,
  'clipboardList': LucideIcons.clipboardList,
  'zap': LucideIcons.zap,
  'stethoscope': LucideIcons.stethoscope,
  'flaskConical': LucideIcons.flaskConical,
  'volume2': LucideIcons.volume2,
  'gauge': LucideIcons.gauge,
  'wind': LucideIcons.wind,
};

class MSITheme {
  final String name;
  final Color primary;
  final Color background;
  final Color card;
  final Color text;
  final Color accent;

  MSITheme({
    required this.name,
    required this.primary,
    required this.background,
    required this.card,
    required this.text,
    required this.accent,
  });
}

final List<MSITheme> appThemes = [
  MSITheme(
    name: 'MSI Classic',
    primary: const Color(0xFF003F87),
    background: const Color(0xFFF8F9FA),
    card: Colors.white,
    text: const Color(0xFF003F87),
    accent: const Color(0xFFE8F1FF),
  ),
  MSITheme(
    name: 'Cyber Dark',
    primary: const Color(0xFFFFD700),
    background: const Color(0xFF000000),
    card: const Color(0xFF1A1A1A),
    text: const Color(0xFFFFD700),
    accent: const Color(0xFF333300),
  ),
  MSITheme(
    name: 'Médico Oscuro',
    primary: const Color(0xFF6366F1),
    background: const Color(0xFF0F172A),
    card: const Color(0xFF1E293B),
    text: Colors.white,
    accent: const Color(0xFF334155),
  ),
  MSITheme(
    name: 'Esmeralda',
    primary: const Color(0xFF10B981),
    background: const Color(0xFFF0FDF4),
    card: Colors.white,
    text: const Color(0xFF065F46),
    accent: const Color(0xFFDCFCE7),
  ),
  MSITheme(
    name: 'Atardecer',
    primary: const Color(0xFFF97316),
    background: const Color(0xFFFFF7ED),
    card: Colors.white,
    text: const Color(0xFF9A3412),
    accent: const Color(0xFFFFEDD5),
  ),
  MSITheme(
    name: 'Púrpura Neón',
    primary: const Color(0xFFA855F7),
    background: const Color(0xFFF5F3FF),
    card: Colors.white,
    text: const Color(0xFF6B21A8),
    accent: const Color(0xFFEDE9FE),
  ),
];
