import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:audio_session/audio_session.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'logger_service.dart';

class PannedAudioService extends ChangeNotifier {
  final ap.AudioPlayer _leftPlayer = ap.AudioPlayer();
  final ap.AudioPlayer _rightPlayer = ap.AudioPlayer();
  final ap.AudioPlayer _rightPlayer2 = ap.AudioPlayer();

  // Se mantiene como en la versión estable.
  // Aunque ahora el PTT real lo haga Android nativo, dejamos sound_stream
  // inicializado igual que cuando las pistas funcionaban perfectas.
  final RecorderStream _recorder = RecorderStream();
  final PlayerStream _player = PlayerStream();

  static const MethodChannel _nativePttChannel =
      MethodChannel('msi_native_ptt');

  static const String voiceCoughAsset = 'sounds/tos.mp3';
  static const String voiceNauseaAsset = 'sounds/nausea.mp3';
  static const String stethoscopeWheezingAsset = 'sounds/wheezing.mp3';
  static const String stethoscopeHeartAsset = 'sounds/heart.mp3';

  bool _isPTTActive = false;
  bool _isHeadsetConnected = false;

  bool get isHeadsetConnected => _isHeadsetConnected;
  bool get isPTTActive => _isPTTActive;
  bool get isLeftPlaying => _leftPlaying;
  bool get isRightPlaying => _rightPlaying1 || _rightPlaying2;

  double _leftVolume = 1.0;
  double _rightVolume = 1.0;

  bool _leftPlaying = false;
  bool _rightPlaying1 = false;
  bool _rightPlaying2 = false;

  bool _isPrimed = false;
  Future<void>? _primeFuture;

  int _lastLogTime = 0;

  PannedAudioService() {
    _init();
  }

  double get leftVolume => _leftVolume;
  double get rightVolume => _rightVolume;

  void _logWithTime(String message, {LogLevel level = LogLevel.debug}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final delta = _lastLogTime == 0 ? 0 : now - _lastLogTime;
    final timestamp =
        DateTime.fromMillisecondsSinceEpoch(now).toIso8601String();

    LoggerService.log('[$timestamp] +${delta}ms: $message', level: level);
    _lastLogTime = now;
  }

  void setLeftVolume(double volume) {
    _leftVolume = volume;
    _leftPlayer.setVolume(volume);
    notifyListeners();
  }

  void setRightVolume(double volume) {
    _rightVolume = volume;
    _rightPlayer.setVolume(volume);
    _rightPlayer2.setVolume(volume);
    notifyListeners();
  }

  Future<void> _init() async {
    _logWithTime(
      'Iniciando PannedAudioService estable + menú de sonidos + PTT nativo aislado...',
      level: LogLevel.info,
    );

    try {
      final audioSession = await AudioSession.instance;

      await _configureSessionForPlayback();

      audioSession.devicesStream.listen(
        (devices) => _handleDevicesChanged(devices.toList()),
      );

      await audioSession.setActive(true);

      // Esto se mantiene exactamente como en la versión estable.
      await _recorder.initialize(sampleRate: 16000);
      await _player.initialize(sampleRate: 16000);

      await _leftPlayer.setReleaseMode(ap.ReleaseMode.stop);
      await _rightPlayer.setReleaseMode(ap.ReleaseMode.stop);
      await _rightPlayer2.setReleaseMode(ap.ReleaseMode.stop);

      _leftPlayer.onPlayerComplete.listen((_) {
        _leftPlaying = false;
        _syncWakeLock();
        notifyListeners();
      });

      _rightPlayer.onPlayerComplete.listen((_) {
        _rightPlaying1 = false;
        _syncWakeLock();
        notifyListeners();
      });

      _rightPlayer2.onPlayerComplete.listen((_) {
        _rightPlaying2 = false;
        _syncWakeLock();
        notifyListeners();
      });

      // Primer arranque silencioso de cada AudioPlayer real.
      _primeFuture = _primeAllPlayers();
      await _primeFuture;

      _logWithTime('Audio service listo', level: LogLevel.info);
    } catch (e, stack) {
      _logWithTime('Error en _init: $e\n$stack', level: LogLevel.error);
    }
  }

  Future<void> _syncWakeLock() async {
    final shouldKeepAwake =
        _isPTTActive || _leftPlaying || _rightPlaying1 || _rightPlaying2;

    if (shouldKeepAwake) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  }

