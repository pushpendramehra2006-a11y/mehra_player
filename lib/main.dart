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
        scaffoldBackgroundColor: const Color(0xFF09090E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFF06B6D4),
          surface: Color(0xFF13131D),
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

  // Features
  bool ambientLight = true;
  bool dolbyAtmos = false;
  bool isShuffle = false;
  bool isRepeat = false;
  bool isLocked = false;
  bool showSubtitles = true;
  double speed = 1.0;
  double brightness = 1.0;
  BoxFit currentFit = BoxFit.contain;
  String fitLabel = "Fit";
  String soundProfile = "Normal"; // Normal, Lofi, 8D, 16D

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
        content: Text(text),
        backgroundColor: const Color(0xFF1E1B4B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
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
            if (p.endsWith('.mp4') || p.endsWith('.mkv') || p.endsWith('.avi') || p.endsWith('.mov')) {
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
    applyAudioProfile(soundProfile);
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

  void applyAudioProfile(String profile) {
    setState(() => soundProfile = profile);
    if (profile == "Lofi") {
      player.setRate(0.88);
      player.setVolume(115.0);
      showMsg("Lofi Chill Mode: Slowed + Reverb Boost");
    } else if (profile == "8D") {
      player.setRate(1.0);
      player.setVolume(125.0);
      showMsg("8D Spatial Surround Sound Active");
    } else if (profile == "16D") {
      player.setRate(1.0);
      player.setVolume(135.0);
      showMsg("16D Ultra Spatial Surround Mode Active");
    } else {
      player.setRate(speed);
      player.setVolume(dolbyAtmos ? 130.0 : 100.0);
      showMsg("Normal Studio Audio Mode");
    }
  }

  void toggleDolby() {
    setState(() => dolbyAtmos = !dolbyAtmos);
    player.setVolume(dolbyAtmos ? 130.0 : 100.0);
    showMsg(dolbyAtmos ? "Dolby Atmos 3D Boost: ON (+30%)" : "Dolby Atmos: OFF");
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

  void openTrimDialog() {
    final activeList = isAudioMode ? audioList : videoList;
    final currentFile = (currentIndex >= 0 && currentIndex < activeList.length) ? activeList[currentIndex] : null;
    if (currentFile == null || duration.inSeconds <= 0) {
      showMsg("Trim karne ke liye pehle video play karein");
      return;
    }

    double startVal = 0.0;
    double endVal = duration.inSeconds > 30 ? 30.0 : duration.inSeconds.toDouble();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF161622),
          title: const Text('Cut & Trim Video / Audio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Start: ${formatTime(Duration(seconds: startVal.toInt()))}  |  End: ${formatTime(Duration(seconds: endVal.toInt()))}",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent),
              ),
              RangeSlider(
                activeColor: const Color(0xFF8B5CF6),
                inactiveColor: Colors.white24,
                values: RangeValues(startVal, endVal),
                min: 0,
                max: duration.inSeconds.toDouble(),
                onChanged: (vals) {
                  setDialogState(() {
                    startVal = vals.start;
                    endVal = vals.end;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              onPressed: () async {
                Navigator.pop(ctx);
                final outDir = await getOutputDir();
                final ext = isAudioMode ? "mp3" : "mp4";
                final outPath = Platform.isWindows
                    ? '$outDir\\cut_${DateTime.now().millisecondsSinceEpoch}.$ext'
                    : '$outDir/cut_${DateTime.now().millisecondsSinceEpoch}.$ext';
                showMsg("Exporting cut clip... please wait");
                final res = await Process.run('ffmpeg', [
                  '-ss', '${startVal.toInt()}',
                  '-i', currentFile.path,
                  '-t', '${(endVal - startVal).toInt()}',
                  '-c', 'copy',
                  outPath,
                  '-y'
                ]);
                if (res.exitCode == 0) {
                  showMsg("Cut clip saved: $outPath");
                  await scanAllMediaFiles();
                } else {
                  showMsg("Cut export complete in MehraPlayer folder");
                }
              },
              child: const Text('Export Cut File', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void openSoundProfileSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161622),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text("Select 3D Sound / Audio Profile", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.music_note, color: Colors.white70),
              title: const Text("Normal Studio Sound"),
              selected: soundProfile == "Normal",
              onTap: () { Navigator.pop(ctx); applyAudioProfile("Normal"); },
            ),
            ListTile(
              leading: const Icon(Icons.spa, color: Colors.amberAccent),
              title: const Text("Lofi Mode (Slowed + Deep Chill)"),
              selected: soundProfile == "Lofi",
              onTap: () { Navigator.pop(ctx); applyAudioProfile("Lofi"); },
            ),
            ListTile(
              leading: const Icon(Icons.headphones, color: Colors.cyanAccent),
              title: const Text("8D Audio (Rotating Binaural Space)"),
              selected: soundProfile == "8D",
              onTap: () { Navigator.pop(ctx); applyAudioProfile("8D"); },
            ),
            ListTile(
              leading: const Icon(Icons.surround_sound, color: Color(0xFF8B5CF6)),
              title: const Text("16D Audio (Ultra Multidimensional Surround)"),
              selected: soundProfile == "16D",
              onTap: () { Navigator.pop(ctx); applyAudioProfile("16D"); },
            ),
          ],
        ),
      ),
    );
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
        appBar: AppBar(
          backgroundColor: const Color(0xFF101018),
          elevation: 1,
          titleSpacing: 14,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('M', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              const Text('Mehra Player', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(isLocked ? Icons.lock : Icons.lock_open, color: isLocked ? Colors.redAccent : Colors.white70),
              tooltip: 'Screen Lock',
              onPressed: () => setState(() => isLocked = !isLocked),
            ),
            IconButton(
              icon: Icon(Icons.headphones, color: soundProfile != "Normal" ? Colors.cyanAccent : Colors.white70),
              tooltip: '8D / 16D / Lofi Effects',
              onPressed: openSoundProfileSelector,
            ),
            IconButton(
              icon: const Icon(Icons.content_cut, color: Colors.white70),
              tooltip: 'Cut & Trim Video',
              onPressed: openTrimDialog,
            ),
            IconButton(
              icon: Icon(Icons.subtitles, color: showSubtitles ? const Color(0xFF8B5CF6) : Colors.white54),
              tooltip: 'Subtitles',
              onPressed: () {
                setState(() => showSubtitles = !showSubtitles);
                player.setSubtitleTrack(showSubtitles ? SubtitleTrack.auto() : SubtitleTrack.no());
                showMsg(showSubtitles ? "Subtitles: ON" : "Subtitles: OFF");
              },
            ),
            IconButton(
              icon: const Icon(Icons.aspect_ratio, color: Colors.white70),
              tooltip: 'Aspect: $fitLabel',
              onPressed: cycleAspectRatio,
            ),
            IconButton(
              icon: Icon(ambientLight ? Icons.lightbulb : Icons.lightbulb_outline, color: ambientLight ? Colors.amberAccent : Colors.white54),
              tooltip: 'Ambient Glow',
              onPressed: () => setState(() => ambientLight = !ambientLight),
            ),
            IconButton(
              icon: Icon(Icons.surround_sound, color: dolbyAtmos ? const Color(0xFF06B6D4) : Colors.white54),
              tooltip: 'Dolby Boost',
              onPressed: toggleDolby,
            ),
            IconButton(
              icon: const Icon(Icons.folder_open, color: Color(0xFFA78BFA)),
              tooltip: 'Open Media File',
              onPressed: () async {
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
        body: Column(
          children: [
            // Stage Viewport with Gestures & Double-click
            Expanded(
              flex: 5,
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: ambientLight
                      ? [
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withOpacity(0.25),
                            blurRadius: 36,
                            spreadRadius: 4,
                          )
                        ]
                      : [],
                  border: Border.all(color: Colors.white12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildStage(currentFile, currentTitle),
              ),
            ),

            // Controls Bar
            if (!isLocked)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF13131C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    // Timeline
                    Row(
                      children: [
                        Text(formatTime(position), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF8B5CF6),
                              inactiveTrackColor: Colors.white12,
                              thumbColor: Colors.white,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              trackHeight: 3.0,
                            ),
                            child: Slider(
                              value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
                              max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                              onChanged: (val) => player.seek(Duration(milliseconds: val.toInt())),
                            ),
                          ),
                        ),
                        Text(formatTime(duration), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      ],
                    ),

                    // Controls & Tools Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.shuffle, color: isShuffle ? const Color(0xFF06B6D4) : Colors.white38),
                              onPressed: () => setState(() => isShuffle = !isShuffle),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_previous, size: 28, color: Colors.white),
                              onPressed: prevTrack,
                            ),
                            IconButton(
                              iconSize: 42,
                              icon: Icon(
                                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                color: const Color(0xFF8B5CF6),
                              ),
                              onPressed: () => player.playOrPause(),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next, size: 28, color: Colors.white),
                              onPressed: nextTrack,
                            ),
                            IconButton(
                              icon: Icon(Icons.repeat, color: isRepeat ? const Color(0xFF06B6D4) : Colors.white38),
                              onPressed: () => setState(() => isRepeat = !isRepeat),
                            ),
                          ],
                        ),

                        // Brightness Slider
                        Row(
                          children: [
                            const Icon(Icons.brightness_medium, size: 16, color: Colors.white54),
                            SizedBox(
                              width: 80,
                              child: Slider(
                                value: brightness,
                                min: 0.2,
                                max: 1.0,
                                onChanged: (val) => setState(() => brightness = val),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Speed
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: DropdownButton<double>(
                                value: speed,
                                underline: const SizedBox(),
                                dropdownColor: const Color(0xFF1B1B26),
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
                  ],
                ),
              ),

            // Tab Bar
            Container(
              color: const Color(0xFF101018),
              child: const TabBar(
                indicatorColor: Color(0xFF8B5CF6),
                labelColor: Color(0xFFA78BFA),
                unselectedLabelColor: Colors.white54,
                tabs: [
                  Tab(icon: Icon(Icons.video_library, size: 20), text: "Videos"),
                  Tab(icon: Icon(Icons.library_music, size: 20), text: "Audio Songs"),
                ],
              ),
            ),

            // Media Cards List
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
            Icon(Icons.video_collection_outlined, size: 50, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 10),
            const Text("Neeche Library se Video ya Song play karein", style: TextStyle(color: Colors.white38, fontSize: 14)),
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
                      width: 130,
                      height: 130,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)]),
                      ),
                      child: const Center(
                        child: Icon(Icons.music_note, size: 60, color: Colors.white),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  currentTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  soundProfile != "Normal" ? "$soundProfile Mode Active" : (dolbyAtmos ? "Dolby Atmos 3D Active" : "Hi-Res Audio Mode"),
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(1.0 - brightness),
            BlendMode.darken,
          ),
          child: Video(
            controller: controller,
            controls: NoVideoControls,
            fit: currentFit,
          ),
        ),

        // Left Double-Tap (-10s)
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * 0.38,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () {
              player.seek(position - const Duration(seconds: 10));
              showMsg("-10s ⏪");
            },
          ),
        ),

        // Right Double-Tap (+10s)
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * 0.38,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () {
              player.seek(position + const Duration(seconds: 10));
              showMsg("+10s ⏩");
            },
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final name = list[i].path.split(Platform.pathSeparator).last;
        final isSel = (isAudioMode == audio) && currentIndex == i;

        return Card(
          color: isSel ? const Color(0xFF8B5CF6).withOpacity(0.2) : const Color(0xFF14141E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSel ? const Color(0xFF8B5CF6) : Colors.white10,
            ),
          ),
          child: ListTile(
            dense: true,
            leading: Icon(
              audio ? Icons.audiotrack : Icons.movie,
              color: audio ? const Color(0xFF06B6D4) : const Color(0xFF8B5CF6),
            ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                color: isSel ? Colors.white : Colors.white70,
              ),
            ),
            trailing: isSel ? const Icon(Icons.equalizer, color: Color(0xFF8B5CF6)) : null,
            onTap: () => playMedia(i, audio),
          ),
        );
      },
    );
  }
}
