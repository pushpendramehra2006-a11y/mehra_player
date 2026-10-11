import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MehraPlayerApp());
}

class MehraPlayerApp extends StatelessWidget {
  const MehraPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mehra Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00E676),
          surface: Color(0xFF17181F),
        ),
      ),
      home: const MainTabScreen(),
    );
  }
}

class MediaFile {
  File file;
  String title;
  int sizeBytes;
  final bool isVideo;
  String folderName;
  String? thumbPath;

  MediaFile({
    required this.file,
    required this.title,
    required this.sizeBytes,
    required this.isVideo,
    required this.folderName,
    this.thumbPath,
  });

  String get formattedSize {
    if (sizeBytes < 1024 * 1024) return "${(sizeBytes / 1024).toStringAsFixed(1)} KB";
    return "${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB";
  }
}

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentNavIndex = 0;
  List<MediaFile> videoList = [];
  List<MediaFile> audioList = [];
  List<MediaFile> historyList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _scanStorage();
  }

  Future<void> _scanStorage() async {
    setState(() => isLoading = true);
    List<Directory> targetDirs = [];

    if (Platform.isAndroid) {
      targetDirs = [
        Directory('/storage/emulated/0/DCIM/Camera'),
        Directory('/storage/emulated/0/DCIM'),
        Directory('/storage/emulated/0/Movies'),
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Music'),
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

    List<MediaFile> vids = [];
    List<MediaFile> auds = [];

    for (var dir in targetDirs) {
      if (dir.existsSync()) {
        try {
          final entries = dir.listSync(recursive: true, followLinks: false);
          for (var e in entries) {
            if (e is File) {
              final p = e.path.toLowerCase();
              final name = e.path.split(Platform.pathSeparator).last;
              if (name.startsWith('.')) continue;

              final folder = e.parent.path.split(Platform.pathSeparator).last;

              if (p.endsWith('.mp4') || p.endsWith('.mkv') || p.endsWith('.avi') || p.endsWith('.mov') || p.endsWith('.webm') || p.endsWith('.flv') || p.endsWith('.ts')) {
                vids.add(MediaFile(file: e, title: name, sizeBytes: e.lengthSync(), isVideo: true, folderName: folder));
              } else if (p.endsWith('.mp3') || p.endsWith('.wav') || p.endsWith('.m4a') || p.endsWith('.flac') || p.endsWith('.ogg') || p.endsWith('.aac')) {
                auds.add(MediaFile(file: e, title: name, sizeBytes: e.lengthSync(), isVideo: false, folderName: folder));
              }
            }
          }
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        videoList = vids;
        audioList = auds;
        if (vids.isNotEmpty) historyList = vids.take(5).toList();
        isLoading = false;
      });
    }
  }

  void _launchPlayer(List<MediaFile> list, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayitVideoPlayer(playlist: list, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F12),
        elevation: 0,
        title: const Text('Mehra Player', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: Colors.white70),
            onPressed: () async {
              final res = await FilePicker.platform.pickFiles(type: FileType.media);
              if (res != null && res.files.single.path != null) {
                final f = File(res.files.single.path!);
                _launchPlayer([MediaFile(file: f, title: f.path.split(Platform.pathSeparator).last, sizeBytes: f.lengthSync(), isVideo: !f.path.endsWith('.mp3'), folderName: 'Browse')], 0);
              }
            },
          ),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white70), onPressed: _scanStorage),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
          : (_currentNavIndex == 0 ? _buildVideosTab() : _buildMusicTab()),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: (i) => setState(() => _currentNavIndex = i),
        backgroundColor: const Color(0xFF14151B),
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: Colors.white38,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.smart_display_rounded), label: "VIDEO"),
          BottomNavigationBarItem(icon: Icon(Icons.audiotrack_rounded), label: "AUDIO"),
        ],
      ),
    );
  }

  Widget _buildVideosTab() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        if (historyList.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text("History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          ),
          SizedBox(
            height: 96,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: historyList.length,
              itemBuilder: (ctx, i) {
                final item = historyList[i];
                return GestureDetector(
                  onTap: () => _launchPlayer(historyList, i),
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: const Color(0xFF1B1C26), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white.withOpacity(0.3), size: 36)),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 12),
        ...videoList.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;

          return ListTile(
            onTap: () => _launchPlayer(videoList, index),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: const Color(0xFF1E1F2B), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.movie_creation_outlined, color: Color(0xFF00E676)),
            ),
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text("${item.folderName} | ${item.formattedSize}", style: const TextStyle(fontSize: 11, color: Colors.white38)),
          );
        }),
      ],
    );
  }

  Widget _buildMusicTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: audioList.length,
      itemBuilder: (ctx, i) {
        final item = audioList[i];
        return ListTile(
          onTap: () => _launchPlayer(audioList, i),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.music_note_rounded, color: Color(0xFF00E676)),
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text("${item.folderName} | ${item.formattedSize}", style: const TextStyle(fontSize: 11, color: Colors.white38)),
        );
      },
    );
  }
}

