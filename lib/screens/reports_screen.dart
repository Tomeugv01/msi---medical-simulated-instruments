import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/simulation_provider.dart';

/// [ReportsScreen] allows users to review the session log and export it as a PDF.
/// It summarizes all clinical events, adjustments, and measurements captured during simulation.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  /// Generates and shows a print/save dialog for the session report.
  Future<void> _exportPdf(BuildContext context, SimulationState state) async {
    final pdf = pw.Document();
    final logsInOrder = state.logs.reversed.toList();
    pdf.addPage(
      pw.MultiPage(
        header: (pw.Context context) => pw.Text(
            'INFORME CLÍNICO - MSI PROTOCOL',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
        build: (pw.Context context) => [
          pw.SizedBox(height: 20),
          pw.Text('Sesión: ${DateTime.now()}'),
          pw.Text('Supervisor: ${state.supervisor}'),
          pw.Text('Estudiante: ${state.student}'),
          pw.Divider(),
          pw.SizedBox(height: 20),
          ...logsInOrder.map((log) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${log['time']} - ${log['title']}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(log['desc']!,
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              )))
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SimulationState>();
    final msiTheme = state.theme;

    return Column(
      children: [
        if (state.logs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: ElevatedButton.icon(
              onPressed: () => _exportPdf(context, state),
              icon: const Icon(LucideIcons.fileText),
              label: Text('Exportar PDF',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: msiTheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50)),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: state.logs.length,
            itemBuilder: (context, i) {
              final log = state.logs[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: msiTheme.card,
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(log['title']!,
                            style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w900,
                                color: msiTheme.primary,
                                fontSize: 13,
                                letterSpacing: -0.2)),
                        Text(log['time']!,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(log['desc']!,
                        style: TextStyle(
                            fontSize: 12,
                            color: msiTheme.text.withOpacity(0.7))),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
