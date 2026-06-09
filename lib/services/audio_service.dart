import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:audio_session/audio_session.dart' as session;
import 'package:sound_stream/sound_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'logger_service.dart';

class PannedAudioService extends ChangeNotifier {
  final ap.AudioPlayer _leftOnlyPlayer = ap.AudioPlayer();
  final ap.AudioPlayer _rightPlayer1 = ap.AudioPlayer();
  final ap.AudioPlayer _rightPlayer2 = ap.AudioPlayer();

  final RecorderStream _recorder = RecorderStream();
  final PlayerStream _player = PlayerStream();
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  bool _isPTTActive = false;

  bool _isHeadsetConnected = false;
  bool get isHeadsetConnected => _isHeadsetConnected;
  bool get isPTTActive => _isPTTActive;

  double _leftVolume = 1.0;
  double _rightVolume = 1.0;
  bool _leftPlaying = false;
  bool _rightPlaying1 = false;
  bool _rightPlaying2 = false;

  StreamSubscription? _leftCompleteSubscription;
  StreamSubscription? _right1CompleteSubscription;
  StreamSubscription? _right2CompleteSubscription;
  StreamSubscription? _leftPositionSubscription;
  StreamSubscription? _right1PositionSubscription;
  StreamSubscription? _right2PositionSubscription;

  Timer? _monitorTimer;
  int _lastLoggedPosition = -1;

  int _lastLogTime = 0;
  void _logWithTime(String message, {LogLevel level = LogLevel.debug}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final delta = _lastLogTime == 0 ? 0 : now - _lastLogTime;
    final timestamp =
        DateTime.fromMillisecondsSinceEpoch(now).toIso8601String();
    LoggerService.log('[$timestamp] +${delta}ms: $message', level: level);
    _lastLogTime = now;
  }

  PannedAudioService() {
    _init();
  }

  void setLeftVolume(double volume) {
    _logWithTime('setLeftVolume: $volume', level: LogLevel.info);
    _leftVolume = volume;
    _leftOnlyPlayer.setVolume(volume);
    notifyListeners();
  }

  void setRightVolume(double volume) {
    _logWithTime('setRightVolume: $volume', level: LogLevel.info);
    _rightVolume = volume;
    _rightPlayer1.setVolume(volume);
    _rightPlayer2.setVolume(volume);
    notifyListeners();
  }

  double get leftVolume => _leftVolume;
  double get rightVolume => _rightVolume;

  Future<void> _init() async {
    _logWithTime('Iniciando PannedAudioService...', level: LogLevel.info);
    try {
      final audioSession = await session.AudioSession.instance;
      await _configureSessionForPlayback();

      audioSession.devicesStream.listen((devices) {
        _handleDevicesChanged(devices.toList());
      });
      await audioSession.setActive(true);
      _logWithTime('AudioSession activada', level: LogLevel.info);

      await _recorder.initialize(sampleRate: 16000);
      await _player.initialize(sampleRate: 16000);
      _logWithTime('sound_stream inicializado', level: LogLevel.info);

      await _preloadSounds();

      _leftCompleteSubscription = _leftOnlyPlayer.onPlayerComplete.listen((_) {
        _leftPlaying = false;
        _syncWakeLock();
        _logWithTime('leftPlayer complete', level: LogLevel.debug);
        _stopMonitoringIfNeeded();
      });
      _right1CompleteSubscription = _rightPlayer1.onPlayerComplete.listen((_) {
        _rightPlaying1 = false;
        _syncWakeLock();
        _logWithTime('rightPlayer1 complete', level: LogLevel.debug);
        _stopMonitoringIfNeeded();
      });
      _right2CompleteSubscription = _rightPlayer2.onPlayerComplete.listen((_) {
        _rightPlaying2 = false;
        _syncWakeLock();
        _logWithTime('rightPlayer2 complete', level: LogLevel.debug);
        _stopMonitoringIfNeeded();
      });

      _leftPositionSubscription =
          _leftOnlyPlayer.onPositionChanged.listen((Duration pos) {
        if (_leftPlaying) _logPositionChange('left', pos);
      });
      _right1PositionSubscription =
          _rightPlayer1.onPositionChanged.listen((Duration pos) {
        if (_rightPlaying1) _logPositionChange('right1', pos);
      });
      _right2PositionSubscription =
          _rightPlayer2.onPositionChanged.listen((Duration pos) {
        if (_rightPlaying2) _logPositionChange('right2', pos);
      });
    } catch (e, stack) {
      _logWithTime('Error en _init: $e\n$stack', level: LogLevel.error);
    }
  }

  void _logPositionChange(String player, Duration pos) {
    final deltaSinceLastLog = _lastLoggedPosition == -1
        ? 0
        : pos.inMilliseconds - _lastLoggedPosition;
    _logWithTime(
        '📊 [$player] posición: ${pos.inMilliseconds}ms (avance: ${deltaSinceLastLog}ms)',
        level: LogLevel.debug);
    _lastLoggedPosition = pos.inMilliseconds;
  }

