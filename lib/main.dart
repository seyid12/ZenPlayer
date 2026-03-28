import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
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
      title: 'Evrensel Medya Oynatıcı',
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
      home: const AnaOynaticiEkrani(),
    );
  }
}

class AnaOynaticiEkrani extends StatefulWidget {
  const AnaOynaticiEkrani({super.key});

  @override
  State<AnaOynaticiEkrani> createState() => _AnaOynaticiEkraniState();
}

class _AnaOynaticiEkraniState extends State<AnaOynaticiEkrani> {
  late final player = Player();
  late final controller = VideoController(player);

  @override
  void initState() {
    super.initState();
    // Arka plan kontrolünü başlat
    setupBackgroundControls(player);
    player.open(
      Media(
        'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
      ),
    );
    player.play();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  void _muzikTestineGec() {
    player.open(
      Media('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'),
    );
    player.play();
  }

  void _videoTestineGec() {
    player.open(
      Media(
        'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
      ),
    );
    player.play();
  }

  // DOSYA SEÇİCİ FONKSİYONU
  Future<void> _dosyaSecVeOynat() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.media, // Sadece video ve ses dosyalarını göster
    );

    if (result != null && result.files.single.path != null) {
      String dosyaYolu = result.files.single.path!;

      // Seçilen yerel dosyayı oynatıcıda aç
      player.open(Media(dosyaYolu));
      player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Evrensel Medya Oynatıcı',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
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

          Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: const BoxDecoration(
              color: Color(0xFF2A2A3C),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _videoTestineGec,
                  icon: const Icon(Icons.movie_creation_rounded),
                  label: const Text("Videoya Geç"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _muzikTestineGec,
                  icon: const Icon(Icons.music_note_rounded),
                  label: const Text("Müziğe Geç"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    backgroundColor: const Color(0xFFFF6584),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      // DOSYA SEÇİCİ BUTONU (Sağ alt köşeye sabitlenir)
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _dosyaSecVeOynat,
        icon: const Icon(Icons.folder_open_rounded),
        label: const Text("Dosya Ekle"),
        backgroundColor: const Color(0xFF00C896),
        foregroundColor: Colors.white,
      ),
    );
  }
}
