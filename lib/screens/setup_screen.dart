import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:reorderables/reorderables.dart';
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
              _ResponsiveMainCardGrid(
                children: [
                  MainCard(
                    title: 'Inicio Rápido',
                    icon: LucideIcons.zap,
                    color: const Color(0xFFD7E2FF),
                    onTap: () {
                      context.read<SimulationState>().startSimulation();
                      widget.onNavigate(0);
                    },
                  ),
                  MainCard(
                    title: 'Casos Clínicos',
                    icon: LucideIcons.clipboardList,
                    color: const Color(0xFFBFD2FD),
                    onTap: () => setState(() => _view = 'presets'),
                  ),
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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              onPressed: () => setState(() => _view = 'main'),
              icon: Icon(LucideIcons.arrowLeft, color: msiTheme.primary),
            ),
            Text(
              'Elegir Categoría',
              style: GoogleFonts.manrope(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: msiTheme.text,
                letterSpacing: -0.5,
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: _ResponsiveMainCardGrid(
                    children: [
                      MainCard(
                        title: 'Monitorización',
                        icon: LucideIcons.wrench,
                        color: const Color(0xFFD7E2FF),
                        onTap: () =>
                            setState(() => _view = 'presets_instrumental'),
                      ),
                      MainCard(
                        title: 'Casos Clínicos',
                        icon: LucideIcons.clipboardList,
                        color: const Color(0xFFBFD2FD),
                        onTap: () => setState(() => _view = 'presets_clinicos'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstrumentalView() {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;
    final presets = state.instrumentalPresets;
    final mobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditPresetDialog(context),
        backgroundColor: msiTheme.primary,
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
                onPressed: () => setState(() => _view = 'presets'),
                icon: Icon(LucideIcons.arrowLeft, color: msiTheme.primary)),
            Text('Monitorización',
                style: GoogleFonts.manrope(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: msiTheme.text,
                    letterSpacing: -0.5)),
            const SizedBox(height: 24),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tileWidth = mobile
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 16) / 2;
                  return ReorderableWrap(
                    needsLongPressDraggable: false,
                    minMainAxisCount: mobile ? 1 : 2,
                    maxMainAxisCount: mobile ? 1 : 2,
                    spacing: 16,
                    runSpacing: 16,
                    onReorder: (oldIndex, newIndex) {
                      state.reorderPreset(oldIndex, newIndex,
                          isClinical: false);
                    },
                    children: presets
                        .map((preset) => SizedBox(
                              key: ValueKey(preset.id),
                              width: tileWidth,
                              child: InstrumentalPresetTile(
                                preset: preset,
                                onTap: () {
                                  state.applyPreset(preset);
                                  widget.onNavigate(0);
                                },
                                onMenuTap: () =>
                                    _showPresetOptions(context, preset),
                              ),
                            ))
                        .toList(),
                  );
                },
              ),
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
    final mobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditPresetDialog(context, isClinical: true),
        backgroundColor: msiTheme.primary,
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
      body: Padding(
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
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tileWidth = mobile
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 16) / 2;
                  return ReorderableWrap(
                    needsLongPressDraggable: false,
                    minMainAxisCount: mobile ? 1 : 2,
                    maxMainAxisCount: mobile ? 1 : 2,
                    spacing: 16,
                    runSpacing: 16,
                    onReorder: (oldIndex, newIndex) {
                      state.reorderPreset(oldIndex, newIndex, isClinical: true);
                    },
                    children: presets
                        .map((preset) => SizedBox(
                              key: ValueKey(preset.id),
                              width: tileWidth,
                              child: InstrumentalPresetTile(
                                preset: preset,
                                onTap: () {
                                  state.applyPreset(preset);
                                  widget.onNavigate(0);
                                },
                                onMenuTap: () =>
                                    _showPresetOptions(context, preset),
                              ),
                            ))
                        .toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponsiveMainCardGrid extends StatelessWidget {
  final List<Widget> children;

  const _ResponsiveMainCardGrid({
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        /*
         * Layout responsive:
         * - Pantallas pequeñas y medianas: tarjetas una sobre la otra,
         *   como en el teléfono.
         * - Pantallas muy anchas: se permiten dos columnas, pero las tarjetas
         *   crecen de forma proporcional y no quedan pequeñas en el centro.
         */
        final useOneColumn = availableWidth < 980;
        final spacing = useOneColumn ? 22.0 : 32.0;

        final maxCardWidth = useOneColumn
            ? availableWidth.clamp(280.0, 560.0)
            : ((availableWidth - spacing) / 2).clamp(320.0, 520.0);

        final cardWidth = maxCardWidth.toDouble();

        if (useOneColumn) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                SizedBox(
                  width: cardWidth,
                  child: children[i],
                ),
                if (i != children.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: spacing,
          children: children
              .map(
                (child) => SizedBox(
                  width: cardWidth,
                  child: child,
                ),
              )
              .toList(),
        );
      },
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 700;
    final verticalPadding =
        isCompact ? 40.0 : (screenWidth * 0.045).clamp(42.0, 72.0);
    final horizontalPadding =
        isCompact ? 24.0 : (screenWidth * 0.03).clamp(28.0, 44.0);
    final iconSize = isCompact ? 48.0 : (screenWidth * 0.045).clamp(52.0, 72.0);
    final titleSize =
        isCompact ? 16.0 : (screenWidth * 0.015).clamp(17.0, 22.0);

    Color bgColor = msiTheme.name == 'MSI Classic' ? color : msiTheme.card;
    if (msiTheme.name == 'Cyber Dark') bgColor = msiTheme.card;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
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
            Icon(icon, size: iconSize, color: msiTheme.primary),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    fontSize: titleSize,
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
  final VoidCallback onMenuTap;
  const InstrumentalPresetTile(
      {super.key,
      required this.preset,
      required this.onTap,
      required this.onMenuTap});

  @override
  Widget build(BuildContext context) {
    final msiTheme = context.watch<SimulationState>().theme;
    return GestureDetector(
      onTap: onTap,
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
            GestureDetector(
              onTap: onMenuTap,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(LucideIcons.moreVertical,
                    size: 18, color: msiTheme.text.withOpacity(0.4)),
              ),
            ),
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
