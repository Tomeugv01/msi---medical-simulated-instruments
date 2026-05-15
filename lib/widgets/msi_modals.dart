import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../providers/simulation_provider.dart';
import '../models/instrumental_models.dart';

/// [ModalShell] provides the consistent look and feel (rounded top corners, title bar)
/// for all bottom-sheet modals in the app.
class ModalShell extends StatelessWidget {
  final String title;
  final Widget child;
  const ModalShell({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: msiTheme.background,
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32), topRight: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: msiTheme.card,
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32), topRight: Radius.circular(32)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: msiTheme.primary)),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(LucideIcons.x, color: msiTheme.text)),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// [ConfigModal] allows global configuration of instruments, themes, and BLE hardware.
class ConfigModal extends StatelessWidget {
  const ConfigModal({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;

    return ModalShell(
      title: 'Configuración Permanente',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const ThemeSelector(),
          const SizedBox(height: 32),
          const InstrumentReorderList(),
          const SizedBox(height: 24),
          const BluetoothShortCard(),
          const SizedBox(height: 24),
          const ActionManagerCard(type: 'events', title: 'Eventos Clínicos'),
          const SizedBox(height: 16),
          const ActionManagerCard(
              type: 'measurements', title: 'Mediciones Manuales'),
          const SizedBox(height: 24),
          const NotesBox(),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

class BluetoothModal extends StatelessWidget {
  const BluetoothModal({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;

    return ModalShell(
      title: 'Conexión Bluetooth',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: msiTheme.card, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Estado del Dispositivo',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: msiTheme.text)),
                    if (state.isScanning)
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: msiTheme.primary)),
                  ],
                ),
                const SizedBox(height: 16),
                if (state.bleStatus == DeviceConnectionState.disconnected)
                  ElevatedButton.icon(
                    onPressed: () => state.startScan(),
                    icon: const Icon(LucideIcons.search, size: 16),
                    label: Text(state.isScanning
                        ? 'Escaneando...'
                        : 'Buscar Dispositivos'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: msiTheme.primary,
                        foregroundColor: msiTheme.background,
                        minimumSize: const Size(double.infinity, 48)),
                  )
                else
                  Row(
                    children: [
                      const Icon(LucideIcons.checkCircle2,
                          color: Colors.green, size: 20),
                      const SizedBox(width: 12),
                      const Text('Conectado',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: 16)),
                      const Spacer(),
                      TextButton(
                          onPressed: () => state.disconnect(),
                          child: Text('Desconectar',
                              style: TextStyle(color: msiTheme.primary))),
                    ],
                  ),
              ],
            ),
          ),
          if (state.devices.isNotEmpty && !state.isConnected) ...[
            const SizedBox(height: 24),
            Text('DISPOSITIVOS DISPONIBLES',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: msiTheme.text.withOpacity(0.5),
                    letterSpacing: 1)),
            const SizedBox(height: 12),
            ...state.devices.map((device) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: msiTheme.card,
                      borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    title: Text(device.name.isEmpty ? 'HMI-UNID' : device.name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: msiTheme.text)),
                    trailing: ElevatedButton(
                      onPressed: () => state.connect(device.id),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: msiTheme.accent,
                          foregroundColor: msiTheme.primary),
                      child: const Text('Vincular'),
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

/// [EditPresetModal] is a complex modal for creating or editing instrumental/clinical presets.
/// It manages internal state for the preset being edited before saving to the provider.
class EditPresetModal extends StatefulWidget {
  final InstrumentalPreset? preset;
  final bool isClinical;
  const EditPresetModal({super.key, this.preset, this.isClinical = false});

  @override
  State<EditPresetModal> createState() => _EditPresetModalState();
}

