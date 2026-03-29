import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:on_audio_query_forked/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'background_manager.dart';

Future<List<SongModel>>? _cachedSarkilarFuture;
Future<List<SongModel>> getCachedSarkilar(OnAudioQuery query) {
  _cachedSarkilarFuture ??= query.querySongs(
    sortType: null,
    orderType: OrderType.ASC_OR_SMALLER,
    uriType: UriType.EXTERNAL,
    ignoreCase: true,
  );
  return _cachedSarkilarFuture!;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MedyaOynaticiApp());
}

class MedyaOynaticiApp extends StatelessWidget {
  const MedyaOynaticiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZenPlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E2C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const AnaEkrani(),
    );
  }
}

// Tüm state'i en üstte tutan ana kontrolcü
class AnaEkrani extends StatefulWidget {
  const AnaEkrani({super.key});

  @override
  State<AnaEkrani> createState() => _AnaEkraniState();
}

class _AnaEkraniState extends State<AnaEkrani> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final player = Player();
  late final controller = VideoController(player);
  late final TabController _tabController = TabController(length: 3, vsync: this);

  // UYKU ZAMANLAYICISI (SLEEP TIMER) DURUMLARI
  Timer? _uykuZamanlayici;
  DateTime? _uykuKapanisVakti;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setupBackgroundControls(player);
    _hafizayiYukle();
    
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  // YAPAY HAFIZA YÜKLEMESİ (KALINAN YERDEN DEVAM ET)
  Future<void> _hafizayiYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMedia = prefs.getString('zenplayer_last_media');
    final lastPosition = prefs.getInt('zenplayer_last_position');
    final lastName = prefs.getString('zenplayer_last_title');
    final lastArtist = prefs.getString('zenplayer_last_artist');

    if (lastMedia != null && lastMedia.isNotEmpty) {
      final m = Media(
        lastMedia,
        extras: {'title': ?lastName, 'artist': ?lastArtist},
      );
      // Sesi sessiz sedasız (play: false) Player'a yükle
      player.open(m, play: false);

      // Medyanın yüklenmesini milisaniye cinsinden yakalayarak atlama (seek) yap
      player.stream.duration.listen((d) {
        if (d.inMilliseconds > 0 && lastPosition != null) {
          player.seek(Duration(milliseconds: lastPosition));
        }
      });
    }
  }

  // UYGULAMA ARKA PLANA ATILDIĞINDA VEYA KAPATILDIĞINDA TETİKLENEN HAFIZA KAYDI
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      final prefs = await SharedPreferences.getInstance();

      // O an listeden çalan medya varsa URL'sini, konumunu ve ismini kaydet
      if (player.state.playlist.medias.isNotEmpty) {
        final currentMedia =
            player.state.playlist.medias[player.state.playlist.index];
        prefs.setString('zenplayer_last_media', currentMedia.uri);
        prefs.setInt(
          'zenplayer_last_position',
          player.state.position.inMilliseconds,
        );

        final title = currentMedia.extras?['title'] as String?;
        final artist = currentMedia.extras?['artist'] as String?;
        if (title != null) prefs.setString('zenplayer_last_title', title);
        if (artist != null) prefs.setString('zenplayer_last_artist', artist);
      }
    }
  }

  @override
  void dispose() {
    _uykuZamanlayici?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    player.dispose();
    super.dispose();
  }

  // Kütüphaneden gelen dosyayı oynatıcıya atama fonksiyonu
  void _kutuphanedenOynat(String dosyaYolu, [String? title, String? artist]) {
    final media = Media(
      dosyaYolu,
      extras: {'title': ?title, 'artist': ?artist},
    );

    if (player.state.playlist.medias.isEmpty) {
      player.open(Playlist([media]));
      player.play();
    } else {
      player.add(media);
    }
  }

  // UYKU ZAMANLAYICISI MOTORU
  void _zamanlayiciKur(int dakika) {
    _uykuZamanlayici?.cancel();
    if (dakika == 0) {
      setState(() {
        _uykuKapanisVakti = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Uyku Zamanlayıcısı İptal Edildi.")),
      );
      return;
    }

    setState(() {
      _uykuKapanisVakti = DateTime.now().add(Duration(minutes: dakika));
    });

    _uykuZamanlayici = Timer(Duration(minutes: dakika), () {
      player.pause();
      setState(() {
        _uykuKapanisVakti = null;
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Müzik $dakika dakika sonra duraklatılacak."),
        backgroundColor: const Color(0xFF6C63FF),
      ),
    );
  }

  void _zamanlayiciMenusuAc() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A2A3C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Uyku Zamanlayıcısı (Sleep Timer)",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.av_timer_rounded,
                  color: Colors.white54,
                ),
                title: const Text(
                  "15 Dakika Sonra Duraklat",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _zamanlayiciKur(15);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.av_timer_rounded,
                  color: Colors.white54,
                ),
                title: const Text(
                  "30 Dakika Sonra Duraklat",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _zamanlayiciKur(30);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.av_timer_rounded,
                  color: Colors.white54,
                ),
                title: const Text(
                  "45 Dakika Sonra Duraklat",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _zamanlayiciKur(45);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.av_timer_rounded,
                  color: Colors.white54,
                ),
                title: const Text(
                  "60 Dakika Sonra Duraklat",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _zamanlayiciKur(60);
                },
              ),
              if (_uykuKapanisVakti != null)
                ListTile(
                  leading: const Icon(
                    Icons.cancel_rounded,
                    color: Colors.pinkAccent,
                  ),
                  title: const Text(
                    "Zamanlayıcıyı İptal Et",
                    style: TextStyle(color: Colors.pinkAccent),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _zamanlayiciKur(0);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniPlayer() {
    return StreamBuilder<Playlist>(
      stream: player.stream.playlist,
      builder: (context, snapshot) {
        final playlist = snapshot.data ?? player.state.playlist;
        if (playlist.medias.isEmpty || _tabController.index == 0) {
          return const SizedBox.shrink();
        }

        final currentIndex = playlist.index;
        if (currentIndex < 0 || currentIndex >= playlist.medias.length) {
          return const SizedBox.shrink();
        }

        final currentMedia = playlist.medias[currentIndex];
        final title = currentMedia.extras?['title'] as String? ?? "Bilinmeyen Şarkı";
        final artist = currentMedia.extras?['artist'] as String? ?? "Bilinmeyen Sanatçı";

        return GestureDetector(
          onTap: () => _tabController.animateTo(0),
          child: Container(
            color: const Color(0xFF2A2A3C),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.music_note_rounded, color: Color(0xFF00C896)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(artist, style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  builder: (context, playingSnapshot) {
                    final isPlaying = playingSnapshot.data ?? player.state.playing;
                    return IconButton(
                      icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                      onPressed: () => player.playOrPause(),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZenPlayer', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFF1E1E2C),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.timer_rounded, color: _uykuKapanisVakti != null ? const Color(0xFF00C896) : Colors.white54),
            tooltip: "Uyku Zamanlayıcısı",
            onPressed: _zamanlayiciMenusuAc,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00C896),
          labelColor: const Color(0xFF00C896),
          unselectedLabelColor: Colors.white54,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(icon: Icon(Icons.play_circle_fill_rounded), text: "Oynatıcı"),
            Tab(icon: Icon(Icons.library_music_rounded), text: "Kütüphanem"),
            Tab(icon: Icon(Icons.favorite_rounded), text: "Favoriler"),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                OynaticiSekmesi(player: player, controller: controller),
                KutuphaneSekmesi(onOynatGonder: _kutuphanedenOynat, player: player),
                FavorilerSekmesi(onOynatGonder: _kutuphanedenOynat, player: player),
              ],
            ),
          ),
          _buildMiniPlayer(),
        ],
      ),
    );
  }
}

class OynaticiSekmesi extends StatelessWidget {
  final Player player;
  final VideoController controller;

  const OynaticiSekmesi({
    super.key,
    required this.player,
    required this.controller,
  });

  Future<void> _dosyaSecVeOynat() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final eklenenMedya = result.files
          .map(
            (file) => Media(
              file.path!,
              extras: {'title': file.name, 'artist': 'Dosya Klasörü'},
            ),
          )
          .toList();
      if (player.state.playlist.medias.isEmpty) {
        player.open(Playlist(eklenenMedya));
        player.play();
      } else {
        for (var media in eklenenMedya) {
          player.add(media);
        }
      }
    }
  }

  List<Widget> _buildTopBar(BuildContext context, Player player) {
    return [
      const Spacer(), // Sola boşluk at, butonları en sağa daya
      
      // HIZLANDIRMA (SPEED) BUTONU
      StatefulBuilder(
        builder: (context, setState) {
          return IconButton(
            icon: Icon(
              Icons.speed_rounded,
              color: player.state.rate > 1.0 ? const Color(0xFF00C896) : Colors.white,
            ),
            tooltip: "Hız: ${player.state.rate}x",
            onPressed: () {
              final rate = player.state.rate;
              final newRate = rate == 1.0 ? 1.5 : (rate == 1.5 ? 2.0 : 1.0);
              player.setRate(newRate);
              setState(() {});
            },
          );
        },
      ),

      // ALTYAZI SEÇİMİ (SUBTITLE MENU)
      StreamBuilder<Tracks>(
        stream: player.stream.tracks,
        builder: (context, snapshot) {
          final tracks = snapshot.data?.subtitle ?? [];
          if (tracks.isEmpty) {
            return const IconButton(
              icon: Icon(Icons.subtitles_off_rounded, color: Colors.white24),
              onPressed: null,
              tooltip: "Bu medyada altyazı yok",
            );
          }
          return PopupMenuButton<SubtitleTrack>(
            icon: const Icon(Icons.subtitles_rounded, color: Colors.white),
            tooltip: "Altyazı Seç",
            onSelected: (track) {
              player.setSubtitleTrack(track);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Altyazı Seçildi: ${track.language ?? track.title ?? 'Açık'}"),
                  backgroundColor: const Color(0xFF6C63FF),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            itemBuilder: (context) {
              final items = tracks.map((track) {
                return PopupMenuItem(
                  value: track,
                  child: Text(track.title ?? track.language ?? "Varsayılan Altyazı"),
                );
              }).toList();
              items.insert(0, PopupMenuItem(value: SubtitleTrack.no(), child: const Text("Kapat (Off)")));
              items.insert(1, PopupMenuItem(value: SubtitleTrack.auto(), child: const Text("Sistem (Auto)")));
              return items;
            },
          );
        },
      ),
      const SizedBox(width: 8), // Sağ kenera çok bitişmesin
    ];
  }

  List<Widget> _buildBottomBar(BuildContext context, Player player) {
    return [
      // ÖNCEKİ ŞARKI BUTONU
      IconButton(
        icon: const Icon(Icons.skip_previous_rounded),
        color: Colors.white,
        tooltip: "Önceki",
        onPressed: () => player.previous(),
      ),

      // 10 SANİYE GERİ SARMA BUTONU (Çubuğun Solunda)
      IconButton(
        icon: const Icon(Icons.replay_10_rounded),
        color: Colors.white,
        tooltip: "10 Saniye Geri",
        onPressed: () {
          final currentPos = player.state.position;
          player.seek(currentPos - const Duration(seconds: 10));
        },
      ),

      // ZAMAN ÇUBUĞU (Ortada tüm boşluğu kaplar ve 5px yukarıda durur)
      const Expanded(
        child: Padding(
          padding: EdgeInsets.only(bottom: 5.0),
          child: MaterialPositionIndicator(),
        ),
      ),

      // 10 SANİYE İLERİ SARMA BUTONU (Çubuğun Sağında)
      IconButton(
        icon: const Icon(Icons.forward_10_rounded),
        color: Colors.white,
        tooltip: "10 Saniye İleri",
        onPressed: () {
          final currentPos = player.state.position;
          player.seek(currentPos + const Duration(seconds: 10));
        },
      ),

      // SONRAKİ ŞARKI BUTONU
      IconButton(
        icon: const Icon(Icons.skip_next_rounded),
        color: Colors.white,
        tooltip: "Sonraki",
        onPressed: () => player.next(),
      ),

      // TAM EKRAN BUTONU
      const MaterialFullscreenButton(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: MaterialVideoControlsTheme(
                  normal: MaterialVideoControlsThemeData(
                    volumeGesture: true,
                    brightnessGesture: true,
                    buttonBarButtonColor: Colors.white,
                    buttonBarButtonSize: 24.0,
                    bottomButtonBarMargin: const EdgeInsets.only(bottom: 20.0, left: 16.0, right: 16.0),
                    topButtonBarMargin: const EdgeInsets.only(top: 10.0, left: 16.0, right: 16.0),
                    topButtonBar: _buildTopBar(context, player),
                    bottomButtonBar: _buildBottomBar(context, player),
                  ),
                  fullscreen: MaterialVideoControlsThemeData(
                    volumeGesture: true,
                    brightnessGesture: true,
                    buttonBarButtonColor: Colors.white,
                    buttonBarButtonSize: 24.0,
                    bottomButtonBarMargin: const EdgeInsets.only(bottom: 20.0, left: 16.0, right: 16.0),
                    topButtonBarMargin: const EdgeInsets.only(top: 10.0, left: 16.0, right: 16.0),
                    topButtonBar: _buildTopBar(context, player),
                    bottomButtonBar: _buildBottomBar(context, player),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox.expand(
                      child: Video(
                        controller: controller,
                        pauseUponEnteringBackgroundMode: false,
                        resumeUponEnteringForegroundMode: true,
                        fill: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.only(top: 25, left: 20, right: 20),
              decoration: const BoxDecoration(
                color: Color(0xFF2A2A3C),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Çalma Listesi (Kuyruk)",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Expanded(
                    child: StreamBuilder<Playlist>(
                      stream: player.stream.playlist,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData ||
                            snapshot.data!.medias.isEmpty) {
                          return const Center(
                            child: Text(
                              "Kuyruk tamamen boş...\nLütfen üst sekmeden Kütüphane'ye gidip arşivinize göz atın.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 16,
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          itemCount: snapshot.data!.medias.length,
                          itemBuilder: (context, index) {
                            final media = snapshot.data!.medias[index];
                            final isPlaying = index == snapshot.data!.index;
                            final dosyaAdi = media.uri
                                .split('/')
                                .last
                                .split('\\')
                                .last;

                            return Card(
                              color: isPlaying
                                  ? const Color(0xFF6C63FF).withOpacity(0.2)
                                  : Colors.transparent,
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                                side: BorderSide(
                                  color: isPlaying
                                      ? const Color(0xFF6C63FF).withOpacity(0.5)
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isPlaying
                                        ? const Color(0xFF6C63FF)
                                        : Colors.white12,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isPlaying
                                        ? Icons.play_arrow_rounded
                                        : Icons.audiotrack_rounded,
                                    color: isPlaying
                                        ? Colors.white
                                        : Colors.white54,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  dosyaAdi,
                                  style: TextStyle(
                                    color: isPlaying
                                        ? Colors.white
                                        : Colors.white70,
                                    fontWeight: isPlaying
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white38,
                                    size: 20,
                                  ),
                                  onPressed: () => player.remove(index),
                                ),
                                onTap: () => player.jump(index),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _dosyaSecVeOynat,
        tooltip: "Harici Dosya Ekle",
        backgroundColor: const Color(0xFF00C896),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class KutuphaneSekmesi extends StatefulWidget {
  final Function(String, [String?, String?]) onOynatGonder;
  final Player player;
  const KutuphaneSekmesi({super.key, required this.onOynatGonder, required this.player});

  @override
  State<KutuphaneSekmesi> createState() => _KutuphaneSekmesiState();
}

class _KutuphaneSekmesiState extends State<KutuphaneSekmesi> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  bool _iznimVarMi = false;
  List<String> _favoriIdler = [];

  @override
  void initState() {
    super.initState();
    _izinleriKontrolEt();
    _favorileriYukle();
  }

  Future<void> _favorileriYukle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favoriIdler = prefs.getStringList('zenplayer_favorites') ?? [];
    });
  }

  Future<void> _favoriDegistir(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriIdler.contains(id)) {
        _favoriIdler.remove(id);
      } else {
        _favoriIdler.add(id);
      }
    });
    await prefs.setStringList('zenplayer_favorites', _favoriIdler);
  }

  Future<void> _izinleriKontrolEt() async {
    bool p = await _audioQuery.permissionsStatus();
    if (!p) {
      p = await _audioQuery.permissionsRequest();
    }

    // Gelişmiş güvenlikler (Android 13+) için ek izini kontrol et
    if (Platform.isAndroid || Platform.isIOS) {
      await Permission.audio.request();
      await Permission.videos.request();
      await Permission.storage.request();
    }

    setState(() {
      _iznimVarMi = p;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_iznimVarMi) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _izinleriKontrolEt,
          icon: const Icon(Icons.security_rounded),
          label: const Text("Medya Tarama İzni Ver"),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
          ),
        ),
      );
    }

    return FutureBuilder<List<SongModel>>(
      future: getCachedSarkilar(_audioQuery),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00C896)),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              "Telefonunuzda medya dosyası bulunamadı.",
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        final songs = snapshot.data!;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            return StreamBuilder<Playlist>(
              stream: widget.player.stream.playlist,
              builder: (context, playlistSnapshot) {
                final playlist = playlistSnapshot.data ?? widget.player.state.playlist;
                final isPlaying = playlist.medias.isNotEmpty && 
                                  playlist.index >= 0 && 
                                  playlist.index < playlist.medias.length && 
                                  playlist.medias[playlist.index].uri == song.data;
                
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 20,
                  ),
                  leading: QueryArtworkWidget(
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    nullArtworkWidget: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isPlaying ? const Color(0xFF00C896).withOpacity(0.2) : Colors.white12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isPlaying ? Icons.play_circle_fill_rounded : Icons.music_note_rounded,
                        color: isPlaying ? const Color(0xFF00C896) : Colors.white54,
                        size: 25,
                      ),
                    ),
                  ),
                  title: Text(
                    song.title,
                    style: TextStyle(
                      color: isPlaying ? const Color(0xFF00C896) : Colors.white,
                      fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              subtitle: Text(
                song.artist ?? "Bilinmeyen Sanatçı",
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _favoriIdler.contains(song.id.toString())
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: _favoriIdler.contains(song.id.toString())
                          ? Colors.pinkAccent
                          : Colors.white54,
                    ),
                    onPressed: () => _favoriDegistir(song.id.toString()),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: Color(0xFF00C896),
                    ),
                    onPressed: () {
                      widget.onOynatGonder(song.data, song.title, song.artist);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("${song.title} sıraya eklendi!"),
                          backgroundColor: const Color(0xFF00C896),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
              onTap: () {
                widget.onOynatGonder(song.data, song.title, song.artist);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("${song.title} oynatılıyor!"),
                    backgroundColor: const Color(0xFF6C63FF),
                    duration: const Duration(seconds: 1),
                  ),
                );
                DefaultTabController.maybeOf(context)?.animateTo(0);
              },
            );
          },
        );
      },
    );
  },
);
  }
}

