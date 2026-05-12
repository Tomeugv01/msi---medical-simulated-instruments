import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/simulation_provider.dart';
import '../models/instrumental_models.dart';
import './screens/setup_screen.dart';
import './screens/hub_screen.dart';
import './screens/reports_screen.dart';
import './widgets/msi_modals.dart';

/// Main entry point for the MSI (Medical Simulated Instruments) Application.
/// Initializes the [SimulationState] provider and sets up the global theme.
void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => SimulationState(),
      child: const ClinicalEtherApp(),
    ),
  );
}

class ClinicalEtherApp extends StatelessWidget {
  const ClinicalEtherApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;

    return MaterialApp(
      title: 'MSI - Medical Simulated Instruments',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: msiTheme.primary,
            primary: msiTheme.primary,
            surface: msiTheme.background),
        scaffoldBackgroundColor: msiTheme.background,
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: const MainAppShell(),
    );
  }
}

class MainAppShell extends StatefulWidget {
  const MainAppShell({super.key});
  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> {
  int _currentIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Simulate initial loading/initialization
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });

    // Listen to simulation state changes
    final state = context.read<SimulationState>();
    state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    context.read<SimulationState>().removeListener(_onStateChanged);
    super.dispose();
  }

  bool _wasRunning = false;
  void _onStateChanged() {
    final state = context.read<SimulationState>();
    if (state.isRunning && !_wasRunning) {
      // Simulation just started, reset to Hub
      setState(() => _currentIndex = 0);
    }
    _wasRunning = state.isRunning;
  }

  void _navigateTo(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo.png',
                  height: 280,
                  errorBuilder: (c, e, s) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.medical_services,
                              size: 120, color: Color(0xFF1E40AF)),
                          const SizedBox(height: 20),
                          Text('MSI PROTOCOL',
                              style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF1E40AF),
                                  fontSize: 32,
                                  letterSpacing: -1.0)),
                          Text('Medical Simulated Instruments',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1E40AF)
                                      .withOpacity(0.5))),
                        ],
                      )),
              const SizedBox(height: 80),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E40AF)),
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;

    return PopScope(
      canPop: !state.isRunning || (_currentIndex == 0),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (state.isRunning && _currentIndex > 0) _navigateTo(0);
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 90,
          backgroundColor: msiTheme.card,
          elevation: 0,
          title: Row(
            children: [
              Image.asset('assets/logo.png',
                  height: 44,
                  errorBuilder: (c, e, s) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MSI PROTOCOL',
                              style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w900,
                                  color: msiTheme.primary,
                                  fontSize: 18,
                                  height: 1.1)),
                          Text('Medical Simulated Instruments',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: msiTheme.primary.withOpacity(0.5))),
                        ],
                      )),
              const SizedBox(width: 12),
              if (state.isRunning)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: msiTheme.accent,
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    Icon(Icons.circle, size: 6, color: msiTheme.primary),
                    const SizedBox(width: 6),
                    Text(state.timeString,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: msiTheme.primary)),
                  ]),
                ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const BluetoothModal()),
              icon: Icon(
                  state.isConnected
                      ? LucideIcons.bluetooth
                      : LucideIcons.bluetoothOff,
                  color: state.isConnected
                      ? msiTheme.primary
                      : Colors.grey.withOpacity(0.3)),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: _buildBottomNav(state),
      ),
    );
  }

  Widget _buildBody() {
    final state = context.watch<SimulationState>();
    if (_currentIndex == 1) return const ReportsScreen();
    if (!state.isRunning) return SetupScreen(onNavigate: (i) => _navigateTo(i));
    return HubScreen(onFinished: () => _navigateTo(1));
  }

  Widget _buildBottomNav(SimulationState state) {
    final msiTheme = state.theme;
    if (!state.isRunning) {
      return Container(
        height: 72,
        decoration: BoxDecoration(color: msiTheme.accent),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _NavBtn(
              icon: LucideIcons.home,
              label: 'Inicio',
              active: _currentIndex == 0,
              onTap: () => _navigateTo(0)),
          _NavBtn(
              icon: LucideIcons.settings,
              label: 'Config',
              active: false,
              onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const ConfigModal())),
        ]),
      );
    } else {
      return Container(
        height: 72,
        decoration: BoxDecoration(color: msiTheme.accent),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _NavBtn(
              icon: LucideIcons.layoutDashboard,
              label: 'Panel',
              active: _currentIndex == 0,
              onTap: () => _navigateTo(0)),
          _NavBtn(
              icon: LucideIcons.clipboardList,
              label: 'Registro',
              active: _currentIndex == 1,
              onTap: () => _navigateTo(1)),
        ]),
      );
    }
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavBtn(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SimulationState>().theme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
            color: active ? theme.primary.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              color: active ? theme.primary : theme.text.withOpacity(0.4),
              size: 24),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: active ? theme.primary : theme.text.withOpacity(0.4))),
        ]),
      ),
    );
  }
}