  void _startMonitoring() {
    if (_monitorTimer == null) {
      _monitorTimer =
          Timer.periodic(const Duration(milliseconds: 200), (timer) {
        if (!_leftPlaying && !_rightPlaying1 && !_rightPlaying2) {
          _stopMonitoringIfNeeded();
          return;
        }
        final leftState = _leftOnlyPlayer.state.name;
        final right1State = _rightPlayer1.state.name;
        final right2State = _rightPlayer2.state.name;
        _logWithTime(
            '🔍 Monitor: left=$leftState, right1=$right1State, right2=$right2State',
            level: LogLevel.debug);
      });
    }
  }

  void _stopMonitoringIfNeeded() {
    if (!_leftPlaying && !_rightPlaying1 && !_rightPlaying2) {
      _monitorTimer?.cancel();
      _monitorTimer = null;
      _logWithTime('Monitor detenido (sin reproducción)',
          level: LogLevel.debug);
      _lastLoggedPosition = -1;
    }
  }

  Future<void> _preloadSounds() async {
    _logWithTime('Precargando sonidos...', level: LogLevel.info);
    try {
      // Sin configuración avanzada de buffer (usamos por defecto)
      await _leftOnlyPlayer.setSourceAsset('audio.mp3');
      await _rightPlayer1.setSourceAsset('audio2.mp3');
      await _rightPlayer2.setSourceAsset('audio2.mp3');

      await _leftOnlyPlayer.setReleaseMode(ap.ReleaseMode.stop);
      await _rightPlayer1.setReleaseMode(ap.ReleaseMode.stop);
      await _rightPlayer2.setReleaseMode(ap.ReleaseMode.stop);

      // Configurar canales: izquierdo a la izquierda, derechos a la derecha
      await _leftOnlyPlayer.setBalance(-1.0);
      await _rightPlayer1.setBalance(1.0);
      await _rightPlayer2.setBalance(1.0);
      _logWithTime('Sonidos precargados correctamente', level: LogLevel.info);
    } catch (e, stack) {
      _logWithTime('Error en _preloadSounds: $e\n$stack',
          level: LogLevel.error);
    }
  }

  Future<void> _syncWakeLock() async {
    final shouldKeepAwake =
        _isPTTActive || _leftPlaying || _rightPlaying1 || _rightPlaying2;
    if (shouldKeepAwake) {
      await WakelockPlus.enable();
      _logWithTime('WakeLock activado', level: LogLevel.debug);
    } else {
      await WakelockPlus.disable();
      _logWithTime('WakeLock desactivado', level: LogLevel.debug);
    }
  }

  Future<void> _configureSessionForPlayback() async {
    try {
      final audioSession = await session.AudioSession.instance;
      await audioSession.configure(session.AudioSessionConfiguration(
        avAudioSessionCategory: session.AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            session.AVAudioSessionCategoryOptions.defaultToSpeaker |
                session.AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: session.AVAudioSessionMode.defaultMode,
        androidAudioAttributes: const session.AndroidAudioAttributes(
          contentType: session.AndroidAudioContentType.music,
          usage: session.AndroidAudioUsage.media,
          flags: session.AndroidAudioFlags.none,
        ),
        androidAudioFocusGainType: session.AndroidAudioFocusGainType.gain,
      ));
      _logWithTime('Sesión de playback configurada', level: LogLevel.info);
    } catch (e, stack) {
      _logWithTime('Error configurando playback: $e\n$stack',
          level: LogLevel.error);
    }
  }

  Future<void> _configureSessionForPTT() async {
    try {
      final audioSession = await session.AudioSession.instance;
      await audioSession.configure(session.AudioSessionConfiguration(
        avAudioSessionCategory: session.AVAudioSessionCategory.playAndRecord,
        avAudioSessionMode: session.AVAudioSessionMode.videoChat,
        avAudioSessionCategoryOptions:
            session.AVAudioSessionCategoryOptions.defaultToSpeaker |
                session.AVAudioSessionCategoryOptions.allowBluetooth,
        androidAudioAttributes: const session.AndroidAudioAttributes(
          contentType: session.AndroidAudioContentType.speech,
          usage: session.AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: session.AndroidAudioFocusGainType.gain,
      ));
      _logWithTime('Sesión de PTT configurada', level: LogLevel.info);
    } catch (e, stack) {
      _logWithTime('Error configurando PTT: $e\n$stack', level: LogLevel.error);
    }
  }

  void _handleDevicesChanged(List<session.AudioDevice> devices) {
    final hasHeadset = devices.any((d) =>
        d.type == session.AudioDeviceType.wiredHeadset ||
        d.type == session.AudioDeviceType.wiredHeadphones ||
        d.type == session.AudioDeviceType.bluetoothA2dp ||
        d.type == session.AudioDeviceType.bluetoothSco);
    if (_isHeadsetConnected != hasHeadset) {
      _isHeadsetConnected = hasHeadset;
      _logWithTime('Headset conectado: $hasHeadset', level: LogLevel.info);
      notifyListeners();
    }
  }

  // ===================== PTT =====================
  Future<void> startPTT() async {
    _logWithTime('startPTT llamado', level: LogLevel.info);
    if (_isPTTActive) return;

    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _logWithTime('Permiso de micrófono denegado', level: LogLevel.error);
      throw Exception('Permiso de micrófono denegado');
    }

    try {
      await _configureSessionForPTT();
      final audioSession = await session.AudioSession.instance;
      await audioSession.setActive(true);

      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = _recorder.audioStream.listen(
        (Uint8List data) {
          if (_isPTTActive) _player.writeChunk(data);
        },
        onError: (err) =>
            _logWithTime('Error en stream: $err', level: LogLevel.error),
      );

      await _player.start();
      await _recorder.start();

      _isPTTActive = true;
      await _syncWakeLock();
      notifyListeners();
      _logWithTime('PTT iniciado', level: LogLevel.info);
    } catch (e, stack) {
      _logWithTime('Error iniciando PTT: $e\n$stack', level: LogLevel.error);
      await stopPTT();
      rethrow;
    }
  }