class PlayitVideoPlayer extends StatefulWidget {
  final List<MediaFile> playlist;
  final int initialIndex;

  const PlayitVideoPlayer({super.key, required this.playlist, required this.initialIndex});

  @override
  State<PlayitVideoPlayer> createState() => _PlayitVideoPlayerState();
}

class _PlayitVideoPlayerState extends State<PlayitVideoPlayer> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final player = Player(
    configuration: PlayerConfiguration(
      bufferSize: 256 * 1024 * 1024,
      vo: 'gpu-next',
      pitch: true,
    ),
  );

  late final controller = VideoController(
    player,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true,
      hwdec: 'mediacodec',
    ),
  );

  late AnimationController _discAnimCtrl;
  late TransformationController _transformController;
  late int currentIndex;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  bool controlsVisible = true;
  bool isLocked = false;
  bool isLandscape = false;
  bool backgroundAudioEnabled = true;

  // Swipe Gestures
  double brightness = 0.5;
  double volume = 1.0;
  bool showGestureIndicator = false;
  String gestureType = "";
  double gestureValue = 0.0;

  // In-App Floating Video Pop-up Window (PiP) State
  bool isFloatingPip = false;
  Offset pipOffset = const Offset(20, 100);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    currentIndex = widget.initialIndex;

    _discAnimCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 10));
    _transformController = TransformationController();

    try {
      (player.platform as dynamic)?.setProperty('framedrop', 'vo');
      (player.platform as dynamic)?.setProperty('video-sync', 'audio');
      (player.platform as dynamic)?.setProperty('vd-lavc-fast', 'yes');
      (player.platform as dynamic)?.setProperty('scale', 'bilinear');
      (player.platform as dynamic)?.setProperty('dscale', 'bilinear');
    } catch (_) {}

    player.stream.playing.listen((p) {
      if (mounted) {
        setState(() => isPlaying = p);
        if (p) _discAnimCtrl.repeat(); else _discAnimCtrl.stop();
      }
    });

    player.stream.position.listen((pos) {
      if (mounted) setState(() => position = pos);
    });

    player.stream.duration.listen((d) {
      if (mounted) setState(() => duration = d);
    });

    _openMedia(currentIndex);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep playing in background when minimized unless explicitly stopped
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (backgroundAudioEnabled && isPlaying) {
        // Continue playback continuously in background
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _discAnimCtrl.dispose();
    _transformController.dispose();
    player.dispose();
    super.dispose();
  }

  void _openMedia(int index) async {
    if (index < 0 || index >= widget.playlist.length) return;
    setState(() => currentIndex = index);
    await player.open(Media(widget.playlist[index].file.path));
    await player.play();
  }

  void _toggleOrientation() {
    setState(() {
      isLandscape = !isLandscape;
      if (isLandscape) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      } else {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    });
  }

  void _triggerPipPopUp() {
    setState(() {
      isFloatingPip = !isFloatingPip;
      controlsVisible = !isFloatingPip;
    });
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return "$m:$s";
  }

  Widget _buildAudioMusicPlayerView(MediaFile item) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _discAnimCtrl,
            builder: (context, child) => Transform.rotate(angle: _discAnimCtrl.value * 2 * math.pi, child: child),
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(colors: [Colors.black, Color(0xFF181A24), Colors.black], stops: [0.3, 0.7, 1.0]),
                boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.35), blurRadius: 45, spreadRadius: 5)],
              ),
              child: Center(
                child: Container(
                  width: 95,
                  height: 95,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00E676), width: 3),
                    gradient: const LinearGradient(colors: [Color(0xFF00E676), Colors.tealAccent]),
                  ),
                  child: const Center(child: Icon(Icons.music_note_rounded, size: 48, color: Colors.black)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 38),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(item.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
          ),
          const SizedBox(height: 6),
          Text(item.formattedSize, style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.playlist[currentIndex];
    final remainingDuration = duration - position;
    final screenWidth = MediaQuery.of(context).size.width;

    // Floating Pop-up Window Render Mode
    if (isFloatingPip) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned(
              left: pipOffset.dx,
              top: pipOffset.dy,
              child: GestureDetector(
                onPanUpdate: (d) {
                  setState(() {
                    pipOffset = Offset(
                      (pipOffset.dx + d.delta.dx).clamp(10, MediaQuery.of(context).size.width - 230),
                      (pipOffset.dy + d.delta.dy).clamp(30, MediaQuery.of(context).size.height - 150),
                    );
                  });
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 220,
                    height: 125,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: const Color(0xFF00E676), width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 16)],
                    ),
                    child: Stack(
                      children: [
                        Video(controller: controller, controls: NoVideoControls, fit: BoxFit.cover),
                        Positioned(
                          right: 4, top: 4,
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: _triggerPipPopUp,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 6, bottom: 6,
                          child: GestureDetector(
                            onTap: () => player.playOrPause(),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: const Color(0xFF00E676), size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (!isLocked) setState(() => controlsVisible = !controlsVisible);
        },
        onVerticalDragUpdate: isLocked
            ? null
            : (details) {
                final isLeftHalf = details.globalPosition.dx < (screenWidth / 2);
                final delta = -details.primaryDelta! / 200.0;
                setState(() {
                  showGestureIndicator = true;
                  if (isLeftHalf) {
                    gestureType = "brightness";
                    brightness = (brightness + delta).clamp(0.05, 1.0);
                    gestureValue = (brightness * 100);
                  } else {
                    gestureType = "volume";
                    volume = (volume + delta).clamp(0.0, 1.0);
                    gestureValue = (volume * 100);
                    player.setVolume(gestureValue);
                  }
                });
              },
        onVerticalDragEnd: (_) {
          Future.delayed(const Duration(milliseconds: 900), () {
            if (mounted) setState(() => showGestureIndicator = false);
          });
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (currentItem.isVideo)
              InteractiveViewer(
                transformationController: _transformController,
                minScale: 1.0,
                maxScale: 3.5,
                panEnabled: true,
                scaleEnabled: !isLocked,
                child: SizedBox.expand(
                  child: Video(controller: controller, controls: NoVideoControls, fit: BoxFit.contain),
                ),
              )
            else
              _buildAudioMusicPlayerView(currentItem),

            IgnorePointer(
              child: Container(color: Colors.black.withOpacity((1.0 - brightness) * 0.75)),
            ),

            if (showGestureIndicator && !isLocked)
              Center(
                child: Container(
                  width: 130,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF00E676), width: 1.2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        gestureType == "brightness" ? Icons.brightness_6_rounded : Icons.volume_up_rounded,
                        color: const Color(0xFF00E676),
                        size: 34,
                      ),
                      const SizedBox(height: 10),
                      Text("${gestureValue.toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: gestureValue / 100.0,
                          minHeight: 5,
                          color: const Color(0xFF00E676),
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Top Bar
            if (controlsVisible && !isLocked)
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.only(top: 36, left: 10, right: 10, bottom: 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.black87, Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(currentItem.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      // Floating Pop-up Window (PiP) Icon
                      if (currentItem.isVideo)
                        IconButton(
                          icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Color(0xFF00E676)),
                          tooltip: 'Floating Pop-up Player',
                          onPressed: _triggerPipPopUp,
                        ),
                      IconButton(
                        icon: Icon(isLandscape ? Icons.screen_lock_landscape_rounded : Icons.screen_rotation_rounded, color: Colors.white),
                        tooltip: 'Rotate Screen',
                        onPressed: _toggleOrientation,
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom Bar
            if (controlsVisible && !isLocked)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.transparent, Colors.black87], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(_formatDuration(position), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFF00E676),
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                                trackHeight: 2.2,
                              ),
                              child: Slider(
                                value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
                                max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                                onChanged: (val) => player.seek(Duration(milliseconds: val.toInt())),
                              ),
                            ),
                          ),
                          Text("-${_formatDuration(remainingDuration)}", style: const TextStyle(fontSize: 11, color: Colors.white70)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            iconSize: 34,
                            icon: Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: Colors.white),
                            onPressed: () => player.playOrPause(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
                            onPressed: () {
                              if (currentIndex > 0) _openMedia(currentIndex - 1);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
                            onPressed: () {
                              if (currentIndex + 1 < widget.playlist.length) _openMedia(currentIndex + 1);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Color(0xFF00E676), size: 24),
                            onPressed: _triggerPipPopUp,
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
  }
}
