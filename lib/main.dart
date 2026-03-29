import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:on_audio_query_forked/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'background_manager.dart';

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

class _AnaEkraniState extends State<AnaEkrani> with WidgetsBindingObserver {
  late final player = Player();
  late final controller = VideoController(player);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setupBackgroundControls(player);
    _hafizayiYukle();
  }

  // YAPAY HAFIZA YÜKLEMESİ (KALINAN YERDEN DEVAM ET)
  Future<void> _hafizayiYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMedia = prefs.getString('zenplayer_last_media');
    final lastPosition = prefs.getInt('zenplayer_last_position');

    if (lastMedia != null && lastMedia.isNotEmpty) {
      // Sesi sessiz sedasız (play: false) Player'a yükle
      player.open(Media(lastMedia), play: false);
      
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      final prefs = await SharedPreferences.getInstance();
      
      // O an listeden çalan medya varsa URL'sini ve konumunu milisaniye bazında hemen kaydet
      if (player.state.playlist.medias.isNotEmpty) {
        prefs.setString('zenplayer_last_media', player.state.playlist.medias[player.state.playlist.index].uri);
        prefs.setInt('zenplayer_last_position', player.state.position.inMilliseconds);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player.dispose();
    super.dispose();
  }

  // Kütüphaneden gelen dosyayı oynatıcıya atama fonksiyonu
  void _kutuphanedenOynat(String dosyaYolu) {
    if (player.state.playlist.medias.isEmpty) {
      player.open(Playlist([Media(dosyaYolu)]));
      player.play();
    } else {
      player.add(Media(dosyaYolu));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'ZenPlayer',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: const Color(0xFF1E1E2C),
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Color(0xFF00C896),
            labelColor: Color(0xFF00C896),
            unselectedLabelColor: Colors.white54,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(icon: Icon(Icons.play_circle_fill_rounded), text: "Oynatıcı"),
              Tab(icon: Icon(Icons.library_music_rounded), text: "Kütüphanem"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            OynaticiSekmesi(player: player, controller: controller),
            KutuphaneSekmesi(onOynatGonder: _kutuphanedenOynat),
          ],
        ),
      ),
    );
  }
}

class OynaticiSekmesi extends StatelessWidget {
  final Player player;
  final VideoController controller;

  const OynaticiSekmesi({super.key, required this.player, required this.controller});

  Future<void> _dosyaSecVeOynat() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final eklenenMedya = result.files.map((file) => Media(file.path!)).toList();
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
                    BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10)),
                  ],
                ),
                child: MaterialVideoControlsTheme(
                  normal: MaterialVideoControlsThemeData(
                    buttonBarButtonColor: Colors.white,
                    buttonBarButtonSize: 24.0,
                    bottomButtonBar: [
                      const MaterialPositionIndicator(),
                      const Spacer(),
                      
                      // HIZLANDIRMA (SPEED) BUTONU
                      StatefulBuilder(
                        builder: (context, setState) {
                          return IconButton(
                            icon: Icon(Icons.speed_rounded, color: player.state.rate > 1.0 ? const Color(0xFF00C896) : Colors.white),
                            tooltip: "Hız: ${player.state.rate}x",
                            onPressed: () {
                              final rate = player.state.rate;
                              final newRate = rate == 1.0 ? 1.5 : (rate == 1.5 ? 2.0 : 1.0);
                              player.setRate(newRate);
                              setState(() {}); // ikonu/tooltipi güncellemek için
                            },
                          );
                        }
                      ),
                      
                      // 10 SANİYE GERİ SARMA BUTONU
                      IconButton(
                        icon: const Icon(Icons.replay_10_rounded),
                        color: Colors.white,
                        tooltip: "10 Saniye Geri",
                        onPressed: () {
                          final currentPos = player.state.position;
                          player.seek(currentPos - const Duration(seconds: 10));
                        },
                      ),

                      // 10 SANİYE İLERİ SARMA BUTONU
                      IconButton(
                        icon: const Icon(Icons.forward_10_rounded),
                        color: Colors.white,
                        tooltip: "10 Saniye İleri",
                        onPressed: () {
                          final currentPos = player.state.position;
                          player.seek(currentPos + const Duration(seconds: 10));
                        },
                      ),

                      const MaterialFullscreenButton(),
                    ],
                  ),
                  fullscreen: const MaterialVideoControlsThemeData(
                    // Tam Ekran ayarında da UI kalmasını isterseniz buraya da aynısını ekleyebilirsiniz.
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
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
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.only(top: 25, left: 20, right: 20),
              decoration: const BoxDecoration(
                color: Color(0xFF2A2A3C),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Çalma Listesi (Kuyruk)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 15),
                  Expanded(
                    child: StreamBuilder<Playlist>(
                      stream: player.stream.playlist,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.medias.isEmpty) {
                          return const Center(
                            child: Text(
                              "Kuyruk tamamen boş...\nLütfen üst sekmeden Kütüphane'ye gidip arşivinize göz atın.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54, fontSize: 16),
                            ),
                          );
                        }
                        return ListView.builder(
                          itemCount: snapshot.data!.medias.length,
                          itemBuilder: (context, index) {
                            final media = snapshot.data!.medias[index];
                            final isPlaying = index == snapshot.data!.index;
                            final dosyaAdi = media.uri.split('/').last.split('\\').last;

                            return Card(
                              color: isPlaying ? const Color(0xFF6C63FF).withOpacity(0.2) : Colors.transparent,
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                                side: BorderSide(color: isPlaying ? const Color(0xFF6C63FF).withOpacity(0.5) : Colors.transparent, width: 1.5),
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: isPlaying ? const Color(0xFF6C63FF) : Colors.white12, shape: BoxShape.circle),
                                  child: Icon(isPlaying ? Icons.play_arrow_rounded : Icons.audiotrack_rounded, color: isPlaying ? Colors.white : Colors.white54, size: 20),
                                ),
                                title: Text(dosyaAdi, style: TextStyle(color: isPlaying ? Colors.white : Colors.white70, fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
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
  final Function(String) onOynatGonder;
  const KutuphaneSekmesi({super.key, required this.onOynatGonder});

  @override
  State<KutuphaneSekmesi> createState() => _KutuphaneSekmesiState();
}

class _KutuphaneSekmesiState extends State<KutuphaneSekmesi> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  bool _iznimVarMi = false;

  @override
  void initState() {
    super.initState();
    _izinleriKontrolEt();
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
      future: _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C896)));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text("Telefonunuzda medya dosyası bulunamadı.", style: TextStyle(color: Colors.white70)),
          );
        }

        final songs = snapshot.data!;
        
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 20),
              leading: QueryArtworkWidget(
                id: song.id,
                type: ArtworkType.AUDIO,
                nullArtworkWidget: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white54, size: 25),
                ),
              ),
              title: Text(
                song.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                song.artist ?? "Bilinmeyen Sanatçı",
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF00C896)),
                onPressed: () {
                  widget.onOynatGonder(song.data);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("${song.title} sıraya eklendi!"),
                      backgroundColor: const Color(0xFF00C896),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
              onTap: () {
                widget.onOynatGonder(song.data);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("${song.title} oynatılıyor!"),
                      backgroundColor: const Color(0xFF6C63FF),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                  // Oynatıcı sekmesine anında atla
                  DefaultTabController.of(context).animateTo(0);
              },
            );
          },
        );
      },
    );
  }
}