  Future<void> _configureSessionForPlayback() async {
    try {
      final session = await AudioSession.instance;

      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.defaultToSpeaker |
                  AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        ),
      );

      await session.setActive(true);
    } catch (e, stack) {
      _logWithTime(
        'Error configurando sesión playback: $e\n$stack',
        level: LogLevel.error,
      );
    }
  }

  void _handleDevicesChanged(List<AudioDevice> devices) {
    final hasHeadset = devices.any(
      (device) =>
          device.type == AudioDeviceType.wiredHeadset ||
          device.type == AudioDeviceType.wiredHeadphones ||
          device.type == AudioDeviceType.bluetoothA2dp ||
          device.type == AudioDeviceType.bluetoothSco,
    );

    if (_isHeadsetConnected != hasHeadset) {
      _isHeadsetConnected = hasHeadset;
      notifyListeners();
    }
  }

  Future<void> _primeAllPlayers() async {
    if (_isPrimed) return;

    try {
      _logWithTime('Priming de players iniciado', level: LogLevel.info);

      await _configureSessionForPlayback();

      await _primeOnePlayer(
        player: _leftPlayer,
        assetPath: voiceCoughAsset,
        balance: -1.0,
      );

      await _primeOnePlayer(
        player: _rightPlayer,
        assetPath: stethoscopeHeartAsset,
        balance: 1.0,
      );

      await _primeOnePlayer(
        player: _rightPlayer2,
        assetPath: voiceCoughAsset,
        balance: 1.0,
      );

      await _leftPlayer.setVolume(_leftVolume);
      await _rightPlayer.setVolume(_rightVolume);
      await _rightPlayer2.setVolume(_rightVolume);

      _isPrimed = true;

      _logWithTime('Priming de players completado', level: LogLevel.info);
    } catch (e, stack) {
      _logWithTime(
        'Error durante priming de players: $e\n$stack',
        level: LogLevel.error,
      );
    }
  }

  Future<void> _primeOnePlayer({
    required ap.AudioPlayer player,
    required String assetPath,
    required double balance,
  }) async {
    try {
      await player.stop();

      await player.setSourceAsset(assetPath);
      await player.setVolume(0.0);
      await player.setBalance(balance);
      await player.seek(Duration.zero);

      await player.resume();

      await Future.delayed(const Duration(milliseconds: 250));

      await player.setBalance(balance);
      await player.setVolume(0.0);

      await Future.delayed(const Duration(milliseconds: 100));

      await player.stop();
      await player.seek(Duration.zero);

      await player.setBalance(balance);
    } catch (e, stack) {
      _logWithTime(
        'Error en _primeOnePlayer($assetPath, balance=$balance): $e\n$stack',
        level: LogLevel.error,
      );
    }
  }

  Future<void> _waitUntilPrimed() async {
    if (_isPrimed) return;

    final future = _primeFuture;
    if (future != null) {
      await future;
    } else {
      _primeFuture = _primeAllPlayers();
      await _primeFuture;
    }
  }

  Future<void> _reprimeAfterPTT() async {
    _logWithTime('Rehaciendo priming después de PTT...', level: LogLevel.info);

    _isPrimed = false;

    await _configureSessionForPlayback();

    await Future.delayed(const Duration(milliseconds: 250));

    _primeFuture = _primeAllPlayers();
    await _primeFuture;

    _logWithTime('Priming post-PTT completado', level: LogLevel.info);
  }

  Future<void> startPTT() async {
    _logWithTime('startPTT llamado', level: LogLevel.info);

    if (_isPTTActive) return;

    final status = await Permission.microphone.request();

    if (status != PermissionStatus.granted) {
      throw Exception('Permiso de micrófono denegado');
    }

    try {
      await stopLeft();
      await stopRight();

      await _nativePttChannel.invokeMethod(
        'startPtt',
        <String, dynamic>{
          'leftVolume': _leftVolume,
        },
      );

      _isPTTActive = true;

      await _syncWakeLock();
      notifyListeners();

      _logWithTime(
        'PTT nativo iniciado: micro tablet -> canal izquierdo',
        level: LogLevel.info,
      );
    } catch (e, stack) {
      _isPTTActive = false;
      notifyListeners();

      await _syncWakeLock();

      _logWithTime(
        'Error iniciando PTT nativo: $e\n$stack',
        level: LogLevel.error,
      );

      rethrow;
    }
  }

  Future<void> stopPTT() async {
    _logWithTime('stopPTT llamado', level: LogLevel.info);

    if (!_isPTTActive) return;

    _isPTTActive = false;
    notifyListeners();

    try {
      await _nativePttChannel.invokeMethod('stopPtt');

      await Future.delayed(const Duration(milliseconds: 250));

      await _configureSessionForPlayback();

      await _reprimeAfterPTT();

      await _syncWakeLock();

      _logWithTime('PTT nativo detenido', level: LogLevel.info);
    } catch (e, stack) {
      _logWithTime(
        'Error deteniendo PTT nativo: $e\n$stack',
        level: LogLevel.error,
      );
    }
  }

  Future<void> _startPannedAsset({
    required ap.AudioPlayer player,
    required String assetPath,
    required double balance,
    required double volume,
  }) async {
    await _startPannedSource(
      player: player,
      assetPath: assetPath,
      balance: balance,
      volume: volume,
    );
  }

  Future<void> _startPannedDeviceFile({
    required ap.AudioPlayer player,
    required String filePath,
    required double balance,
    required double volume,
  }) async {
    await _startPannedSource(
      player: player,
      filePath: filePath,
      balance: balance,
      volume: volume,
    );
  }

  Future<void> _startPannedSource({
    required ap.AudioPlayer player,
    String? assetPath,
    String? filePath,
    required double balance,
    required double volume,
  }) async {
    await _waitUntilPrimed();
    await _configureSessionForPlayback();

    await player.stop();

    if (filePath != null) {
      await player.setSourceDeviceFile(filePath);
    } else if (assetPath != null) {
      await player.setSourceAsset(assetPath);
    } else {
      throw ArgumentError('Se necesita assetPath o filePath');
    }

    await player.setBalance(balance);
    await player.setVolume(volume);
    await player.seek(Duration.zero);

    await player.resume();

    await Future.delayed(const Duration(milliseconds: 30));
    await player.setBalance(balance);
    await player.setVolume(volume);

    await Future.delayed(const Duration(milliseconds: 120));
    await player.setBalance(balance);
    await player.setVolume(volume);
  }

  Future<void> playLeftCough() async {
    await playLeftAsset(voiceCoughAsset, logName: 'tos');
  }

  Future<void> playLeftNausea() async {
    await playLeftAsset(voiceNauseaAsset, logName: 'nausea');
  }

  Future<void> playStethoscopeWheezing() async {
    await playRightAsset(stethoscopeWheezingAsset, logName: 'wheezing');
  }

  Future<void> playStethoscopeHeart() async {
    await playRightAsset(stethoscopeHeartAsset, logName: 'heart');
  }

  Future<void> playLeftOnly() async {
    await playLeftCough();
  }

  Future<void> playRightOnly() async {
    await playStethoscopeHeart();
  }

  Future<void> playLeftAsset(String assetPath, {String? logName}) async {
    _logWithTime('playLeftAsset llamado: ${logName ?? assetPath}',
        level: LogLevel.info);

    try {
      if (_isPTTActive) {
        await stopPTT();
      }

      await _startPannedAsset(
        player: _leftPlayer,
        assetPath: assetPath,
        balance: -1.0,
        volume: _leftVolume,
      );

      _leftPlaying = true;
      await _syncWakeLock();
      notifyListeners();
    } catch (e, stack) {
      _logWithTime(
        'Error en playLeftAsset: $e\n$stack',
        level: LogLevel.error,
      );
    }
  }

  Future<void> playRightAsset(String assetPath, {String? logName}) async {
    _logWithTime('playRightAsset llamado: ${logName ?? assetPath}',
        level: LogLevel.info);

    try {
      if (_isPTTActive) {
        await stopPTT();
      }

      await _startPannedAsset(
        player: _rightPlayer,
        assetPath: assetPath,
        balance: 1.0,
        volume: _rightVolume,
      );

      _rightPlaying1 = true;
      _rightPlaying2 = false;
      await _syncWakeLock();
      notifyListeners();
    } catch (e, stack) {
      _logWithTime(
        'Error en playRightAsset: $e\n$stack',
        level: LogLevel.error,
      );
    }
  }

  Future<void> playLeftFile(String filePath, {String? logName}) async {
    _logWithTime('playLeftFile llamado: ${logName ?? filePath}',
        level: LogLevel.info);

    try {
      if (_isPTTActive) {
        await stopPTT();
      }

      await _startPannedDeviceFile(
        player: _leftPlayer,
        filePath: filePath,
        balance: -1.0,
        volume: _leftVolume,
      );

      _leftPlaying = true;
      await _syncWakeLock();
      notifyListeners();
    } catch (e, stack) {
      _logWithTime(
        'Error en playLeftFile: $e\n$stack',
        level: LogLevel.error,
      );
    }
  }

  Future<void> playRightFile(String filePath, {String? logName}) async {
    _logWithTime('playRightFile llamado: ${logName ?? filePath}',
        level: LogLevel.info);

    try {
      if (_isPTTActive) {
        await stopPTT();
      }

      await _startPannedDeviceFile(
        player: _rightPlayer,
        filePath: filePath,
        balance: 1.0,
        volume: _rightVolume,
      );

      _rightPlaying1 = true;
      _rightPlaying2 = false;
      await _syncWakeLock();
      notifyListeners();
    } catch (e, stack) {
      _logWithTime(
        'Error en playRightFile: $e\n$stack',
        level: LogLevel.error,
      );
    }
  }

  Future<void> playBothOnRight() async {
    _logWithTime('playBothOnRight llamado', level: LogLevel.info);

    try {
      if (_isPTTActive) {
        await stopPTT();
      }

      await _waitUntilPrimed();
      await _configureSessionForPlayback();

      await _rightPlayer.stop();
      await _rightPlayer2.stop();

      await Future.delayed(const Duration(milliseconds: 50));

      await _rightPlayer.setSourceAsset(stethoscopeHeartAsset);
      await _rightPlayer2.setSourceAsset(voiceCoughAsset);

      await _rightPlayer.setBalance(1.0);
      await _rightPlayer2.setBalance(1.0);

      await _rightPlayer.setVolume(_rightVolume);
      await _rightPlayer2.setVolume(_rightVolume);

      await _rightPlayer.seek(Duration.zero);
      await _rightPlayer2.seek(Duration.zero);

      await _rightPlayer.resume();
      await _rightPlayer2.resume();

      await Future.delayed(const Duration(milliseconds: 30));

      await _rightPlayer.setBalance(1.0);
      await _rightPlayer2.setBalance(1.0);
      await _rightPlayer.setVolume(_rightVolume);
      await _rightPlayer2.setVolume(_rightVolume);

      await Future.delayed(const Duration(milliseconds: 120));

      await _rightPlayer.setBalance(1.0);
      await _rightPlayer2.setBalance(1.0);
      await _rightPlayer.setVolume(_rightVolume);
      await _rightPlayer2.setVolume(_rightVolume);

      _rightPlaying1 = true;
      _rightPlaying2 = true;

      await _syncWakeLock();
      notifyListeners();
    } catch (e, stack) {
      _logWithTime(
        'Error en playBothOnRight: $e\n$stack',
        level: LogLevel.error,
      );
    }
  }

  Future<void> stopLeft() async {
    try {
      await _leftPlayer.stop();
      _leftPlaying = false;

      await _leftPlayer.setBalance(-1.0);
      await _leftPlayer.setVolume(_leftVolume);

      await _syncWakeLock();
      notifyListeners();
    } catch (e, stack) {
      _logWithTime(
        'Error en stopLeft: $e\n$stack',
        level: LogLevel.error,
      );
    }
  }

  Future<void> stopRight() async {
    try {
      await _rightPlayer.stop();
      await _rightPlayer2.stop();

      _rightPlaying1 = false;
      _rightPlaying2 = false;

      await _rightPlayer.setBalance(1.0);
      await _rightPlayer2.setBalance(1.0);
      await _rightPlayer.setVolume(_rightVolume);
      await _rightPlayer2.setVolume(_rightVolume);

      await _syncWakeLock();
      notifyListeners();
    } catch (e, stack) {
      _logWithTime(
        'Error en stopRight: $e\n$stack',
        level: LogLevel.error,
      );
    }
  }

  Future<void> stop() async {
    await stopPTT();
    await stopLeft();
    await stopRight();
  }

  @override
  void dispose() {
    _leftPlayer.dispose();
    _rightPlayer.dispose();
    _rightPlayer2.dispose();

    try {
      _recorder.dispose();
    } catch (_) {}

    try {
      _player.dispose();
    } catch (_) {}

    unawaited(_nativePttChannel.invokeMethod('stopPtt'));

    WakelockPlus.disable();

    super.dispose();
  }
}
