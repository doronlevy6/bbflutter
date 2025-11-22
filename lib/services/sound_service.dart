import 'package:audioplayers/audioplayers.dart';

/// Service for playing sound effects throughout the app
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _soundEnabled = true;

  /// Enable or disable sound effects
  void setSoundEnabled(bool enabled) {
    _soundEnabled = enabled;
  }

  /// Play a button click sound
  Future<void> playButtonClick() async {
    if (!_soundEnabled) return;
    
    try {
      // For now, using a silent implementation
      // Sound files can be added to assets/sounds/ later
      // await _audioPlayer.play(AssetSource('sounds/click.mp3'), volume: 0.3);
    } catch (e) {
      // Silently fail if sound can't be played
      // This prevents sound errors from affecting app functionality
    }
  }

  /// Play a success sound
  Future<void> playSuccess() async {
    if (!_soundEnabled) return;
    
    try {
      // For now, using a silent implementation
      // await _audioPlayer.play(AssetSource('sounds/success.mp3'), volume: 0.4);
    } catch (e) {
      // Silently fail
    }
  }

  /// Dispose the audio player
  void dispose() {
    _audioPlayer.dispose();
  }
}
