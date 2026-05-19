import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/simulation_provider.dart';
import '../models/instrumental_models.dart';
import '../services/telemetry_service.dart';

/// [HubScreen] is the main operational view where the user monitors the simulation.
/// It displays enabled instruments in a grid/wrap layout.
class HubScreen extends StatelessWidget {
  final VoidCallback? onFinished;
  const HubScreen({super.key, this.onFinished});

  void _confirmStop(BuildContext context, SimulationState state) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Finalizar Simulación?'),
        content: const Text(
            'Se guardará el registro actual y se detendrá la telemetría.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              state.stopSimulation();
              Navigator.pop(context);
              if (onFinished != null) onFinished!();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child:
                const Text('Finalizar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    final displayItems = state.displayInstruments;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: () => _showActionsMenu(context, state),
            icon: const Icon(LucideIcons.plusCircle, size: 18),
            label: Text('ACCIONES DE CAMPO',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: msiTheme.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 64),
              elevation: 4,
              shadowColor: msiTheme.primary.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PANEL EN VIVO',
                      style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: msiTheme.text.withOpacity(0.4),
                          letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  _TelemetryStatusBadge(),
                ],
              ),
              Row(
                children: [
                  _ColumnSelector(current: state.hubColumns),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = 16.0;
              final colCount = state.hubColumns;
              final itemWidth =
                  (constraints.maxWidth - (spacing * (colCount - 1))) /
                      colCount;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: displayItems.map((inst) {
                  return SizedBox(
                    width: itemWidth,
                    child: HubCell(instrument: inst, key: ValueKey(inst.title)),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _confirmStop(context, state),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFEF2F2),
                foregroundColor: const Color(0xFFEF4444).withOpacity(0.8),
                minimumSize: const Size(double.infinity, 56),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                side: BorderSide(
                    color: const Color(0xFFEF4444).withOpacity(0.1))),
            child: Text('FINALIZAR SESIÓN',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _showActionsMenu(BuildContext context, SimulationState state) {
    final msiTheme = state.theme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: msiTheme.background,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(32), topRight: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ACCIONES DISPONIBLES',
                style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: msiTheme.text,
                    letterSpacing: -0.5)),
            const SizedBox(height: 32),
            _ActionCategoryTile(
              title: 'Eventos Clínicos',
              icon: LucideIcons.zap,
              color: const Color(0xFFD7E2FF),
              onTap: () {
                Navigator.pop(context);
                _showSubActions(context, state, 'Eventos', state.activeEvents);
              },
            ),
            const SizedBox(height: 16),
            _ActionCategoryTile(
              title: 'Mediciones Manuales',
              icon: LucideIcons.gauge,
              color: const Color(0xFFBFD2FD),
              onTap: () {
                Navigator.pop(context);
                _showSubActions(
                    context, state, 'Medición', state.activeMeasurements);
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showSubActions(BuildContext context, SimulationState state,
      String category, List<dynamic> items) {
    final msiTheme = state.theme;
    final isChecklist = category == 'Medición';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setInternalState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: BoxDecoration(
            color: msiTheme.background,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(32), topRight: Radius.circular(32)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(LucideIcons.arrowLeft)),
                      const SizedBox(width: 8),
                      Text(category.toUpperCase(),
                          style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: msiTheme.primary)),
                    ],
                  ),
                  if (isChecklist)
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('LISTO'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final String title =
                        item is ClinicalEvent ? item.title : item.toString();

                    if (isChecklist) {
                      final bool isDone =
                          state.isMeasurementCompleted(item.toString());
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: msiTheme.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: isDone
                                  ? msiTheme.primary.withOpacity(0.3)
                                  : msiTheme.text.withOpacity(0.05)),
                        ),
                        child: CheckboxListTile(
                          value: isDone,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          onChanged: (val) {
                            state.toggleMeasurement(item.toString());
                            setInternalState(() {});
                          },
                          activeColor: msiTheme.primary,
                          checkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          title: Text(title,
                              style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: isDone
                                      ? msiTheme.primary
                                      : msiTheme.text)),
                          secondary: Icon(
                            isDone
                                ? LucideIcons.checkCircle2
                                : LucideIcons.circle,
                            color: isDone
                                ? msiTheme.primary
                                : msiTheme.text.withOpacity(0.2),
                            size: 20,
                          ),
                        ),
                      );
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: msiTheme.card,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: msiTheme.text.withOpacity(0.05)),
                      ),
                      child: ListTile(
                        onTap: () {
                          if (item is ClinicalEvent) {
                            state.recordEvent(item);
                          } else {
                            state.recordAction(category, item.toString());
                          }
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$title registrado con éxito'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: msiTheme.primary,
                            ),
                          );
                        },
                        leading: Icon(LucideIcons.checkCircle2,
                            color: msiTheme.primary, size: 20),
                        title: Text(title,
                            style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: msiTheme.text)),
                        trailing:
                            const Icon(LucideIcons.chevronRight, size: 16),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TelemetryStatusBadge extends StatelessWidget {
  void _showMonitorSelector(BuildContext context) {
    final telemetry = TelemetryService();
    final theme = context.read<SimulationState>().theme;

    if (!telemetry.isConnected && !telemetry.isSearching) {
      telemetry.startSearch();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
        child: ListenableBuilder(
          listenable: telemetry,
          builder: (context, _) {
            final devices = telemetry.discoveredDevices;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SELECCIONAR MONITOR',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: theme.text,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (telemetry.isSearching)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        onPressed: () => telemetry.startSearch(),
                        icon: const Icon(LucideIcons.refreshCw, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                if (devices.isEmpty && !telemetry.isSearching)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('No se encontraron monitores cercanos.'),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final isThisOne =
                            telemetry.connectedDeviceId == device.id;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: theme.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isThisOne
                                  ? theme.primary
                                  : theme.text.withOpacity(0.05),
                              width: isThisOne ? 2 : 1,
                            ),
                          ),
                          child: ListTile(
                            onTap: () async {
                              // Mostrar diálogo de progreso
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => AlertDialog(
                                  content: Row(
                                    children: [
                                      const CircularProgressIndicator(),
                                      const SizedBox(width: 16),
                                      Text('Conectando...',
                                          style: GoogleFonts.manrope()),
                                    ],
                                  ),
                                ),
                              );

                              final success =
                                  await telemetry.connectToMonitor(device.id);
                              Navigator.pop(context); // cerrar diálogo

                              if (success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Monitor conectado correctamente')),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Error al conectar. Inténtalo de nuevo'),
                                      backgroundColor: Colors.red),
                                );
                              }
                              Navigator.pop(context); // cerrar el bottom sheet
                            },
                            leading: Icon(
                              LucideIcons.monitor,
                              color: isThisOne
                                  ? theme.primary
                                  : theme.text.withOpacity(0.3),
                            ),
                            title: Text(
                              device.name.isEmpty
                                  ? 'Monitor Desconocido'
                                  : device.name,
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: theme.text,
                              ),
                            ),
                            subtitle: Text(
                              device.id,
                              style: GoogleFonts.manrope(
                                fontSize: 10,
                                color: theme.text.withOpacity(0.4),
                              ),
                            ),
                            trailing: isThisOne
                                ? const Icon(LucideIcons.checkCircle2,
                                    color: Colors.green)
                                : const Icon(LucideIcons.chevronRight,
                                    size: 16),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 24),
                if (telemetry.isConnected)
                  TextButton.icon(
                    onPressed: () {
                      telemetry.stop();
                      Navigator.pop(context);
                    },
                    icon: const Icon(LucideIcons.unplug,
                        size: 16, color: Colors.red),
                    label: const Text('DESCONECTAR',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w900)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final telemetry = TelemetryService();
    return ListenableBuilder(
      listenable: telemetry,
      builder: (context, _) {
        final isConnected = telemetry.isConnected;
        final isSearching = telemetry.isSearching;

        Color color = Colors.grey;
        String text = 'SIN MONITOR';
        IconData icon = LucideIcons.unplug;

        if (isConnected) {
          color = Colors.green;
          text = 'MONITOR VIVO';
          icon = LucideIcons.radio;
        } else if (isSearching) {
          color = Colors.blue;
          text = 'BUSCANDO...';
          icon = LucideIcons.search;
        }

        return GestureDetector(
          onTap: () => _showMonitorSelector(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 10, color: color),
                const SizedBox(width: 4),
                Text(
                  text,
                  style: GoogleFonts.manrope(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionCategoryTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionCategoryTile(
      {required this.title,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SimulationState>().theme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.text.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: theme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: theme.primary, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
                child: Text(title,
                    style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: theme.text))),
            Icon(LucideIcons.chevronRight,
                size: 20, color: theme.primary.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }
}

/// [HubCell] represents a single instrument tile in the dashboard.
/// It displays the current vital value and provides +/- controls for rapid adjustment.
class HubCell extends StatelessWidget {
  final Instrument instrument;
  const HubCell({required this.instrument, super.key});

  void _showManualInput(BuildContext context, SimulationState state,
      String vitalKey, String title) {
    if (title == 'Tensión Arterial') {
      _showBPManualInput(context, state);
      return;
    }
    if (title == 'Sat% y FR') {
      _showGasesManualInput(context, state);
      return;
    }
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ajustar $title'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'Introduce el valor manual'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null) state.setVital(vitalKey, val);
              Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showGasesManualInput(BuildContext context, SimulationState state) {
    final TextEditingController o2Controller =
        TextEditingController(text: '${state.spo2}');
    final TextEditingController co2Controller =
        TextEditingController(text: '${state.co2}');
    final msiTheme = state.theme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: msiTheme.background,
        title: Text('Ajustar Sat% y FR',
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w900, color: msiTheme.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: o2Controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Sat% (%)',
                labelStyle: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1),
                filled: true,
                fillColor: msiTheme.card,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: co2Controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'FR (rpm)',
                labelStyle: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1),
                filled: true,
                fillColor: msiTheme.card,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final o2 = int.tryParse(o2Controller.text);
              final co2 = int.tryParse(co2Controller.text);
              if (o2 != null) state.setVital('spo2', o2);
              if (co2 != null) state.setVital('co2', co2);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: msiTheme.primary,
                foregroundColor: Colors.white),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showBPManualInput(BuildContext context, SimulationState state) {
    final TextEditingController sysController =
        TextEditingController(text: '${state.sys}');
    final TextEditingController diaController =
        TextEditingController(text: '${state.dia}');
    final msiTheme = state.theme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: msiTheme.background,
        title: Text('Ajustar Tensión Arterial',
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w900, color: msiTheme.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: sysController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'SISTÓLICA (mmHg)',
                labelStyle: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1),
                filled: true,
                fillColor: msiTheme.card,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: diaController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'DIASTÓLICA (mmHg)',
                labelStyle: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1),
                filled: true,
                fillColor: msiTheme.card,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final sys = int.tryParse(sysController.text);
              final dia = int.tryParse(diaController.text);
              if (sys != null) state.setVital('sys', sys);
              if (dia != null) state.setVital('dia', dia);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: msiTheme.primary,
                foregroundColor: Colors.white),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    String title = instrument.title;
    IconData icon = instrument.icon;
    bool isCollapsed = state.isCollapsed(title);

    double scale = 1.0;
    if (state.hubColumns == 2) scale = 0.85;
    if (state.hubColumns == 3) scale = 0.50;

    String val = '--';
    String unit = '';
    String vitalKey = '';
    double step = 1;

    if (title == 'Frecuencia Cardíaca') {
      val = '${state.hr}';
      unit = 'BPM';
      vitalKey = 'hr';
    } else if (title == 'Sat% y FR') {
      val = '${state.spo2}%';
      unit = 'Sat/FR';
      vitalKey = 'spo2';
    } else if (title == 'Temperatura' || title == 'Termómetro') {
      val = '${state.temp.toStringAsFixed(1)}°C';
      unit = 'TEMP';
      vitalKey = 'temp';
      step = 0.1;
    } else if (title == 'Glucosa en Sangre' || title == 'Glucómetro') {
      val = '${state.glucose}';
      unit = 'mg/dL';
      vitalKey = 'glucose';
    } else if (title == 'Tensión Arterial') {
      val = '${state.sys}/${state.dia}';
      unit = 'mmHg';
      vitalKey = 'sys';
    } else if (title == 'Voz') {
      val = 'Pista 1';
      unit = 'IZQ';
    } else if (title == 'Estetoscopio') {
      val = 'Pista 2';
      unit = 'DER';
    }

    if (title == 'Voz') {
      return _VoiceModuleCell(instrument: instrument, scale: scale);
    }
    if (title == 'Estetoscopio') {
      return _StethoscopeModuleCell(instrument: instrument, scale: scale);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: msiTheme.card,
        borderRadius: BorderRadius.circular(28 * scale),
        border: Border.all(color: msiTheme.text.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16 * scale,
            offset: Offset(0, 6 * scale),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => state.toggleCollapse(title),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: 16 * scale, vertical: 14 * scale),
              color: msiTheme.primary.withOpacity(0.03),
              child: Row(
                children: [
                  Icon(icon,
                      color: instrument.textColor ?? msiTheme.primary,
                      size: 20 * scale),
                  SizedBox(width: 10 * scale),
                  Expanded(
                    child: Text(
                      isCollapsed ? title.toUpperCase() : unit,
                      style: GoogleFonts.manrope(
                        fontSize: 11 * scale,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: (instrument.textColor ?? msiTheme.primary)
                            .withOpacity(isCollapsed ? 0.9 : 0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Botón de visibilidad en el monitor (ojo)
                      GestureDetector(
                        onTap: () => state.toggleVisibilityOnMonitor(title),
                        child: Container(
                          padding: EdgeInsets.all(8 * scale),
                          decoration: BoxDecoration(
                            color: instrument.isVisibleOnMonitor
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            instrument.isVisibleOnMonitor
                                ? LucideIcons.eye
                                : LucideIcons.eyeOff,
                            size: 14 * scale,
                            color: instrument.isVisibleOnMonitor
                                ? Colors.blue
                                : Colors.grey,
                          ),
                        ),
                      ),
                      // Botón SYNC si está en modo manual y tiene cambios pendientes
                      if (instrument.isManualTransmission &&
                          instrument.hasPendingSync)
                        GestureDetector(
                          onTap: () => state.syncInstrument(title),
                          child: Container(
                            margin: EdgeInsets.only(right: 8 * scale),
                            padding: EdgeInsets.symmetric(
                                horizontal: 10 * scale, vertical: 6 * scale),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12 * scale),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.3),
                                  blurRadius: 8 * scale,
                                  offset: Offset(0, 2 * scale),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(LucideIcons.send,
                                    color: Colors.white, size: 12 * scale),
                                if (scale > 0.6) ...[
                                  SizedBox(width: 4 * scale),
                                  Text(
                                    'SYNC',
                                    style: GoogleFonts.manrope(
                                      fontSize: 8 * scale,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      // Botón de modo manual/automático
                      GestureDetector(
                        onTap: () => state.toggleTransmissionMode(title),
                        child: Container(
                          padding: EdgeInsets.all(8 * scale),
                          decoration: BoxDecoration(
                            color: instrument.isManualTransmission
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.green.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            instrument.isManualTransmission
                                ? LucideIcons.hand
                                : LucideIcons.zap,
                            size: 14 * scale,
                            color: instrument.isManualTransmission
                                ? Colors.orange
                                : Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: 8 * scale),
                  Icon(
                    isCollapsed
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronUp,
                    size: 16 * scale,
                    color: msiTheme.primary.withOpacity(0.3),
                  ),
                ],
              ),
            ),
          ),
          if (!isCollapsed) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20 * scale, 12 * scale, 20 * scale, 20 * scale),
              child: Column(
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 11 * scale,
                      fontWeight: FontWeight.w900,
                      color: msiTheme.text.withOpacity(0.4),
                    ),
                  ),
                  SizedBox(height: 4 * scale),
                  GestureDetector(
                    onTap: () => vitalKey.isNotEmpty
                        ? _showManualInput(context, state, vitalKey, title)
                        : null,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        children: [
                          Text(
                            val,
                            style: GoogleFonts.manrope(
                              fontSize: 52 * scale,
                              fontWeight: FontWeight.w900,
                              color: instrument.textColor ?? msiTheme.primary,
                              height: 1.1,
                            ),
                          ),
                          if (title == 'Sat% y FR')
                            Text(
                              '${state.co2} FR',
                              style: GoogleFonts.manrope(
                                fontSize: 24 * scale,
                                fontWeight: FontWeight.w800,
                                color:
                                    (instrument.textColor ?? msiTheme.primary)
                                        .withOpacity(0.6),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16 * scale),
                  if (title == 'Sat% y FR')
                    Column(
                      children: [
                        _AdjustRow(
                            label: 'Sat',
                            value: state.spo2,
                            scale: scale,
                            onPlus: () =>
                                state.setVital('spo2', state.spo2 + 1),
                            onMinus: () =>
                                state.setVital('spo2', state.spo2 - 1)),
                        SizedBox(height: 12 * scale),
                        _AdjustRow(
                            label: 'FR',
                            value: state.co2,
                            scale: scale,
                            onPlus: () => state.setVital('co2', state.co2 + 1),
                            onMinus: () =>
                                state.setVital('co2', state.co2 - 1)),
                      ],
                    )
                  else if (title == 'Tensión Arterial')
                    Column(
                      children: [
                        _AdjustRow(
                            label: 'SIS',
                            value: state.sys,
                            scale: scale,
                            onPlus: () => state.setVital('sys', state.sys + 5),
                            onMinus: () =>
                                state.setVital('sys', state.sys - 5)),
                        SizedBox(height: 12 * scale),
                        _AdjustRow(
                            label: 'DIA',
                            value: state.dia,
                            scale: scale,
                            onPlus: () => state.setVital('dia', state.dia + 5),
                            onMinus: () =>
                                state.setVital('dia', state.dia - 5)),
                      ],
                    )
                  else if (vitalKey.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _MiniAdjustBtn(
                            icon: LucideIcons.minus,
                            scale: scale,
                            onTap: () => state.setVital(
                                vitalKey,
                                (vitalKey == 'temp'
                                        ? state.temp
                                        : (vitalKey == 'hr'
                                            ? state.hr
                                            : state.glucose)) -
                                    step)),
                        SizedBox(width: 32 * scale),
                        _MiniAdjustBtn(
                            icon: LucideIcons.plus,
                            scale: scale,
                            onTap: () => state.setVital(
                                vitalKey,
                                (vitalKey == 'temp'
                                        ? state.temp
                                        : (vitalKey == 'hr'
                                            ? state.hr
                                            : state.glucose)) +
                                    step)),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdjustRow extends StatelessWidget {
  final String label;
  final num value;
  final double scale;
  final VoidCallback onPlus;
  final VoidCallback onMinus;
  const _AdjustRow(
      {required this.label,
      required this.value,
      required this.scale,
      required this.onPlus,
      required this.onMinus});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SimulationState>().theme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 30 * scale,
          child: Text(label,
              style: TextStyle(
                  fontSize: 11 * scale,
                  fontWeight: FontWeight.w900,
                  color: theme.primary.withOpacity(0.4))),
        ),
        _MiniAdjustBtn(icon: LucideIcons.minus, scale: scale, onTap: onMinus),
        SizedBox(width: 12 * scale),
        _MiniAdjustBtn(icon: LucideIcons.plus, scale: scale, onTap: onPlus),
      ],
    );
  }
}

class _MiniAdjustBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double scale;
  const _MiniAdjustBtn(
      {required this.icon, required this.onTap, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SimulationState>().theme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(12 * scale),
        decoration: BoxDecoration(
            color: theme.accent.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12 * scale)),
        child: Icon(icon, size: 22 * scale, color: theme.primary),
      ),
    );
  }
}

class _TransmitBtn extends StatelessWidget {
  final double scale;
  final VoidCallback onTap;
  const _TransmitBtn({required this.scale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SimulationState>().theme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 12 * scale),
        decoration: BoxDecoration(
          color: theme.primary,
          borderRadius: BorderRadius.circular(16 * scale),
          boxShadow: [
            BoxShadow(
              color: theme.primary.withOpacity(0.3),
              blurRadius: 10 * scale,
              offset: Offset(0, 4 * scale),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.send, color: Colors.white, size: 14 * scale),
            SizedBox(width: 8 * scale),
            Text(
              'TRANSMITIR CAMBIOS',
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 10 * scale,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showVolumeMenu(BuildContext context, SimulationState state, bool isLeft) {
  final theme = state.theme;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32), topRight: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
              isLeft
                  ? 'Volumen Canal Izquierdo (Voz)'
                  : 'Volumen Canal Derecho (Estetoscopio)',
              style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 24),
          ListenableBuilder(
            listenable: state,
            builder: (context, _) {
              double currentVol = isLeft ? state.leftVolume : state.rightVolume;
              return Column(
                children: [
                  Slider(
                    value: currentVol,
                    activeColor: theme.primary,
                    onChanged: (val) => isLeft
                        ? state.setLeftVolume(val)
                        : state.setRightVolume(val),
                  ),
                  Text('${(currentVol * 100).round()}%',
                      style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          color: theme.primary)),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

class _ColumnSelector extends StatelessWidget {
  final int current;
  const _ColumnSelector({required this.current});

  @override
  Widget build(BuildContext context) {
    final state = context.read<SimulationState>();
    final msiTheme = state.theme;
    final layoutIcons = {
      1: LucideIcons.square,
      2: LucideIcons.layoutGrid,
      3: LucideIcons.grid
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: msiTheme.accent, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [1, 2, 3]
            .map((n) => GestureDetector(
                  onTap: () => state.setHubColumns(n),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                        color: current == n
                            ? msiTheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(layoutIcons[n],
                        size: 16,
                        color: current == n
                            ? msiTheme.background
                            : msiTheme.primary),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _VoiceModuleCell extends StatelessWidget {
  final Instrument instrument;
  final double scale;
  const _VoiceModuleCell({required this.instrument, required this.scale});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    final title = instrument.title;
    final isCollapsed = state.isCollapsed(title);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: msiTheme.card,
        borderRadius: BorderRadius.circular(28 * scale),
        border: Border.all(color: msiTheme.text.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16 * scale,
              offset: Offset(0, 6 * scale))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => state.toggleCollapse(title),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: 16 * scale, vertical: 14 * scale),
              color: msiTheme.primary.withOpacity(0.03),
              child: Row(
                children: [
                  Icon(instrument.icon,
                      color: instrument.textColor ?? msiTheme.primary,
                      size: 20 * scale),
                  SizedBox(width: 10 * scale),
                  Expanded(
                      child: Text(isCollapsed ? 'VOZ' : 'VOZ (IZQ)',
                          style: GoogleFonts.manrope(
                              fontSize: 11 * scale,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: (instrument.textColor ?? msiTheme.primary)
                                  .withOpacity(isCollapsed ? 0.9 : 0.5)))),
                  Icon(
                    isCollapsed
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronUp,
                    size: 16 * scale,
                    color: msiTheme.primary.withOpacity(0.3),
                  ),
                ],
              ),
            ),
          ),
          if (!isCollapsed)
            Padding(
              padding: EdgeInsets.all(20 * scale),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('VOLUMEN:',
                          style: GoogleFonts.manrope(
                              fontSize: 10 * scale,
                              fontWeight: FontWeight.bold,
                              color: msiTheme.text.withOpacity(0.4))),
                      GestureDetector(
                        onTap: () => _showVolumeMenu(context, state, true),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 8 * scale, vertical: 2 * scale),
                          decoration: BoxDecoration(
                            color: msiTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4 * scale),
                          ),
                          child: Text(
                            '${(state.leftVolume * 100).round()}%',
                            style: GoogleFonts.manrope(
                                fontSize: 10 * scale,
                                fontWeight: FontWeight.w900,
                                color: msiTheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16 * scale),
                  Row(
                    children: [
                      Expanded(
                        child: _SoundBtn(
                          label: 'REPRODUCIR',
                          icon: LucideIcons.playCircle,
                          scale: scale,
                          onTap: () => state.playLeft(),
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      Expanded(
                        child: _PTTBtn(scale: scale),
                      ),
                    ],
                  ),
                  SizedBox(height: 8 * scale),
                  _SoundBtn(
                    label: 'DETENER',
                    icon: LucideIcons.square,
                    scale: scale,
                    isStop: true,
                    onTap: () => state.stopSound(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StethoscopeModuleCell extends StatelessWidget {
  final Instrument instrument;
  final double scale;
  const _StethoscopeModuleCell({required this.instrument, required this.scale});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    final title = instrument.title;
    final isCollapsed = state.isCollapsed(title);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: msiTheme.card,
        borderRadius: BorderRadius.circular(28 * scale),
        border: Border.all(color: msiTheme.text.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16 * scale,
              offset: Offset(0, 6 * scale))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => state.toggleCollapse(title),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: 16 * scale, vertical: 14 * scale),
              color: msiTheme.primary.withOpacity(0.03),
              child: Row(
                children: [
                  Icon(instrument.icon,
                      color: instrument.textColor ?? msiTheme.primary,
                      size: 20 * scale),
                  SizedBox(width: 10 * scale),
                  Expanded(
                      child: Text(
                          isCollapsed ? 'ESTETOSCOPIO' : 'ESTETOSCOPIO (DER)',
                          style: GoogleFonts.manrope(
                              fontSize: 11 * scale,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: (instrument.textColor ?? msiTheme.primary)
                                  .withOpacity(isCollapsed ? 0.9 : 0.5)))),
                  Icon(
                    isCollapsed
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronUp,
                    size: 16 * scale,
                    color: msiTheme.primary.withOpacity(0.3),
                  ),
                ],
              ),
            ),
          ),
          if (!isCollapsed)
            Padding(
              padding: EdgeInsets.all(20 * scale),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('VOLUMEN:',
                          style: GoogleFonts.manrope(
                              fontSize: 10 * scale,
                              fontWeight: FontWeight.bold,
                              color: msiTheme.text.withOpacity(0.4))),
                      GestureDetector(
                        onTap: () => _showVolumeMenu(context, state, false),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 8 * scale, vertical: 2 * scale),
                          decoration: BoxDecoration(
                            color: msiTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4 * scale),
                          ),
                          child: Text(
                            '${(state.rightVolume * 100).round()}%',
                            style: GoogleFonts.manrope(
                                fontSize: 10 * scale,
                                fontWeight: FontWeight.w900,
                                color: msiTheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16 * scale),
                  Row(
                    children: [
                      Expanded(
                        child: _SoundBtn(
                          label: 'LATIDOS',
                          icon: LucideIcons.heartPulse,
                          scale: scale,
                          onTap: () => state.playRight(),
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      Expanded(
                        child: _SoundBtn(
                          label: 'AMBOS',
                          icon: LucideIcons.copy,
                          scale: scale,
                          onTap: () => state.playBothRight(),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8 * scale),
                  _SoundBtn(
                    label: 'DETENER',
                    icon: LucideIcons.square,
                    scale: scale,
                    isStop: true,
                    onTap: () => state.stopSound(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SoundBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final double scale;
  final VoidCallback onTap;
  final bool isStop;
  const _SoundBtn({
    required this.label,
    required this.icon,
    required this.scale,
    required this.onTap,
    this.isStop = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SimulationState>().theme;
    Color bgColor = theme.accent;
    Color borderColor = theme.primary.withOpacity(0.1);
    Color contentColor = theme.primary;

    if (isStop) {
      bgColor = Colors.red.withOpacity(0.1);
      borderColor = Colors.red.withOpacity(0.2);
      contentColor = Colors.red;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12 * scale),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18 * scale, color: contentColor),
            SizedBox(height: 4 * scale),
            Text(label,
                style: GoogleFonts.manrope(
                    fontSize: 8 * scale,
                    fontWeight: FontWeight.w900,
                    color: contentColor)),
          ],
        ),
      ),
    );
  }
}

class _PTTBtn extends StatelessWidget {
  final double scale;
  const _PTTBtn({required this.scale});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final theme = state.theme;
    final isActive = state.isPTTActive;

    Color bgColor = isActive ? theme.primary.withOpacity(0.2) : theme.accent;
    Color borderColor =
        isActive ? theme.primary : theme.primary.withOpacity(0.1);
    Color contentColor = theme.primary;

    return GestureDetector(
      onTapDown: (_) => state.startPTT(),
      onTapUp: (_) => state.stopPTT(),
      onTapCancel: () => state.stopPTT(),
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12 * scale),
          border: Border.all(color: borderColor, width: isActive ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(isActive ? LucideIcons.mic : LucideIcons.micOff,
                size: 18 * scale, color: contentColor),
            SizedBox(height: 4 * scale),
            Text('PTT VIVO',
                style: GoogleFonts.manrope(
                    fontSize: 8 * scale,
                    fontWeight: FontWeight.w900,
                    color: contentColor)),
          ],
        ),
      ),
    );
  }
}
