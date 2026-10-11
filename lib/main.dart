import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Allow all orientations on mobile
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MehraApp());
}

class MehraApp extends StatelessWidget {
  const MehraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mehra Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0D14),
        fontFamily: 'Segoe UI',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFF00E676),
          surface: Color(0xFF141522),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class MediaItem {
  final File file;
  final String name;
  final int sizeInBytes;
  final bool isVideo;
  Uint8List? thumbnail;

  MediaItem({
    required this.file,
    required this.name,
    required this.sizeInBytes,
    required this.isVideo,
    this.thumbnail,
  });

  String get formattedSize {
    if (sizeInBytes < 1024 * 1024) {
      return "${(sizeInBytes / 1024).toStringAsFixed(1)} KB";
    }
    return "${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB";
  }
}

// ---------------- HOME SCREEN ----------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<MediaItem> videos = [];
  List<MediaItem> audios = [];
  bool isLoading = true;
  bool isConverting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scanStorage();
  }

  Future<String> _getAudioOutputDir() async {
    if (Platform.isAndroid) {
      final musicDir = Directory('/storage/emulated/0/Music/MehraPlayer');
      if (!await musicDir.exists()) await musicDir.create(recursive: true);
      return musicDir.path;
    } else {
      final home = Platform.environment['USERPROFILE'] ?? 'C:';
      final dir = Directory('$home\\Music\\MehraPlayer');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir.path;
    }
  }

  Future<void> _scanStorage() async {
    setState(() => isLoading = true);
    List<Directory> targetDirs = [];

    if (Platform.isAndroid) {
      targetDirs = [
        Directory('/storage/emulated/0/DCIM'),
        Directory('/storage/emulated/0/Movies'),
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Music'),
        Directory('/storage/emulated/0/WhatsApp/Media'),
        Directory('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media'),
      ];
    } else {
      final home = Platform.environment['USERPROFILE'] ?? 'C:';
      targetDirs = [
        Directory('$home\\Videos'),
        Directory('$home\\Music'),
        Directory('$home\\Downloads'),
      ];
    }

    List<MediaItem> vList = [];
    List<MediaItem> aList = [];

    for (var dir in targetDirs) {
      if (dir.existsSync()) {
        try {
          final entries = dir.listSync(recursive: true, followLinks: false);
          for (var e in entries) {
            if (e is File) {
              final p = e.path.toLowerCase();
              final fname = e.path.split(Platform.pathSeparator).last;
              if (fname.startsWith('.')) continue;

              if (p.endsWith('.mp4') || p.endsWith('.mkv') || p.endsWith('.avi') || p.endsWith('.mov') || p.endsWith('.webm') || p.endsWith('.3gp')) {
                vList.add(MediaItem(
                  file: e,
                  name: fname,
                  sizeInBytes: e.lengthSync(),
                  isVideo: true,
                ));
              } else if (p.endsWith('.mp3') || p.endsWith('.wav') || p.endsWith('.m4a') || p.endsWith('.flac') || p.endsWith('.aac') || p.endsWith('.ogg')) {
                aList.add(MediaItem(
                  file: e,
                  name: fname,
                  sizeInBytes: e.lengthSync(),
                  isVideo: false,
                ));
              }
            }
          }
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        videos = vList;
        audios = aList;
        isLoading = false;
      });
    }

    for (var item in vList) {
      try {
        final thumb = await VideoThumbnail.thumbnailData(
          video: item.file.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 160,
          quality: 50,
        );
        if (mounted && thumb != null) {
          setState(() => item.thumbnail = thumb);
        }
      } catch (_) {}
    }
  }

  Future<void> _convertVideoToAudio(MediaItem videoItem) async {
    setState(() => isConverting = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Extracting audio from '${videoItem.name}'..."),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF1E1F30),
      ),
    );

    try {
      final outDir = await _getAudioOutputDir();
      final cleanName = videoItem.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      final outPath = Platform.isWindows
          ? '$outDir\\${cleanName}_audio_${DateTime.now().millisecondsSinceEpoch}.mp3'
          : '$outDir/${cleanName}_audio_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final res = await Process.run('ffmpeg', [
        '-i', videoItem.file.path,
        '-vn',
        '-acodec', 'libmp3lame',
        '-q:a', '2',
        outPath,
        '-y'
      ]);

      if (res.exitCode == 0) {
        await _scanStorage();
        if (mounted) {
          _tabController.animateTo(1);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Audio extract complete! Switched to Audio tab."),
              backgroundColor: Color(0xFF00E676),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Audio extraction failed. Check media file.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isConverting = false);
    }
  }

  void _openPlayer(List<MediaItem> list, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(playlist: list, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F101A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('M', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(width: 10),
            const Text('Mehra Player', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, letterSpacing: 0.5)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _scanStorage,
            tooltip: 'Refresh Library',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: Color(0xFFA78BFA)),
            tooltip: 'Browse',
            onPressed: () async {
              final res = await FilePicker.platform.pickFiles(type: FileType.media);
              if (res != null && res.files.single.path != null) {
                final file = File(res.files.single.path!);
                final isVid = !file.path.toLowerCase().endsWith('.mp3');
                final item = MediaItem(
                  file: file,
                  name: file.path.split(Platform.pathSeparator).last,
                  sizeInBytes: file.lengthSync(),
                  isVideo: isVid,
                );
                _openPlayer([item], 0);
              }
            },
          ),
          const SizedBox(width: 6),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF8B5CF6),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: [
            Tab(text: "All Videos (${videos.length})"),
            Tab(text: "All Audios (${audios.length})"),
          ],
        ),
      ),
      body: isLoading || isConverting
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                  const SizedBox(height: 14),
                  Text(
                    isConverting ? "Extracting Video to Audio (MP3)..." : "Scanning all device media...",
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildVideoList(),
                _buildAudioList(),
              ],
            ),
    );
  }

  Widget _buildVideoList() {
    if (videos.isEmpty) {
      return const Center(child: Text("Koi video nahi mili", style: TextStyle(color: Colors.white38)));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      itemCount: videos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = videos[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openPlayer(videos, i),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF141522),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 105,
                    height: 64,
                    color: const Color(0xFF1E1F30),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.thumbnail != null)
                          Image.memory(item.thumbnail!, fit: BoxFit.cover)
                        else
                          const Center(child: Icon(Icons.movie_rounded, color: Colors.white24, size: 28)),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text("HD", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white24),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text("Video", style: TextStyle(fontSize: 9.5, color: Colors.white70)),
                          ),
                          const SizedBox(width: 6),
                          Text(item.formattedSize, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.music_note_rounded, color: Color(0xFF00E676)),
                  tooltip: 'Convert to Audio (MP3)',
                  onPressed: () => _convertVideoToAudio(item),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAudioList() {
    if (audios.isEmpty) {
      return const Center(child: Text("Koi audio song nahi mila", style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      itemCount: audios.length,
      itemBuilder: (context, i) {
        final item = audios[i];
        return Card(
          color: const Color(0xFF141522),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.white.withOpacity(0.04)),
          ),
          child: ListTile(
            onTap: () => _openPlayer(audios, i),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.music_note_rounded, color: Color(0xFF8B5CF6)),
            ),
            title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
            subtitle: Text(item.formattedSize, style: const TextStyle(fontSize: 11, color: Colors.white38)),
            trailing: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF00E676), size: 28),
          ),
        );
      },
    );
  }
}