  Future<void> stopPTT() async {
    _logWithTime('stopPTT llamado', level: LogLevel.info);
    if (!_isPTTActive) return;
    _isPTTActive = false;
    notifyListeners();

    try {
      await _recorder.stop();
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;
      await _player.stop();
      await _configureSessionForPlayback();
      await _syncWakeLock();
      _logWithTime('PTT detenido', level: LogLevel.info);
    } catch (e, stack) {
      _logWithTime('Error deteniendo PTT: $e\n$stack', level: LogLevel.error);
    }
  }

  // ===================== Reproducción de MP3 =====================
  Future<void> playLeftOnly() async {
    _logWithTime('▶️ playLeftOnly - inicio', level: LogLevel.info);
    _leftPlaying = true;
    await _syncWakeLock();
    await _leftOnlyPlayer.seek(Duration.zero);
    await _leftOnlyPlayer.resume();
    _logWithTime('✅ Ruidos vocales reproduciéndose', level: LogLevel.info);
    _startMonitoring();
  }

  Future<void> playRightOnly() async {
    _logWithTime('▶️ playRightOnly - inicio', level: LogLevel.info);
    _rightPlaying1 = true;
    await _syncWakeLock();
    await _rightPlayer1.seek(Duration.zero);
    await _rightPlayer1.resume();
    _logWithTime('✅ Estetoscopio reproduciéndose', level: LogLevel.info);
    _startMonitoring();
  }

  Future<void> playBothOnRight() async {
    _logWithTime('▶️ playBothOnRight - inicio', level: LogLevel.info);
    _rightPlaying1 = true;
    _rightPlaying2 = true;
    await _syncWakeLock();
    await _rightPlayer1.seek(Duration.zero);
    await _rightPlayer2.seek(Duration.zero);
    await _rightPlayer1.resume();
    await _rightPlayer2.resume();
    _logWithTime('✅ Ambos sonidos reproduciéndose en derecho',
        level: LogLevel.info);
    _startMonitoring();
  }

  // ===================== Detener =====================
  Future<void> stopLeft() async {
    _logWithTime('⏹️ stopLeft llamado', level: LogLevel.info);
    await _leftOnlyPlayer.stop();
    _leftPlaying = false;
    await _syncWakeLock();
    _logWithTime('Ruidos vocales detenidos', level: LogLevel.info);
    _stopMonitoringIfNeeded();
  }

  Future<void> stopRight() async {
    _logWithTime('⏹️ stopRight llamado', level: LogLevel.info);
    await _rightPlayer1.stop();
    await _rightPlayer2.stop();
    _rightPlaying1 = false;
    _rightPlaying2 = false;
    await _syncWakeLock();
    _logWithTime('Estetoscopio detenido', level: LogLevel.info);
    _stopMonitoringIfNeeded();
  }

  Future<void> stop() async {
    _logWithTime('⏹️ stop todo', level: LogLevel.info);
    await stopPTT();
    await stopLeft();
    await stopRight();
    _logWithTime('Todos los sonidos detenidos', level: LogLevel.info);
  }

  @override
  void dispose() {
    _logWithTime('Disposing PannedAudioService', level: LogLevel.info);
    _monitorTimer?.cancel();
    _leftPositionSubscription?.cancel();
    _right1PositionSubscription?.cancel();
    _right2PositionSubscription?.cancel();
    _leftCompleteSubscription?.cancel();
    _right1CompleteSubscription?.cancel();
    _right2CompleteSubscription?.cancel();
    _audioStreamSubscription?.cancel();
    _recorder.dispose();
    _player.dispose();
    _leftOnlyPlayer.dispose();
    _rightPlayer1.dispose();
    _rightPlayer2.dispose();
    WakelockPlus.disable();
    super.dispose();
  }
}
