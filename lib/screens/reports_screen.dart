import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../providers/simulation_provider.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  Future<void> _exportPdf(BuildContext context, SimulationState state) async {
    try {
      final pdf = pw.Document();

      // Logs en orden cronológico (más antiguo primero)
      final logsInOrder = state.logs.reversed.toList();

      // Separar logs de ajustes de parámetros, evaluación final y el resto
      final List<Map<String, String>> paramLogs = [];
      final List<Map<String, String>> otherLogs = [];
      Map<String, String>? evaluationLog;

      for (var log in logsInOrder) {
        if (log['title'] == 'Ajuste de Parámetros') {
          paramLogs.add(log);
        } else if (log['title'] == 'Evaluación Final' ||
            (log['title']?.startsWith('Desempeño Checklist') ?? false)) {
          evaluationLog = log;
        } else {
          otherLogs.add(log);
        }
      }

      // Construir la lista reorganizada
      final List<Map<String, String>> reorderedLogs = [];

      // 1. Evaluación Final al principio
      if (evaluationLog != null) {
        reorderedLogs.add(evaluationLog!);
      }

      // 2. Ajustes de Parámetros consolidados (un solo título)
      if (paramLogs.isNotEmpty) {
        final combinedDesc = paramLogs.map((log) {
          // Extraer la descripción real (sin el prefijo "Cambio detectado: ")
          String desc = log['desc']!;
          if (desc.startsWith('Cambio detectado: ')) {
            desc = desc.substring(18);
          }
          return '${log['time']} - $desc';
        }).join('\n');
        reorderedLogs.add({
          'time': paramLogs.first['time']!,
          'title': 'Ajustes de Parámetros',
          'desc': combinedDesc,
        });
      }

      // 3. Resto de logs en orden
      reorderedLogs.addAll(otherLogs);

      pdf.addPage(
        pw.MultiPage(
          header: (pw.Context _) => pw.Text(
            'INFORME CLÍNICO - MSI PROTOCOL',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
          build: (pw.Context _) => [
            pw.SizedBox(height: 20),
            pw.Text('Sesión: ${DateTime.now()}'),
            pw.Text(
                'Profesor: ${state.supervisor.isEmpty ? 'No especificado' : state.supervisor}'),
            pw.Text(
                'Estudiante: ${state.student.isEmpty ? 'No especificado' : state.student}'),
            if (state.currentIntroduction.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Introducción:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(state.currentIntroduction),
            ],
            if (state.currentNotes.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Notas:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(state.currentNotes),
            ],
            pw.Divider(),
            pw.SizedBox(height: 20),
            ...reorderedLogs.map((log) {
              // Limpiar emojis por texto plano
              String cleanedDesc =
                  log['desc']!.replaceAll('✅', '[X]').replaceAll('❌', '[ ]');
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('${log['time']} - ${log['title']}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(cleanedDesc,
                        style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
      );
    } catch (e, stack) {
      debugPrint('Error generando PDF: $e\n$stack');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Error al generar el PDF. Por favor, inténtalo de nuevo.')),
        );
      }
    }
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
                minimumSize: const Size(double.infinity, 50),
              ),
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
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          log['title']!,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w900,
                            color: msiTheme.primary,
                            fontSize: 13,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          log['time']!,
                          style:
                              const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      log['desc']!,
                      style: TextStyle(
                        fontSize: 12,
                        color: msiTheme.text.withOpacity(0.7),
                      ),
                    ),
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