class _EditPresetModalState extends State<EditPresetModal> {
  late TextEditingController _titleController;
  late IconData _selectedIcon;
  late List<String> _selectedInstruments;
  late List<ClinicalEvent> _selectedEvents;
  late List<String> _selectedMeasurements;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.preset?.title ?? '');
    _selectedIcon = widget.preset?.icon ??
        (widget.isClinical ? LucideIcons.clipboardList : LucideIcons.wrench);
    _selectedInstruments =
        List<String>.from(widget.preset?.instrumentTitles ?? []);
    _selectedEvents =
        List<ClinicalEvent>.from(widget.preset?.allowedEvents ?? []);
    _selectedMeasurements =
        List<String>.from(widget.preset?.allowedMeasurements ?? []);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;

    final availableInstruments = state.instruments
        .map((i) => i.title)
        .where((t) => !_selectedInstruments.contains(t))
        .toList();

    return ModalShell(
      title: widget.preset == null ? 'Nueva Configuración' : 'Editar Caso',
      child: Column(
        children: [
          Expanded(
            child: ReorderableListView(
              padding: const EdgeInsets.all(24),
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _selectedInstruments.removeAt(oldIndex);
                  _selectedInstruments.insert(newIndex, item);
                });
              },
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Nombre del Caso o Formación',
                      labelStyle: TextStyle(
                          color: msiTheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                      filled: true,
                      fillColor: msiTheme.card,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 20),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text('ELIGE UN ICONO REPRESENTATIVO',
                      style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: msiTheme.text.withOpacity(0.5),
                          letterSpacing: 1.5)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: iconMap.values.map((icon) {
                      bool isSelected = _selectedIcon == icon;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedIcon = icon),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                isSelected ? msiTheme.primary : msiTheme.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: isSelected
                                    ? msiTheme.primary
                                    : msiTheme.text.withOpacity(0.05)),
                          ),
                          child: Icon(icon,
                              color:
                                  isSelected ? Colors.white : msiTheme.primary,
                              size: 24),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('INSTRUMENTOS ACTIVOS (ORDENABLE)',
                          style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: msiTheme.text.withOpacity(0.5),
                              letterSpacing: 1.5)),
                      const Icon(LucideIcons.gripVertical,
                          size: 14, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
              children: [
                ..._selectedInstruments.asMap().entries.map((entry) {
                  final String title = entry.value;
                  final inst =
                      state.instruments.firstWhere((i) => i.title == title);
                  return Container(
                    key: ValueKey('sel_$title'),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                        color: msiTheme.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: msiTheme.primary.withOpacity(0.1))),
                    child: ListTile(
                      leading:
                          Icon(inst.icon, color: msiTheme.primary, size: 20),
                      title: Text(title,
                          style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: msiTheme.text)),
                      trailing: IconButton(
                        icon: const Icon(LucideIcons.minusCircle,
                            color: Colors.redAccent, size: 20),
                        onPressed: () => setState(
                            () => _selectedInstruments.removeAt(entry.key)),
                      ),
                    ),
                  );
                }),

                // Static section for adding new ones - but ReorderableListView children must be keyed
                Container(
                  key: const ValueKey('add_section_header'),
                  padding: const EdgeInsets.only(top: 24, bottom: 12),
                  child: Text('AÑADIR INSTRUMENTOS',
                      style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: msiTheme.text.withOpacity(0.5),
                          letterSpacing: 1.5)),
                ),

                ...availableInstruments.map((title) {
                  final inst =
                      state.instruments.firstWhere((i) => i.title == title);
                  return Container(
                    key: ValueKey('avail_$title'),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                        color: msiTheme.card.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: Icon(inst.icon,
                          color: msiTheme.primary.withOpacity(0.3), size: 20),
                      title: Text(title,
                          style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: msiTheme.text.withOpacity(0.6))),
                      trailing: IconButton(
                        icon: Icon(LucideIcons.plusCircle,
                            color: msiTheme.primary, size: 20),
                        onPressed: () =>
                            setState(() => _selectedInstruments.add(title)),
                      ),
                    ),
                  );
                }),

                Container(
                  key: const ValueKey('actions_section_header'),
                  padding: const EdgeInsets.only(top: 32, bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CONFIGURACIÓN DE ACCIONES',
                          style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: msiTheme.primary,
                              letterSpacing: 1.5)),
                      const SizedBox(height: 8),
                      Text(
                          'Selecciona qué eventos y mediciones estarán habilitados.',
                          style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: msiTheme.text.withOpacity(0.6))),
                    ],
                  ),
                ),

                _CompactActionSelector(
                  key: const ValueKey('compact_events'),
                  title: 'EVENTOS CLÍNICOS',
                  icon: LucideIcons.zap,
                  allOptions: state.events,
                  selectedOptions: _selectedEvents,
                  onChanged: (newList) => setState(
                      () => _selectedEvents = newList.cast<ClinicalEvent>()),
                ),

                _CompactActionSelector(
                  key: const ValueKey('compact_measurements'),
                  title: 'MEDICIONES MANUALES',
                  icon: LucideIcons.gauge,
                  allOptions: state.measurements,
                  selectedOptions: _selectedMeasurements,
                  onChanged: (newList) => setState(
                      () => _selectedMeasurements = newList.cast<String>()),
                ),

                const SizedBox(key: ValueKey('spacer_bottom'), height: 100),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: ElevatedButton(
              onPressed: () {
                if (_titleController.text.isEmpty) return;
                final newPreset = InstrumentalPreset(
                  id: widget.preset?.id ??
                      DateTime.now().millisecondsSinceEpoch.toString(),
                  title: _titleController.text,
                  icon: _selectedIcon,
                  instrumentTitles: _selectedInstruments,
                  isClinical: widget.preset?.isClinical ?? widget.isClinical,
                  allowedEvents: _selectedEvents,
                  allowedMeasurements: _selectedMeasurements,
                );
                if (widget.preset == null) {
                  state.addPreset(newPreset);
                } else {
                  state.updatePreset(newPreset);
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: msiTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text('GUARDAR CONFIGURACIÓN',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

// Sub-widgets needed for the modals
class ThemeSelector extends StatelessWidget {
  const ThemeSelector({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TEMA VISUAL',
            style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: msiTheme.text.withOpacity(0.5),
                letterSpacing: 1.5)),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: appThemes.length,
            itemBuilder: (context, index) {
              final t = appThemes[index];
              bool isSelected = state.themeIndex == index;
              return GestureDetector(
                onTap: () => state.setTheme(index),
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? (msiTheme.text.withOpacity(0.6))
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: ClipOval(
                        child: CustomPaint(
                          painter: DiagonalSplitPainter(
                            color1: t.primary,
                            color2: t.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class DiagonalSplitPainter extends CustomPainter {
  final Color color1;
  final Color color2;

  DiagonalSplitPainter({required this.color1, required this.color2});

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()..color = color1;
    final paint2 = Paint()..color = color2;

    final path1 = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();

    final path2 = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path1, paint1);
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class InstrumentReorderList extends StatelessWidget {
  const InstrumentReorderList({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('INSTRUMENTOS DISPONIBLES',
                style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: msiTheme.text.withOpacity(0.5),
                    letterSpacing: 1.5)),
            const Icon(LucideIcons.gripVertical, size: 14, color: Colors.grey),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: state.instruments.length * 70.0,
          child: ReorderableListView(
            physics: const NeverScrollableScrollPhysics(),
            onReorder: state.reorderInstruments,
            children: state.instruments.asMap().entries.map((entry) {
              final index = entry.key;
              final inst = entry.value;
              return Container(
                key: ValueKey('main_reorder_${inst.title}'),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                    color: msiTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: msiTheme.text.withOpacity(0.05))),
                child: ListTile(
                  leading: Icon(inst.icon, color: msiTheme.primary, size: 20),
                  title: GestureDetector(
                    onTap: () => _showColorPicker(context, state, index, inst),
                    child: Text(inst.title,
                        style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: inst.textColor ?? msiTheme.text)),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                          value: inst.isEnabled,
                          onChanged: (_) => state.toggleInstrument(index),
                          activeColor: msiTheme.primary),
                      const SizedBox(width: 8),
                      const Icon(LucideIcons.gripVertical,
                          size: 18, color: Colors.grey),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _showColorPicker(
      BuildContext context, SimulationState state, int index, Instrument inst) {
    final msiTheme = state.theme;
    final List<Color?> colors = [
      null, // Default
      Colors.redAccent,
      Colors.greenAccent[700],
      Colors.blueAccent,
      Colors.orangeAccent,
      Colors.purpleAccent,
      Colors.pinkAccent,
      const Color(0xFF003F87), // Deep Blue
      const Color(0xFFffd700), // Gold
      Colors.teal,
      // Tonos Pastel
      const Color(0xFFFFB3BA), // Rojo Pastel
      const Color(0xFFFFDFBA), // Naranja Pastel
      const Color(0xFFFFFFBA), // Amarillo Pastel
      const Color(0xFFBAFFC9), // Verde Pastel
      const Color(0xFFBAE1FF), // Azul Pastel
      const Color(0xFFE0BBE4), // Púrpura Pastel
      const Color(0xFFFFC8DD), // Rosa Pastel
      const Color(0xFFA2D2FF), // Azul Cielo Suave
      const Color(0xFFB9FBC0), // Verde Menta
      const Color(0xFFF3E5F5), // Lavanda Pastel
      const Color(0xFFE8F5E9), // Menta Pastel
      const Color(0xFFFFF3E0), // Melocotón Pastel
      const Color(0xFFF1F8E9), // Lima Pastel
      const Color(0xFFE1F5FE), // Celeste Pastel
      const Color(0xFFFCE4EC), // Rosa Pálido
      const Color(0xFFD1C4E9), // Violeta Pastel
      const Color(0xFFFFE0B2), // Albaricoque Pastel
      const Color(0xFFDCEDC8), // Té Verde Pastel
      const Color(0xFFB2EBF2), // Cian Pastel
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: msiTheme.background,
        title: Text('Color para ${inst.title}',
            style:
                GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 16)),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((color) {
            return GestureDetector(
              onTap: () {
                state.setInstrumentColor(index, color);
                Navigator.pop(context);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color ?? msiTheme.text,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (inst.textColor == color)
                        ? msiTheme.primary
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: color == null
                    ? const Icon(LucideIcons.ban, size: 20, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cerrar', style: TextStyle(color: msiTheme.primary))),
        ],
      ),
    );
  }
}

class BluetoothShortCard extends StatelessWidget {
  const BluetoothShortCard({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    return Container(
      decoration: BoxDecoration(
        color: msiTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: msiTheme.text.withOpacity(0.05)),
      ),
      child: ListTile(
        onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const BluetoothModal()),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: state.isConnected
                  ? Colors.blue.withOpacity(0.1)
                  : msiTheme.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(LucideIcons.bluetooth,
              color: state.isConnected
                  ? Colors.blue
                  : msiTheme.primary.withOpacity(0.3)),
        ),
        title: Text('HARDWARE EXTERNO',
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1,
                color: msiTheme.text.withOpacity(0.4))),
        subtitle: Text(
            state.isConnected ? 'Dispositivo Vinculado' : 'Sin conexión activa',
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: state.isConnected ? Colors.blue : msiTheme.text)),
        trailing: Icon(LucideIcons.chevronRight,
            size: 18, color: msiTheme.primary.withOpacity(0.3)),
      ),
    );
  }
}

class NotesBox extends StatefulWidget {
  const NotesBox({super.key});

  @override
  State<NotesBox> createState() => _NotesBoxState();
}

class _NotesBoxState extends State<NotesBox> {
  late TextEditingController _supController;
  late TextEditingController _stdController;

  @override
  void initState() {
    super.initState();
    final state = context.read<SimulationState>();
    _supController = TextEditingController(text: state.supervisor);
    _stdController = TextEditingController(text: state.student);
  }

  @override
  void dispose() {
    _supController.dispose();
    _stdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CONFIGURACIÓN DE ENTRENAMIENTO',
            style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: msiTheme.text.withOpacity(0.5),
                letterSpacing: 1.5)),
        const SizedBox(height: 16),
        TextField(
          onChanged: (v) => state.setSessionInfo(supervisor: v),
          controller: _supController,
          decoration: InputDecoration(
            labelText: 'SUPERVISOR',
            labelStyle: GoogleFonts.manrope(
                fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
            filled: true,
            fillColor: msiTheme.card,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            prefixIcon: Icon(LucideIcons.userCheck,
                size: 18, color: msiTheme.primary.withOpacity(0.3)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (v) => state.setSessionInfo(student: v),
          controller: _stdController,
          decoration: InputDecoration(
            labelText: 'ESTUDIANTE / EQUIPO',
            labelStyle: GoogleFonts.manrope(
                fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
            filled: true,
            fillColor: msiTheme.card,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            prefixIcon: Icon(LucideIcons.users,
                size: 18, color: msiTheme.primary.withOpacity(0.3)),
          ),
        ),
      ],
    );
  }
}

class ActionManagerCard extends StatelessWidget {
  final String type;
  final String title;
  const ActionManagerCard({super.key, required this.type, required this.title});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    final items = type == 'events' ? state.events : state.measurements;
    final icon = type == 'events' ? LucideIcons.zap : LucideIcons.gauge;

    return Container(
      decoration: BoxDecoration(
        color: msiTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: msiTheme.text.withOpacity(0.05)),
      ),
      child: ListTile(
        onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => ActionListModal(type: type, title: title)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: msiTheme.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: msiTheme.primary.withOpacity(0.6)),
        ),
        title: Text(title.toUpperCase(),
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1,
                color: msiTheme.text.withOpacity(0.4))),
        subtitle: Text('${items.length} elementos configurados',
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: msiTheme.text)),
        trailing: Icon(LucideIcons.chevronRight,
            size: 18, color: msiTheme.primary.withOpacity(0.3)),
      ),
    );
  }
}

class ActionListModal extends StatelessWidget {
  final String type;
  final String title;
  const ActionListModal({super.key, required this.type, required this.title});

  @override
  Widget build(BuildContext context) {
    return ModalShell(
      title: 'Gestionar $title',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ActionListManager(type: type, title: 'MODIFICAR LISTADO ACTUAL'),
        ],
      ),
    );
  }
}

class ActionListManager extends StatelessWidget {
  final String type;
  final String title;
  const ActionListManager({super.key, required this.type, required this.title});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final theme = state.theme;
    final items = type == 'events' ? state.events : state.measurements;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: theme.text.withOpacity(0.5),
                    letterSpacing: 1.5)),
            IconButton(
              icon:
                  Icon(LucideIcons.plusCircle, size: 20, color: theme.primary),
              onPressed: () => _showAddDialog(context, state),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.text.withOpacity(0.05)),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final String displayTitle =
                  item is ClinicalEvent ? item.title : item.toString();

              return ListTile(
                title: Text(displayTitle,
                    style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.text)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.edit3,
                          size: 16, color: Colors.grey),
                      onPressed: () => _showAddDialog(context, state,
                          index: index, initialValue: item),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.trash2,
                          size: 16, color: Colors.grey),
                      onPressed: () {
                        if (type == 'events') {
                          state.deleteEvent(index);
                        } else {
                          state.deleteMeasurement(index);
                        }
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context, SimulationState state,
      {int? index, dynamic initialValue}) {
    final titleController = TextEditingController(
        text: initialValue is ClinicalEvent
            ? initialValue.title
            : initialValue?.toString() ?? '');
    final theme = state.theme;
    final isEditing = index != null;

    Map<String, double> healthEffects = initialValue is ClinicalEvent
        ? Map<String, double>.from(initialValue.healthEffects)
        : {};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: theme.background,
          title: Text(isEditing ? 'Editar Acción' : 'Añadir Nuevo',
              style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w900, color: theme.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Nombre de la acción',
                    filled: true,
                    fillColor: theme.card,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                if (type == 'events') ...[
                  const SizedBox(height: 20),
                  Text('EFECTOS CLÍNICOS',
                      style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: theme.primary)),
                  const SizedBox(height: 12),
                  ..._buildEffectPickers(theme, healthEffects, setDialogState),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            TextButton(
              onPressed: () {
                if (titleController.text.isNotEmpty) {
                  if (type == 'events') {
                    final newEvent = ClinicalEvent(
                        title: titleController.text,
                        healthEffects: healthEffects);
                    if (isEditing) {
                      state.updateEvent(index, newEvent);
                    } else {
                      state.addEvent(newEvent);
                    }
                  } else {
                    if (isEditing) {
                      state.updateMeasurement(index, titleController.text);
                    } else {
                      state.addMeasurement(titleController.text);
                    }
                  }
                  Navigator.pop(context);
                }
              },
              child: Text(isEditing ? 'Guardar' : 'Añadir',
                  style: TextStyle(color: theme.primary)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEffectPickers(
      MSITheme theme, Map<String, double> effects, StateSetter setDialogState) {
    final vits = [
      {'key': 'hr', 'label': 'FC (BPM)'},
      {'key': 'spo2', 'label': 'SpO2 (%)'},
      {'key': 'resp', 'label': 'FR (/min)'},
      {'key': 'temp', 'label': 'Temp (°C)'},
      {'key': 'glucose', 'label': 'Glu (mg/dL)'},
      {'key': 'sys', 'label': 'PAS (mmHg)'},
    ];

    return vits.map((v) {
      final key = v['key']!;
      final label = v['label']!;
      final value = effects[key] ?? 0.0;

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold))),
            IconButton(
              icon: const Icon(LucideIcons.minusCircle, size: 20),
              onPressed: () => setDialogState(
                  () => effects[key] = value - (key == 'temp' ? 0.1 : 1.0)),
            ),
            SizedBox(
              width: 50,
              child: Text(
                value > 0
                    ? '+$value'
                    : value.toStringAsFixed(key == 'temp' ? 1 : 0),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: value == 0
                        ? Colors.grey
                        : (value > 0 ? Colors.green : Colors.red)),
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.plusCircle, size: 20),
              onPressed: () => setDialogState(
                  () => effects[key] = value + (key == 'temp' ? 0.1 : 1.0)),
            ),
          ],
        ),
      );
    }).toList();
  }
}