class FavorilerSekmesi extends StatefulWidget {
  final Function(String, [String?, String?]) onOynatGonder;
  final Player player;
  const FavorilerSekmesi({super.key, required this.onOynatGonder, required this.player});

  @override
  State<FavorilerSekmesi> createState() => _FavorilerSekmesiState();
}

class _FavorilerSekmesiState extends State<FavorilerSekmesi> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  List<String> _favoriIdler = [];
  bool _iznimVarMi = false;

  @override
  void initState() {
    super.initState();
    _izinleriKontrolEt();
    _favorileriYukle();
  }

  Future<void> _izinleriKontrolEt() async {
    bool p = await _audioQuery.permissionsStatus();
    setState(() {
      _iznimVarMi = p;
    });
  }

  Future<void> _izinleriIste() async {
    await _audioQuery.permissionsRequest();
    if (Platform.isAndroid || Platform.isIOS) {
      await Permission.audio.request();
      await Permission.videos.request();
      await Permission.storage.request();
    }
    _izinleriKontrolEt();
  }

  Future<void> _favorileriYukle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favoriIdler = prefs.getStringList('zenplayer_favorites') ?? [];
    });
  }

  Future<void> _favoriDegistir(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriIdler.contains(id)) {
        _favoriIdler.remove(id);
      } else {
        _favoriIdler.add(id);
      }
    });
    await prefs.setStringList('zenplayer_favorites', _favoriIdler);
  }

  @override
  Widget build(BuildContext context) {
    if (!_iznimVarMi) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _izinleriIste,
          icon: const Icon(Icons.security_rounded),
          label: const Text("Medya Tarama İzni Ver"),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
          ),
        ),
      );
    }

    return FutureBuilder<List<SongModel>>(
      future: getCachedSarkilar(_audioQuery),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00C896)),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              "Telefonunuzda medya dosyası bulunamadı.",
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        final tumSarkilar = snapshot.data!;
        final favSongs = tumSarkilar
            .where((s) => _favoriIdler.contains(s.id.toString()))
            .toList();

        if (favSongs.isEmpty) {
          return const Center(
            child: Text(
              "Henüz favorilere eklediğiniz bir müzik yok.\nKütüphaneden ❤️ butonuna basarak ekleyebilir veya Favorilerden çıkarabilirsiniz.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: favSongs.length,
          itemBuilder: (context, index) {
            final song = favSongs[index];
            return StreamBuilder<Playlist>(
              stream: widget.player.stream.playlist,
              builder: (context, playlistSnapshot) {
                final playlist = playlistSnapshot.data ?? widget.player.state.playlist;
                final isPlaying = playlist.medias.isNotEmpty && 
                                  playlist.index >= 0 && 
                                  playlist.index < playlist.medias.length && 
                                  playlist.medias[playlist.index].uri == song.data;
                                  
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 20,
                  ),
                  leading: QueryArtworkWidget(
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    nullArtworkWidget: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isPlaying ? const Color(0xFF00C896).withOpacity(0.2) : Colors.white12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isPlaying ? Icons.play_circle_fill_rounded : Icons.music_note_rounded,
                        color: isPlaying ? const Color(0xFF00C896) : Colors.white54,
                        size: 25,
                      ),
                    ),
                  ),
                  title: Text(
                    song.title,
                    style: TextStyle(
                      color: isPlaying ? const Color(0xFF00C896) : Colors.white,
                      fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              subtitle: Text(
                song.artist ?? "Bilinmeyen Sanatçı",
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _favoriIdler.contains(song.id.toString())
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: _favoriIdler.contains(song.id.toString())
                          ? Colors.pinkAccent
                          : Colors.white54,
                    ),
                    onPressed: () => _favoriDegistir(song.id.toString()),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: Color(0xFF00C896),
                    ),
                    onPressed: () {
                      widget.onOynatGonder(song.data, song.title, song.artist);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("${song.title} sıraya eklendi!"),
                          backgroundColor: const Color(0xFF00C896),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
              onTap: () {
                widget.onOynatGonder(song.data, song.title, song.artist);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("${song.title} oynatılıyor!"),
                    backgroundColor: const Color(0xFF6C63FF),
                    duration: const Duration(seconds: 1),
                  ),
                );
                DefaultTabController.maybeOf(context)?.animateTo(0);
              },
            );
          },
        );
      },
    );
  },
);
  }
}
