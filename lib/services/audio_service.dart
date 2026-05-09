import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart' as session;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

enum PlaybackMode { balanceControl, dualStream }

class PannedAudioService extends ChangeNotifier {
  // Reproductores independientes para MP3 (audioplayers)
  final ap.AudioPlayer _leftOnlyPlayer = ap.AudioPlayer();
  final ap.AudioPlayer _rightPlayer1 = ap.AudioPlayer();
  final ap.AudioPlayer _rightPlayer2 = ap.AudioPlayer();

  // Reproductor para el micrófono (just_audio)
  final ja.AudioPlayer _micPlayer = ja.AudioPlayer();

  bool _isMicActive = false;
  bool _isHeadsetConnected = false;
  session.AudioSession? _audioSession;
  PlaybackMode _currentMode = PlaybackMode.balanceControl;

  static const platform = MethodChannel('msi/audio');
  static const micStream = EventChannel('msi/mic_stream');
  StreamSubscription? _micStreamSubscription;

  List<int> _audioBuffer = [];
  Timer? _flushTimer;
  final int _flushIntervalMs = 200;

  PannedAudioService() {
    _init();
  }

  Future<void> _init() async {
    // 1. Configuración correcta de la sesión de audio
    _audioSession = await session.AudioSession.instance;
    await _audioSession!.configure(session.AudioSessionConfiguration(
      avAudioSessionCategory: session.AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          session.AVAudioSessionCategoryOptions.allowBluetooth,
      avAudioSessionMode: session.AVAudioSessionMode.voiceChat, // ✅ CORRECTO
      androidAudioAttributes: session.AndroidAudioAttributes(
        contentType: session.AndroidAudioContentType.speech,
        usage: session.AndroidAudioUsage.voiceCommunication,
      ),
    ));

    // 2. Detectar cambios de dispositivos
    _audioSession!.devicesStream.listen((devices) {
      _isHeadsetConnected = devices.any((d) =>
          d.type == session.AudioDeviceType.bluetoothA2dp ||
          d.type == session.AudioDeviceType.wiredHeadset);
      notifyListeners();
    });

    // 3. Modo de audio nativo (MainActivity)
    await _configureAudioMode();

    // 4. (Opcional) Configuración inicial de just_audio (no es necesario establecer fuente)
    await _micPlayer.setVolume(1.0);
    // Nota: just_audio no tiene setBalance, pero haremos la mezcla manual en el WAV.
  }

