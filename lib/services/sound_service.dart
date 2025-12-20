import 'dart:html' as html;

/// Service for playing sound effects throughout the app
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  bool _soundEnabled = true;

  /// Enable or disable sound effects
  void setSoundEnabled(bool enabled) {
    _soundEnabled = enabled;
  }

  bool get soundEnabled => _soundEnabled;

  /// Play buzzer sound for end of period/game
  Future<void> playBuzzer({int type = 0}) async {
    if (!_soundEnabled) return;
    
    try {
      String url;
      switch (type) {
        case 0: // Long buzzer
          url = 'https://www.soundjay.com/buttons/button-10.mp3';
          break;
        case 1: // Short buzzer
          url = 'https://www.soundjay.com/buttons/button-35.mp3';
          break;
        case 2: // Triple beep
          url = 'https://www.soundjay.com/buttons/button-21.mp3';
          break;
        default:
          url = 'https://www.soundjay.com/buttons/button-10.mp3';
      }
      final audio = html.AudioElement(url)..volume = 1.0;
      await audio.play();
    } catch (e) {
      print('Error playing buzzer: $e');
    }
  }

  /// Play warning sound before period ends
  Future<void> playWarning({int type = 0}) async {
    if (!_soundEnabled) return;
    
    try {
      String url;
      switch (type) {
        case 0: // Single beep
          url = 'https://www.soundjay.com/buttons/button-35.mp3';
          break;
        case 1: // Double beep
          url = 'https://www.soundjay.com/buttons/button-10.mp3';
          break;
        case 2: // Whistle
          url = 'https://www.soundjay.com/buttons/button-21.mp3';
          break;
        default:
          url = 'https://www.soundjay.com/buttons/button-35.mp3';
      }
      final audio = html.AudioElement(url)..volume = 0.8;
      await audio.play();
    } catch (e) {
      print('Error playing warning: $e');
    }
  }

  /// Play a button click sound
  Future<void> playButtonClick() async {
    if (!_soundEnabled) return;
    
    try {
      final audio = html.AudioElement('https://www.soundjay.com/buttons/button-35.mp3')..volume = 0.3;
      await audio.play();
    } catch (e) {
      // Silently fail if sound can't be played
    }
  }

  /// Play a success sound
  Future<void> playSuccess() async {
    if (!_soundEnabled) return;
    
    try {
      final audio = html.AudioElement('https://www.soundjay.com/buttons/button-10.mp3')..volume = 0.4;
      await audio.play();
    } catch (e) {
      // Silently fail
    }
  }
}
