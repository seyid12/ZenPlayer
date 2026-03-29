import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:smtc_windows/smtc_windows.dart';

// İleride lazım olursa diye handler tutucusu (uyarı vermemesi için kullanıldı)
AudioHandler? audioHandlerGlobal;

// Uygulama açılışında işletim sistemini algılayıp servisi bağlayan bölüm
Future<void> setupBackgroundControls(Player player) async {
  if (kIsWeb) return;

  if (Platform.isWindows) {
    // 1. WİNDOWS SMTC MOTORU
    await SMTCWindows.initialize();
    final smtc = SMTCWindows(
      config: const SMTCConfig(
        playEnabled: true,
        pauseEnabled: true,
        nextEnabled: true,
        prevEnabled: true,
        stopEnabled: true,
        fastForwardEnabled: false, // Eksik parametreler eklendi
        rewindEnabled: false, // Eksik parametreler eklendi
      ),
    );

    // SMTC Dinleyicileri (Kullanıcı klavyeden tuşa basarsa player'i çalıştırır)
    smtc.buttonPressStream.listen((event) {
      if (event == PressedButton.play) {
        player.play();
      } else if (event == PressedButton.pause) {
        player.pause();
      } else if (event == PressedButton.next) {
        player.next();
      } else if (event == PressedButton.previous) {
        player.previous();
      } else if (event == PressedButton.stop) {
        player.stop();
      }
    });

    // Player Dinleyicileri (Arayüzde Duraklatıldığında SMTC'ye "Ben durdum" der)
    player.stream.playing.listen((isPlaying) {
      smtc.setPlaybackStatus(
        // Büyük/küçük harf API farklılığı düzeltildi (Playing yerine playing)
        isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused,
      );
    });
  } else if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    // 2. MOBİL AUDIO SERVICE MOTORU
    audioHandlerGlobal = await AudioService.init(
      builder: () => MobileAudioHandler(player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.seyid.medya_oynatici.channel.audio',
        androidNotificationChannelName: 'Medya Oynatıcı Bildirimi',
        androidNotificationOngoing: true,
      ),
    );
  }
}

// Android/iOS tarafının yönetim sınıfı (BaseAudioHandler alt yapısı)
class MobileAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final Player player;

  MobileAudioHandler(this.player) {
    // 1- Android'in arka plan bildirimini çizebilmesi için ZORUNLU KİMLİK!
    mediaItem.add(
      const MediaItem(
        id: 'default_stream',
        album: 'Medya Oynatıcı Projesi',
        title: 'Ekranda Oynatılan Medya',
        artist: 'Canlı Oynatım',
      ),
    );

    // 2- Oynatım komutlarını Android'e bildiriyoruz
    player.stream.playing.listen((playing) {
      playbackState.add(
        playbackState.value.copyWith(
          playing: playing,
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
          ],
          systemActions: const {MediaAction.seek},
          processingState: AudioProcessingState.ready,
        ),
      );
    });

    // 3- Şarkı değiştiğinde kilit ekranını Dinamik verilerle (Extras çekmecesi) Güncelle
    player.stream.playlist.listen((playlist) {
      if (playlist.medias.isEmpty) return;
      
      final currentMedia = playlist.medias[playlist.index];
      final title = currentMedia.extras?['title'] as String? ?? currentMedia.uri.split('/').last.split('\\').last;
      final artist = currentMedia.extras?['artist'] as String? ?? 'Bilinmeyen Sanatçı';

      mediaItem.add(
        MediaItem(
          id: currentMedia.uri,
          album: 'ZenPlayer',
          title: title,
          artist: artist,
        ),
      );
    });
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() => player.stop();

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.previous();
}