  Future<void> _configureAudioMode() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await platform.invokeMethod('setAudioMode');
        debugPrint("✅ Modo audio configurado para auriculares Bluetooth");
      } catch (e) {
        debugPrint("⚠️ Error configurando audio nativo: $e");
      }
    }
  }

  bool get isHeadsetConnected => _isHeadsetConnected;
  bool get isMicActive => _isMicActive;
  PlaybackMode get currentMode => _currentMode;

  // --- MP3: independencia de canales ---
  Future<void> playLeftOnly(String path) async {
    await _playWithBalance(_leftOnlyPlayer, path, -1.0);
  }

  Future<void> playRightOnly(String path) async {
    await _playWithBalance(_rightPlayer1, path, 1.0);
  }

  Future<void> playBothOnRight(String path1, String path2) async {
    double balance = isHeadsetConnected ? 1.0 : 0.0;
    await _rightPlayer1.setBalance(balance);
    await _rightPlayer2.setBalance(balance);
    await _rightPlayer1.play(ap.AssetSource(path1));
    await _rightPlayer2.play(ap.AssetSource(path2));
  }

  Future<void> _playWithBalance(
      ap.AudioPlayer player, String path, double balance) async {
    await player.setBalance(isHeadsetConnected ? balance : 0.0);
    await player.play(ap.AssetSource(path));
  }

  // --- Micrófono: captura nativa + reproducción con just_audio (archivos WAV) ---
  Future<void> toggleMicL() async {
    try {
      if (await Permission.microphone.request().isGranted == false) return;

      if (_isMicActive) {
        _flushTimer?.cancel();
        await platform.invokeMethod('stopMic');
        await _micStreamSubscription?.cancel();
        await _micPlayer.stop();
        _isMicActive = false;
        debugPrint("🔴 Micrófono detenido");
      } else {
        await _configureAudioMode();
        _audioBuffer.clear();
        _flushTimer = Timer.periodic(
            Duration(milliseconds: _flushIntervalMs), (_) => _flushBuffer());
        await platform.invokeMethod('startMic');
        _micStreamSubscription =
            micStream.receiveBroadcastStream().listen((event) {
          _audioBuffer.addAll(event as Uint8List);
        });
        _isMicActive = true;
        debugPrint("🎤 Micrófono activado (vía nativo)");
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error en toggleMicL: $e");
    }
  }

  Future<void> _flushBuffer() async {
    if (_audioBuffer.isEmpty) return;
    final data = Uint8List.fromList(_audioBuffer);
    _audioBuffer.clear();

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(
          '${tempDir.path}/mic_${DateTime.now().millisecondsSinceEpoch}.wav');
      final wavBytes = _buildStereoLeftOnlyWav(data, 16000);
      await file.writeAsBytes(wavBytes);

      await _micPlayer.setAudioSource(ja.AudioSource.file(file.path));
      await _micPlayer.play();
      Future.delayed(Duration(seconds: 1), () => file.delete());
    } catch (e) {
      debugPrint("Error al vaciar buffer: $e");
    }
  }

  /// Construye un archivo WAV PCM de 16 bits (mono o estéreo)
  Uint8List _buildWavFile(Uint8List pcmData, int sampleRate, int numChannels) {
    final int byteRate = sampleRate * numChannels * 2;
    final int totalDataLen = pcmData.length;
    final int totalLen = totalDataLen + 36;
    final ByteBuffer buffer = ByteBuffer(totalLen);
    buffer
      ..setString(0, "RIFF")
      ..setInt32(4, totalLen - 8, Endian.little)
      ..setString(8, "WAVE")
      ..setString(12, "fmt ")
      ..setInt32(16, 16, Endian.little)
      ..setInt16(20, 1, Endian.little)
      ..setInt16(22, numChannels, Endian.little)
      ..setInt32(24, sampleRate, Endian.little)
      ..setInt32(28, byteRate, Endian.little)
      ..setInt16(32, numChannels * 2, Endian.little)
      ..setInt16(34, 16, Endian.little)
      ..setString(36, "data")
      ..setInt32(40, totalDataLen, Endian.little)
      ..setBytes(44, pcmData);
    return buffer.asUint8List();
  }

  /// Convierte mono a estéreo solo canal izquierdo y genera WAV
  Uint8List _buildStereoLeftOnlyWav(Uint8List monoPcm, int sampleRate) {
    final int samples = monoPcm.length ~/ 2;
    final Uint8List stereoPcm = Uint8List(samples * 4);
    for (int i = 0; i < samples; i++) {
      stereoPcm[i * 4] = monoPcm[i * 2];
      stereoPcm[i * 4 + 1] = monoPcm[i * 2 + 1];
      // canal derecho = 0 (silencio)
    }
    return _buildWavFile(stereoPcm, sampleRate, 2);
  }

  Future<void> stop() async {
    await _leftOnlyPlayer.stop();
    await _rightPlayer1.stop();
    await _rightPlayer2.stop();
    if (_isMicActive) {
      _flushTimer?.cancel();
      await platform.invokeMethod('stopMic');
      await _micStreamSubscription?.cancel();
      await _micPlayer.stop();
      _isMicActive = false;
    }
  }

  @override
  void dispose() {
    _leftOnlyPlayer.dispose();
    _rightPlayer1.dispose();
    _rightPlayer2.dispose();
    _micPlayer.dispose();
    _flushTimer?.cancel();
    if (_isMicActive) platform.invokeMethod('stopMic');
    _micStreamSubscription?.cancel();
    super.dispose();
  }
}

/// Utilidad para escribir bytes en little-endian
class ByteBuffer {
  final List<int> _list;
  ByteBuffer(int length) : _list = List<int>.filled(length, 0);

  void setInt32(int offset, int value, Endian endian) {
    final bytes = ByteData(4)..setInt32(0, value, endian);
    setBytes(offset, bytes.buffer.asUint8List());
  }

  void setInt16(int offset, int value, Endian endian) {
    final bytes = ByteData(2)..setInt16(0, value, endian);
    setBytes(offset, bytes.buffer.asUint8List());
  }

  void setString(int offset, String value) {
    final bytes = value.codeUnits;
    setBytes(offset, Uint8List.fromList(bytes));
  }

  void setBytes(int offset, Uint8List bytes) {
    for (int i = 0; i < bytes.length; i++) {
      _list[offset + i] = bytes[i];
    }
  }

  Uint8List asUint8List() => Uint8List.fromList(_list);
}
