import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:audio_session/audio_session.dart' as session;
import 'package:sound_stream/sound_stream.dart';
import 'package:permission_handler/permission_handler.dart';

class PannedAudioService extends ChangeNotifier {
  // --------------------------------------------------------------------------
  // MP3 players (unchanged)
  // --------------------------------------------------------------------------
  final ap.AudioPlayer _leftOnlyPlayer = ap.AudioPlayer();
  final ap.AudioPlayer _rightPlayer1 = ap.AudioPlayer();
  final ap.AudioPlayer _rightPlayer2 = ap.AudioPlayer();

  // --------------------------------------------------------------------------
  // PTT using sound_stream (direct streaming, no file I/O)
  // --------------------------------------------------------------------------
  final RecorderStream _recorder = RecorderStream();
  final PlayerStream _player = PlayerStream();
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  bool _isPTTActive = false;

  // Headset detection
  bool _isHeadsetConnected = false;
  bool get isHeadsetConnected => _isHeadsetConnected;
  bool get isPTTActive => _isPTTActive;

  PannedAudioService() {
    _init();
  }

  Future<void> _init() async {
    // 1. Configure audio session for playback (initial state)
    final audioSession = await session.AudioSession.instance;
    await _configureSessionForPlayback();

    // 2. Listen for headset changes
    audioSession.devicesStream.listen((devices) {
      _handleDevicesChanged(devices.toList());
    });

    await audioSession.setActive(true);

    // 3. Initialize sound_stream recorder and player with same sample rate
    try {
      await _recorder.initialize(sampleRate: 16000);
      await _player.initialize(sampleRate: 16000);
      debugPrint('sound_stream initialized (recorder & player)');
    } catch (e) {
      debugPrint('sound_stream init error: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Audio session configurations
  // --------------------------------------------------------------------------
  Future<void> _configureSessionForPlayback() async {
    final audioSession = await session.AudioSession.instance;
    await audioSession.configure(session.AudioSessionConfiguration(
      avAudioSessionCategory: session.AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions:
          session.AVAudioSessionCategoryOptions.defaultToSpeaker |
              session.AVAudioSessionCategoryOptions.allowBluetooth,
      androidAudioAttributes: const session.AndroidAudioAttributes(
        contentType: session.AndroidAudioContentType.music,
        usage: session.AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: session.AndroidAudioFocusGainType.gain,
    ));
  }

  Future<void> _configureSessionForPTT() async {
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
  }

  void _handleDevicesChanged(List<session.AudioDevice> devices) {
    final hasHeadset = devices.any((d) =>
        d.type == session.AudioDeviceType.wiredHeadset ||
        d.type == session.AudioDeviceType.wiredHeadphones ||
        d.type == session.AudioDeviceType.bluetoothA2dp ||
        d.type == session.AudioDeviceType.bluetoothSco);
    if (_isHeadsetConnected != hasHeadset) {
      _isHeadsetConnected = hasHeadset;
      notifyListeners();
    }
  }

  // --------------------------------------------------------------------------
  // PTT Implementation using sound_stream
  // --------------------------------------------------------------------------
  Future<void> startPTT() async {
    if (_isPTTActive) {
      debugPrint('PTT already active');
      return;
    }

    // Request microphone permission if not already granted
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw Exception('Microphone permission not granted');
    }

    try {
      // Switch audio session to play+record mode (enables echo cancellation)
      await _configureSessionForPTT();
      final audioSession = await session.AudioSession.instance;
      await audioSession.setActive(true);

      // Cancel any previous subscription to avoid leaks
      await _audioStreamSubscription?.cancel();

      // Connect the recorder's audio stream directly to the player
      _audioStreamSubscription = _recorder.audioStream.listen(
        (Uint8List data) {
          if (_isPTTActive) {
            _player.writeChunk(data);
          }
        },
        onError: (err) => debugPrint('Recorder audio stream error: $err'),
      );

      // Start the player first (it will wait for data)
      await _player.start();

      // Then start the recorder (it will begin pushing data)
      await _recorder.start();

      _isPTTActive = true;
      notifyListeners();
      debugPrint('PTT started (sound_stream)');
    } catch (e) {
      debugPrint('Error starting PTT: $e');
      await stopPTT(); // ensure clean state on error
      rethrow;
    }
  }

  Future<void> stopPTT() async {
    if (!_isPTTActive) return;

    _isPTTActive = false;
    notifyListeners();

    try {
      // Stop recorder (stops microphone capture)
      await _recorder.stop();

      // Cancel the stream subscription
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // Stop player (releases audio output)
      await _player.stop();

      // Restore playback‑only session (so MP3s route correctly)
      await _configureSessionForPlayback();
      debugPrint('PTT stopped, back to playback session');
    } catch (e) {
      debugPrint('Error stopping PTT: $e');
    }
  }

  // --------------------------------------------------------------------------
  // MP3 playback (unchanged)
  // --------------------------------------------------------------------------
  Future<void> playLeftOnly(String assetPath) async {
    await _leftOnlyPlayer.setBalance(-1.0);
    await _leftOnlyPlayer.play(ap.AssetSource(assetPath));
  }

  Future<void> playRightOnly(String assetPath) async {
    await _rightPlayer1.setBalance(1.0);
    await _rightPlayer1.play(ap.AssetSource(assetPath));
  }

  Future<void> playBothOnRight(String assetPath1, String assetPath2) async {
    await _rightPlayer1.setBalance(1.0);
    await _rightPlayer2.setBalance(1.0);
    await _rightPlayer1.play(ap.AssetSource(assetPath1));
    await _rightPlayer2.play(ap.AssetSource(assetPath2));
  }

  Future<void> stop() async {
    await stopPTT();
    await _leftOnlyPlayer.stop();
    await _rightPlayer1.stop();
    await _rightPlayer2.stop();
  }

  @override
  void dispose() {
    _audioStreamSubscription?.cancel();
    _recorder.dispose();
    _player.dispose();
    _leftOnlyPlayer.dispose();
    _rightPlayer1.dispose();
    _rightPlayer2.dispose();
    super.dispose();
  }
}