class _CompactActionSelector extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<dynamic> allOptions;
  final List<dynamic> selectedOptions;
  final Function(List<dynamic>) onChanged;

  const _CompactActionSelector({
    super.key,
    required this.title,
    required this.icon,
    required this.allOptions,
    required this.selectedOptions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SimulationState>().theme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.text.withOpacity(0.05)),
      ),
      child: ListTile(
        onTap: () => _showSelectionDialog(context, theme),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: theme.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: theme.primary, size: 20),
        ),
        title: Text(title,
            style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: theme.text.withOpacity(0.4),
                letterSpacing: 1)),
        subtitle: Text(
          selectedOptions.isEmpty
              ? 'Ninguna seleccionada'
              : '${selectedOptions.length} seleccionadas',
          style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800, fontSize: 13, color: theme.text),
        ),
        trailing: Icon(LucideIcons.chevronRight,
            size: 18, color: theme.primary.withOpacity(0.3)),
      ),
    );
  }

  void _showSelectionDialog(BuildContext context, MSITheme msiTheme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: msiTheme.background,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(32), topRight: Radius.circular(32)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: msiTheme.card,
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title,
                        style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: msiTheme.primary)),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon:
                            const Icon(LucideIcons.check, color: Colors.green)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: allOptions.length,
                  itemBuilder: (context, index) {
                    final item = allOptions[index];
                    final String title =
                        item is ClinicalEvent ? item.title : item.toString();
                    final isSelected = selectedOptions.any((selected) {
                      if (item is ClinicalEvent && selected is ClinicalEvent) {
                        return item.title == selected.title;
                      }
                      return item == selected;
                    });

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? msiTheme.primary.withOpacity(0.05)
                            : msiTheme.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: isSelected
                                ? msiTheme.primary
                                : msiTheme.text.withOpacity(0.05)),
                      ),
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (val) {
                          List<dynamic> newList = List.from(selectedOptions);
                          if (val == true) {
                            newList.add(item);
                          } else {
                            newList.removeWhere((selected) {
                              if (item is ClinicalEvent &&
                                  selected is ClinicalEvent) {
                                return item.title == selected.title;
                              }
                              return item == selected;
                            });
                          }
                          onChanged(newList);
                          setModalState(() {});
                        },
                        title: Text(title,
                            style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: msiTheme.text)),
                        activeColor: msiTheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        controlAffinity: ListTileControlAffinity.trailing,
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
