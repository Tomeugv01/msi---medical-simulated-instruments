import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/simulation_provider.dart';
import '../models/instrumental_models.dart';
import '../widgets/msi_modals.dart';

class SetupScreen extends StatefulWidget {
  final Function(int) onNavigate;
  const SetupScreen({super.key, required this.onNavigate});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  String _view = 'main';

  void _handleBack() {
    if (_view == 'presets_instrumental' || _view == 'presets_clinicos') {
      setState(() => _view = 'presets');
    } else if (_view == 'presets') {
      setState(() => _view = 'main');
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 700;

    Widget content;
    if (_view == 'presets') {
      content = _buildPresets(isMobile);
    } else if (_view == 'presets_instrumental') {
      content = _buildInstrumentalView();
    } else if (_view == 'presets_clinicos') {
      content = _buildClinicalView();
    } else {
      content = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 48,
                runSpacing: 32,
                children: [
                  MainCard(
                      title: 'Inicio Rápido',
                      icon: LucideIcons.zap,
                      color: const Color(0xFFD7E2FF),
                      onTap: () {
                        context.read<SimulationState>().startSimulation();
                        widget.onNavigate(0);
                      }),
                  MainCard(
                      title: 'Inicio caso clinico preconfigurado',
                      icon: LucideIcons.clipboardList,
                      color: const Color(0xFFBFD2FD),
                      onTap: () => setState(() => _view = 'presets')),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: _view == 'main',
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: content,
    );
  }

  Widget _buildPresets(bool mobile) {
    final msiTheme = context.watch<SimulationState>().theme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
              onPressed: () => setState(() => _view = 'main'),
              icon: Icon(LucideIcons.arrowLeft, color: msiTheme.primary)),
          Text('Elegir Categoría',
              style: GoogleFonts.manrope(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: msiTheme.text,
                  letterSpacing: -0.5)),
          const SizedBox(height: 32),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: mobile ? 1 : 2,
            childAspectRatio: mobile ? 1.8 : 2.2,
            mainAxisSpacing: 24,
            crossAxisSpacing: 24,
            children: [
              MainCard(
                title: 'Formación Instrumental',
                icon: LucideIcons.wrench,
                color: const Color(0xFFD7E2FF),
                onTap: () => setState(() => _view = 'presets_instrumental'),
              ),
              MainCard(
                title: 'Casos Clínicos',
                icon: LucideIcons.clipboardList,
                color: const Color(0xFFBFD2FD),
                onTap: () => setState(() => _view = 'presets_clinicos'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstrumentalView() {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    final presets = state.instrumentalPresets;
    bool mobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditPresetDialog(context),
        backgroundColor: msiTheme.primary,
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
                onPressed: () => setState(() => _view = 'presets'),
                icon: Icon(LucideIcons.arrowLeft, color: msiTheme.primary)),
            Text('Formación Instrumental',
                style: GoogleFonts.manrope(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: msiTheme.text,
                    letterSpacing: -0.5)),
            const SizedBox(height: 24),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: mobile ? 1 : 2,
              childAspectRatio: mobile ? 2.6 : 3.2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: presets
                  .map((preset) => InstrumentalPresetTile(
                        preset: preset,
                        onTap: () {
                          state.applyPreset(preset);
                          widget.onNavigate(0);
                        },
                        onLongPress: () => _showPresetOptions(context, preset),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showPresetOptions(BuildContext context, InstrumentalPreset preset) {
    HapticFeedback.mediumImpact();
    final msiTheme = context.read<SimulationState>().theme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: msiTheme.background,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(32), topRight: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(preset.title,
                style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: msiTheme.text)),
            const SizedBox(height: 24),
            ListTile(
              leading: Icon(LucideIcons.edit3, color: msiTheme.primary),
              title: Text('Editar Configuración',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700, color: msiTheme.text)),
              onTap: () {
                Navigator.pop(context);
                _showEditPresetDialog(context,
                    preset: preset, isClinical: preset.isClinical);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: Colors.red),
              title: Text('Eliminar',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700, color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirm(context, preset);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, InstrumentalPreset preset) {
    final state = context.read<SimulationState>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Formación'),
        content:
            Text('¿Estás seguro de que deseas eliminar \"${preset.title}\"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              state.deletePreset(preset.id);
              Navigator.pop(context);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showEditPresetDialog(BuildContext context,
      {InstrumentalPreset? preset, bool isClinical = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          EditPresetModal(preset: preset, isClinical: isClinical),
    );
  }

  Widget _buildClinicalView() {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    final presets = state.clinicalPresets;
    bool mobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditPresetDialog(context, isClinical: true),
        backgroundColor: msiTheme.primary,
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
                onPressed: () => setState(() => _view = 'presets'),
                icon: Icon(LucideIcons.arrowLeft, color: msiTheme.primary)),
            Text('Casos Clínicos',
                style: GoogleFonts.manrope(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: msiTheme.text,
                    letterSpacing: -0.5)),
            const SizedBox(height: 24),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: mobile ? 1 : 2,
              childAspectRatio: mobile ? 2.6 : 3.2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: presets
                  .map((preset) => InstrumentalPresetTile(
                        preset: preset,
                        onTap: () {
                          state.applyPreset(preset);
                          widget.onNavigate(0);
                        },
                        onLongPress: () => _showPresetOptions(context, preset),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class MainCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const MainCard(
      {super.key,
      required this.title,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final msiTheme = context.watch<SimulationState>().theme;
    bool mobile = MediaQuery.of(context).size.width < 700;
    Color bgColor = msiTheme.name == 'MSI Classic' ? color : msiTheme.card;
    if (msiTheme.name == 'Cyber Dark') bgColor = msiTheme.card;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: mobile ? double.infinity : 280,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: msiTheme.text.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 8))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: msiTheme.primary),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: msiTheme.text,
                    letterSpacing: -0.2)),
          ],
        ),
      ),
    );
  }
}

class InstrumentalPresetTile extends StatelessWidget {
  final InstrumentalPreset preset;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const InstrumentalPresetTile(
      {super.key,
      required this.preset,
      required this.onTap,
      required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final msiTheme = context.watch<SimulationState>().theme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: msiTheme.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: msiTheme.text.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: msiTheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(preset.icon, color: msiTheme.primary, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    preset.title,
                    style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: msiTheme.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${preset.instrumentTitles.length} instrumentos activos',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: msiTheme.text.withOpacity(0.4)),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.moreVertical,
                size: 18, color: msiTheme.text.withOpacity(0.2)),
          ],
        ),
      ),
    );
  }
}

class PresetTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  const PresetTile(
      {super.key,
      required this.title,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final msiTheme = context.watch<SimulationState>().theme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: msiTheme.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: msiTheme.text.withOpacity(0.05)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 4))
            ]),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: msiTheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: msiTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(title,
                    style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: msiTheme.text),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