// ---------------- RESPONSIVE PLAYER SCREEN (Auto Landscape / Portrait) ----------------
class PlayerScreen extends StatefulWidget {
  final List<MediaItem> playlist;
  final int initialIndex;

  const PlayerScreen({super.key, required this.playlist, required this.initialIndex});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with SingleTickerProviderStateMixin {
  late final player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: 64 * 1024 * 1024,
      vo: 'gpu',
      pitch: true,
    ),
  );

  late final controller = VideoController(
    player,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true,
      hwdec: 'auto-safe',
    ),
  );

  late int currentIndex;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  bool isControlsVisible = true;
  bool isLocked = false;
  bool isMuted = false;
  bool mirrorMode = false;
  bool nightMode = false;
  bool isLandscape = false;
  double brightness = 1.0;
  double speed = 1.0;
  BoxFit currentFit = BoxFit.contain;
  String soundProfile = "Normal";
  late AnimationController pulseController;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    player.stream.playing.listen((p) {
      if (mounted) setState(() => isPlaying = p);
    });
    player.stream.position.listen((pos) {
      if (mounted) setState(() => position = pos);
    });
    player.stream.duration.listen((d) {
      if (mounted) setState(() => duration = d);
    });

    _playIndex(currentIndex);
  }

  @override
  void dispose() {
    pulseController.dispose();
    player.dispose();
    // Reset orientation on exiting player
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _playIndex(int index) async {
    if (index < 0 || index >= widget.playlist.length) return;
    setState(() => currentIndex = index);
    await player.open(Media(widget.playlist[index].file.path));
    await player.play();
  }

  void _toggleManualOrientation() {
    if (isLandscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
    setState(() => isLandscape = !isLandscape);
  }

  String formatTime(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final m = twoDigits(d.inMinutes.remainder(60));
    final s = twoDigits(d.inSeconds.remainder(60));
    return "$m:$s";
  }

  void showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1E1F30),
      ),
    );
  }

  void _openPlayitSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12131F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Wrap(
            runSpacing: 16,
            children: [
              const Text("Play settings", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _sheetItem(
                    icon: Icons.headphones_rounded,
                    label: "Sound FX\n($soundProfile)",
                    active: soundProfile != "Normal",
                    onTap: () {
                      Navigator.pop(ctx);
                      _openSoundProfileDialog();
                    },
                  ),
                  _sheetItem(
                    icon: Icons.music_note_rounded,
                    label: "Video to\nAudio MP3",
                    active: false,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final currentItem = widget.playlist[currentIndex];
                      if (!currentItem.isVideo) {
                        showMsg("Yeh already audio file hai!");
                        return;
                      }
                      showMsg("Extracting audio in background...");
                      final outDir = currentItem.file.parent.path;
                      final outPath = "$outDir/${currentItem.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '')}_audio.mp3";
                      await Process.run('ffmpeg', [
                        '-i', currentItem.file.path,
                        '-vn',
                        '-acodec', 'libmp3lame',
                        outPath,
                        '-y'
                      ]);
                      showMsg("Saved MP3: $outPath");
                    },
                  ),
                  _sheetItem(
                    icon: Icons.nightlight_round,
                    label: "Night mode",
                    active: nightMode,
                    onTap: () {
                      setSheetState(() => nightMode = !nightMode);
                      setState(() => nightMode = nightMode);
                    },
                  ),
                  _sheetItem(
                    icon: Icons.flip_rounded,
                    label: "Mirror mode",
                    active: mirrorMode,
                    onTap: () {
                      setSheetState(() => mirrorMode = !mirrorMode);
                      setState(() => mirrorMode = mirrorMode);
                    },
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              Row(
                children: [
                  const Icon(Icons.brightness_medium_rounded, size: 20, color: Colors.white54),
                  const SizedBox(width: 10),
                  const Text("Brightness", style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Slider(
                      value: brightness,
                      min: 0.2,
                      max: 1.0,
                      activeColor: const Color(0xFF8B5CF6),
                      onChanged: (val) {
                        setSheetState(() => brightness = val);
                        setState(() => brightness = val);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetItem({required IconData icon, required String label, required bool active, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? const Color(0xFF00E676).withOpacity(0.2) : Colors.white.withOpacity(0.06),
              border: Border.all(color: active ? const Color(0xFF00E676) : Colors.transparent),
            ),
            child: Icon(icon, color: active ? const Color(0xFF00E676) : Colors.white70, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ],
      ),
    );
  }

  void _openSoundProfileDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141522),
        title: const Text("Audio FX Profile"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ["Normal", "Lofi Mode", "8D Audio", "16D Audio"].map((prof) {
            return ListTile(
              title: Text(prof),
              leading: Icon(Icons.graphic_eq_rounded, color: soundProfile == prof ? const Color(0xFF00E676) : Colors.white38),
              onTap: () {
                setState(() => soundProfile = prof);
                if (prof.contains("Lofi")) {
                  player.setRate(0.88);
                  player.setVolume(115.0);
                } else if (prof.contains("8D")) {
                  player.setRate(1.0);
                  player.setVolume(125.0);
                } else if (prof.contains("16D")) {
                  player.setRate(1.0);
                  player.setVolume(135.0);
                } else {
                  player.setRate(speed);
                  player.setVolume(100.0);
                }
                Navigator.pop(context);
                showMsg("$prof Active");
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.playlist[currentIndex];
    final isAudio = !currentItem.isVideo;

    return OrientationBuilder(
      builder: (context, orientation) {
        final inLandscape = orientation == Orientation.landscape;

        return Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => setState(() => isControlsVisible = !isControlsVisible),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video or Audio Stage
                if (isAudio)
                  Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0xFF2E1065), Color(0xFF08080C)],
                        radius: 0.9,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: pulseController,
                            builder: (context, child) {
                              final scale = isPlaying ? 1.0 + (pulseController.value * 0.08) : 1.0;
                              return Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: inLandscape ? 100 : 140,
                                  height: inLandscape ? 100 : 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF00E676)]),
                                    boxShadow: [
                                      BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.4), blurRadius: 30),
                                    ],
                                  ),
                                  child: Icon(Icons.audiotrack_rounded, size: inLandscape ? 50 : 70, color: Colors.white),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              currentItem.name,
                              style: TextStyle(fontSize: inLandscape ? 14 : 16, fontWeight: FontWeight.bold, color: Colors.white),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            soundProfile != "Normal" ? "$soundProfile Active" : "Hi-Res Audio Playback",
                            style: const TextStyle(color: Color(0xFF00E676), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Center(
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..setEntry(0, 0, mirrorMode ? -1 : 1),
                      child: Video(
                        controller: controller,
                        controls: NoVideoControls,
                        fit: currentFit,
                      ),
                    ),
                  ),

                if (nightMode)
                  IgnorePointer(child: Container(color: Colors.amber.withOpacity(0.18))),
                if (brightness < 0.98)
                  IgnorePointer(child: Container(color: Colors.black.withOpacity(1.0 - brightness))),

                // Seeking Zones
                Positioned(
                  left: 0,
                  top: 70,
                  bottom: 70,
                  width: MediaQuery.of(context).size.width * 0.35,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: () {
                      player.seek(position - const Duration(seconds: 10));
                      showMsg("-10s ⏪");
                    },
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 70,
                  bottom: 70,
                  width: MediaQuery.of(context).size.width * 0.35,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: () {
                      player.seek(position + const Duration(seconds: 10));
                      showMsg("+10s ⏩");
                    },
                  ),
                ),

                // Side Quick Actions
                if (isControlsVisible)
                  Positioned(
                    left: 14,
                    top: MediaQuery.of(context).size.height * 0.40,
                    child: Column(
                      children: [
                        _sideCircleBtn(
                          icon: isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          onTap: () {
                            setState(() => isMuted = !isMuted);
                            player.setVolume(isMuted ? 0 : 100);
                          },
                        ),
                        const SizedBox(height: 12),
                        _sideCircleBtn(
                          icon: isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                          color: isLocked ? Colors.redAccent : Colors.white,
                          onTap: () => setState(() => isLocked = !isLocked),
                        ),
                      ],
                    ),
                  ),

                // Top Bar
                if (isControlsVisible && !isLocked)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.only(
                        top: inLandscape ? 12 : 36,
                        left: 12,
                        right: 12,
                        bottom: 8,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black87, Colors.transparent],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Text(
                              currentItem.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                          ),
                          // Rotate Toggle Button
                          IconButton(
                            icon: Icon(inLandscape ? Icons.screen_lock_portrait_rounded : Icons.screen_lock_landscape_rounded, color: Colors.white70, size: 20),
                            tooltip: 'Rotate Screen',
                            onPressed: _toggleManualOrientation,
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                            onPressed: _openPlayitSettingsSheet,
                          ),
                        ],
                      ),
                    ),
                  ),

                // Bottom Bar
                if (isControlsVisible && !isLocked)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: inLandscape ? 8 : 14,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Colors.black87],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(formatTime(position), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: const Color(0xFF00E676),
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                    trackHeight: 2.5,
                                  ),
                                  child: Slider(
                                    value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
                                    max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                                    onChanged: (val) => player.seek(Duration(milliseconds: val.toInt())),
                                  ),
                                ),
                              ),
                              Text(formatTime(duration), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                iconSize: 32,
                                icon: Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: Colors.white),
                                onPressed: () => player.playOrPause(),
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                                onPressed: () {
                                  if (currentIndex > 0) _playIndex(currentIndex - 1);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                                onPressed: () {
                                  if (currentIndex + 1 < widget.playlist.length) _playIndex(currentIndex + 1);
                                },
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    speed = speed == 1.0 ? 1.5 : (speed == 1.5 ? 2.0 : 1.0);
                                    player.setRate(speed);
                                  });
                                },
                                child: Text("${speed}x", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              IconButton(
                                icon: Icon(currentFit == BoxFit.contain ? Icons.fullscreen_rounded : Icons.fullscreen_exit_rounded, color: Colors.white70),
                                tooltip: 'Fit / Fill',
                                onPressed: () {
                                  setState(() {
                                    currentFit = currentFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sideCircleBtn({required IconData icon, Color color = Colors.white, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.55),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}
