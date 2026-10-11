import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
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
        scaffoldBackgroundColor: const Color(0xFF08080C),
        fontFamily: 'Segoe UI',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFF06B6D4),
          surface: Color(0xFF12121A),
        ),
      ),
      home: const MainPlayerScreen(),
    );
  }
}

class MainPlayerScreen extends StatefulWidget {
  const MainPlayerScreen({super.key});

  @override
  State<MainPlayerScreen> createState() => _MainPlayerScreenState();
}

class _MainPlayerScreenState extends State<MainPlayerScreen> with SingleTickerProviderStateMixin {
  late final player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: 128 * 1024 * 1024,
      vo: 'gpu',
      pitch: true,
    ),
  );

  late final controller = VideoController(
    player,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true,
      hwdec: 'auto',
    ),
  );

  late AnimationController pulseController;

  List<FileSystemEntity> videoList = [];
  List<FileSystemEntity> audioList = [];
  int currentIndex = -1;
  bool isAudioMode = false;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  // States
  bool ambientLight = true;
  bool dolbyAtmos = false;
  bool isShuffle = false;
  bool isRepeat = false;
  bool isLocked = false;
  bool showSubtitles = true;
  double speed = 1.0;
  BoxFit currentFit = BoxFit.contain;
  String fitLabel = "Fit";

  @override
  void initState() {
    super.initState();
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

    scanAllMediaFiles();
  }

  @override
  void dispose() {
    pulseController.dispose();
    player.dispose();
    super.dispose();
  }

  void showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1E1B4B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<String> getOutputDir() async {
    final home = Platform.isWindows ? (Platform.environment['USERPROFILE'] ?? 'C:') : '/storage/emulated/0/Download';
    final dir = Directory('$home/MehraPlayer');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> scanAllMediaFiles() async {
    List<Directory> targetDirs = [];
    if (Platform.isAndroid) {
      targetDirs = [
        Directory('/storage/emulated/0/DCIM'),
        Directory('/storage/emulated/0/Movies'),
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Music'),
      ];
    } else {
      final home = Platform.environment['USERPROFILE'] ?? 'C:';
      targetDirs = [
        Directory('$home\\Videos'),
        Directory('$home\\Music'),
        Directory('$home\\Downloads\\MehraPlayer'),
      ];
    }

    List<FileSystemEntity> vids = [];
    List<FileSystemEntity> auds = [];

    for (var dir in targetDirs) {
      if (dir.existsSync()) {
        try {
          final list = dir.listSync(recursive: true, followLinks: false);
          for (var f in list) {
            final p = f.path.toLowerCase();
            if (p.endsWith('.mp4') || p.endsWith('.mkv') || p.endsWith('.avi')) {
              vids.add(f);
            } else if (p.endsWith('.mp3') || p.endsWith('.wav') || p.endsWith('.m4a') || p.endsWith('.flac')) {
              auds.add(f);
            }
          }
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        videoList = vids;
        audioList = auds;
      });
    }
  }

  void playMedia(int index, bool audio) async {
    final list = audio ? audioList : videoList;
    if (index < 0 || index >= list.length) return;

    setState(() {
      currentIndex = index;
      isAudioMode = audio;
    });

    await player.open(Media(list[index].path));
    await player.play();
  }

  void nextTrack() {
    final list = isAudioMode ? audioList : videoList;
    if (list.isEmpty) return;
    int next = isShuffle ? ((currentIndex + 3) % list.length) : (currentIndex + 1 >= list.length ? 0 : currentIndex + 1);
    playMedia(next, isAudioMode);
  }

  void prevTrack() {
    final list = isAudioMode ? audioList : videoList;
    if (list.isEmpty) return;
    int prev = currentIndex - 1 < 0 ? list.length - 1 : currentIndex - 1;
    playMedia(prev, isAudioMode);
  }

  void toggleDolby() {
    setState(() => dolbyAtmos = !dolbyAtmos);
    player.setVolume(dolbyAtmos ? 130.0 : 100.0);
    showMsg(dolbyAtmos ? "Dolby Atmos 3D: Enabled (+30% Boost)" : "Dolby Atmos: Disabled");
  }

  void cycleAspectRatio() {
    setState(() {
      if (currentFit == BoxFit.contain) {
        currentFit = BoxFit.cover;
        fitLabel = "Zoom";
      } else if (currentFit == BoxFit.cover) {
        currentFit = BoxFit.fill;
        fitLabel = "Fill";
      } else {
        currentFit = BoxFit.contain;
        fitLabel = "Fit";
      }
    });
    showMsg("Aspect Ratio: $fitLabel");
  }

  String formatTime(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final m = twoDigits(d.inMinutes.remainder(60));
    final s = twoDigits(d.inSeconds.remainder(60));
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final activeList = isAudioMode ? audioList : videoList;
    final currentFile = (currentIndex >= 0 && currentIndex < activeList.length) ? activeList[currentIndex] : null;
    final currentTitle = currentFile != null ? currentFile.path.split(Platform.pathSeparator).last : "Koi file chunein";

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(62),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF111119), Color(0xFF09090D)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)]),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.4), blurRadius: 10),
                      ],
                    ),
                    child: const Text('M', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  const SizedBox(width: 12),
                  const Text('Mehra Player', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 0.5)),
                ],
              ),
              actions: [
                _buildHeaderIcon(
                  icon: isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: isLocked ? Colors.redAccent : Colors.white70,
                  tooltip: 'Screen Lock',
                  onTap: () => setState(() => isLocked = !isLocked),
                ),
                _buildHeaderIcon(
                  icon: Icons.subtitles_rounded,
                  color: Colors.white70,
                  tooltip: 'Subtitles',
                  onTap: () {
                    setState(() => showSubtitles = !showSubtitles);
                    player.setSubtitleTrack(showSubtitles ? SubtitleTrack.auto() : SubtitleTrack.no());
                    showMsg(showSubtitles ? "Subtitles: ON" : "Subtitles: OFF");
                  },
                ),
                _buildHeaderIcon(
                  icon: Icons.aspect_ratio_rounded,
                  color: Colors.white70,
                  tooltip: 'Aspect: $fitLabel',
                  onTap: cycleAspectRatio,
                ),
                _buildHeaderIcon(
                  icon: ambientLight ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
                  color: ambientLight ? const Color(0xFFFBBF24) : Colors.white70,
                  tooltip: 'Ambient Glow',
                  onTap: () => setState(() => ambientLight = !ambientLight),
                ),
                _buildHeaderIcon(
                  icon: Icons.surround_sound_rounded,
                  color: dolbyAtmos ? const Color(0xFF06B6D4) : Colors.white70,
                  tooltip: 'Dolby Atmos',
                  onTap: toggleDolby,
                ),
                _buildHeaderIcon(
                  icon: Icons.folder_open_rounded,
                  color: const Color(0xFFA78BFA),
                  tooltip: 'Open Media File',
                  onTap: () async {
                    final res = await FilePicker.platform.pickFiles(type: FileType.media);
                    if (res != null && res.files.single.path != null) {
                      final p = res.files.single.path!;
                      final isAud = p.toLowerCase().endsWith('.mp3');
                      setState(() {
                        if (isAud) {
                          audioList.insert(0, File(p));
                          playMedia(0, true);
                        } else {
                          videoList.insert(0, File(p));
                          playMedia(0, false);
                        }
                      });
                    }
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            // Video / Music Screen Viewport
            Expanded(
              flex: 5,
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: ambientLight
                      ? [
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withOpacity(0.28),
                            blurRadius: 40,
                            spreadRadius: 6,
                          )
                        ]
                      : [],
                  border: Border.all(color: Colors.white10),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildStage(currentFile, currentTitle),
              ),
            ),

            // Modern Floating Player Controls
            if (!isLocked)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF12121A).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  children: [
                    // Timeline
                    Row(
                      children: [
                        Text(formatTime(position), style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF8B5CF6),
                              inactiveTrackColor: Colors.white12,
                              thumbColor: Colors.white,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayColor: const Color(0xFF8B5CF6).withOpacity(0.2),
                              trackHeight: 3.5,
                            ),
                            child: Slider(
                              value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
                              max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                              onChanged: (val) => player.seek(Duration(milliseconds: val.toInt())),
                            ),
                          ),
                        ),
                        Text(formatTime(duration), style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
                      ],
                    ),

                    // Controls Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(Icons.shuffle_rounded, color: isShuffle ? const Color(0xFF06B6D4) : Colors.white38),
                          onPressed: () => setState(() => isShuffle = !isShuffle),
                        ),
                        const SizedBox(width: 14),
                        IconButton(
                          iconSize: 28,
                          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                          onPressed: prevTrack,
                        ),
                        const SizedBox(width: 14),
                        GestureDetector(
                          onTap: () => player.playOrPause(),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                              ),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.4), blurRadius: 16),
                              ],
                            ),
                            child: Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        IconButton(
                          iconSize: 28,
                          icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                          onPressed: nextTrack,
                        ),
                        const SizedBox(width: 14),
                        IconButton(
                          icon: Icon(Icons.repeat_rounded, color: isRepeat ? const Color(0xFF06B6D4) : Colors.white38),
                          onPressed: () => setState(() => isRepeat = !isRepeat),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButton<double>(
                            value: speed,
                            underline: const SizedBox(),
                            dropdownColor: const Color(0xFF1E1B2E),
                            items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                                .map((s) => DropdownMenuItem(value: s, child: Text('${s}x', style: const TextStyle(fontSize: 12))))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => speed = val);
                                player.setRate(val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Tab bar for media lists
            Container(
              margin: const EdgeInsets.only(top: 4),
              color: const Color(0xFF0F0F16),
              child: const TabBar(
                indicatorColor: Color(0xFF8B5CF6),
                labelColor: Color(0xFFA78BFA),
                unselectedLabelColor: Colors.white54,
                tabs: [
                  Tab(icon: Icon(Icons.movie_filter_rounded, size: 20), text: "Videos"),
                  Tab(icon: Icon(Icons.music_note_rounded, size: 20), text: "Audio Songs"),
                ],
              ),
            ),

            // Media list with Cards
            Expanded(
              flex: 4,
              child: TabBarView(
                children: [
                  _buildMediaList(videoList, false),
                  _buildMediaList(audioList, true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStage(FileSystemEntity? currentFile, String currentTitle) {
    if (currentFile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_outline_rounded, size: 54, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 10),
            const Text("Koi bhi Video ya Song select karein", style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      );
    }

    if (isAudioMode) {
      return Container(
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
                  final scale = isPlaying ? 1.0 + (pulseController.value * 0.06) : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)]),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.5), blurRadius: 28),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.audiotrack_rounded, size: 64, color: Colors.white),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  currentTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.4)),
                ),
                child: Text(
                  dolbyAtmos ? "Dolby Atmos 3D Active" : "Hi-Res Audio Player",
                  style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Video(
      controller: controller,
      controls: NoVideoControls,
      fit: currentFit,
    );
  }

  Widget _buildMediaList(List<FileSystemEntity> list, bool audio) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          audio ? "Koi audio file nahi mili" : "Koi video file nahi mili",
          style: const TextStyle(color: Colors.white30),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final name = list[i].path.split(Platform.pathSeparator).last;
        final isSel = (isAudioMode == audio) && currentIndex == i;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFF8B5CF6).withOpacity(0.18) : const Color(0xFF14141E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSel ? const Color(0xFF8B5CF6).withOpacity(0.6) : Colors.white.withOpacity(0.04),
            ),
          ),
          child: ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: (audio ? const Color(0xFF06B6D4) : const Color(0xFF8B5CF6)).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                audio ? Icons.music_note_rounded : Icons.play_arrow_rounded,
                color: audio ? const Color(0xFF06B6D4) : const Color(0xFF8B5CF6),
                size: 20,
              ),
            ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                color: isSel ? Colors.white : Colors.white70,
              ),
            ),
            trailing: isSel
                ? const Icon(Icons.graphic_eq_rounded, color: Color(0xFF8B5CF6), size: 18)
                : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 12),
            onTap: () => playMedia(i, audio),
          ),
        );
      },
    );
  }

  Widget _buildHeaderIcon({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return IconButton(
      icon: Icon(icon, color: color, size: 21),
      tooltip: tooltip,
      splashRadius: 20,
      onPressed: onTap,
    );
  }
}
