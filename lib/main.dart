import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:permission_handler/permission_handler.dart';

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
        scaffoldBackgroundColor: const Color(0xFF0C0D11),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00E676),
          surface: Color(0xFF161720),
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
  DateTime modifiedTime;
  String? thumbPath;

  MediaFile({
    required this.file,
    required this.title,
    required this.sizeBytes,
    required this.isVideo,
    required this.folderName,
    required this.modifiedTime,
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
  String sortBy = "time";

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  void _initApp() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.videos,
        Permission.audio,
        Permission.manageExternalStorage,
      ].request();
    }
    _scanStorage();
  }

  Future<String> _getAppDir(bool isVideo) async {
    final base = isVideo ? '/storage/emulated/0/Movies/MehraPlayer' : '/storage/emulated/0/Music/MehraPlayer';
    final dir = Directory(base);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _scanStorage() async {
    List<Directory> targetDirs = [];
    if (Platform.isAndroid) {
      final root = Directory('/storage/emulated/0');
      if (root.existsSync()) {
        try {
          final topLevel = root.listSync();
          for (var item in topLevel) {
            if (item is Directory) {
              final name = item.path.split('/').last;
              if (!name.startsWith('.') && name != 'Android') {
                targetDirs.add(item);
              }
            }
          }
        } catch (_) {}
      }
      targetDirs.add(Directory('/storage/emulated/0/Android/media'));
    } else {
      final home = Platform.environment['USERPROFILE'] ?? 'C:';
      targetDirs = [Directory('$home\\Videos'), Directory('$home\\Downloads')];
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
              final stat = e.statSync();

              if (p.endsWith('.mp4') || p.endsWith('.mkv') || p.endsWith('.avi') || p.endsWith('.mov') || p.endsWith('.webm') || p.endsWith('.3gp') || p.endsWith('.flv')) {
                vids.add(MediaFile(file: e, title: name, sizeBytes: stat.size, isVideo: true, folderName: folder, modifiedTime: stat.modified));
              } else if (p.endsWith('.mp3') || p.endsWith('.wav') || p.endsWith('.m4a') || p.endsWith('.flac') || p.endsWith('.ogg')) {
                auds.add(MediaFile(file: e, title: name, sizeBytes: stat.size, isVideo: false, folderName: folder, modifiedTime: stat.modified));
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
      });
      _applySorting();
      _generateRealThumbnails(vids);
    }
  }

  Future<void> _generateRealThumbnails(List<MediaFile> vids) async {
    final cacheDir = Directory("${Directory.systemTemp.path}/mehra_player_thumbs");
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

    for (var v in vids.take(30)) {
      final thumbPath = "${cacheDir.path}/${v.file.path.hashCode}.jpg";
      final thumbFile = File(thumbPath);

      if (await thumbFile.exists()) {
        if (mounted) setState(() => v.thumbPath = thumbPath);
      } else {
        try {
          final tempPlayer = Player();
          await tempPlayer.open(Media(v.file.path), play: false);
          await Future.delayed(const Duration(milliseconds: 300));
          final Uint8List? screenshot = await tempPlayer.screenshot(format: 'image/jpeg');
          await tempPlayer.dispose();

          if (screenshot != null && screenshot.isNotEmpty) {
            await thumbFile.writeAsBytes(screenshot);
            if (mounted) setState(() => v.thumbPath = thumbPath);
          }
        } catch (_) {}
      }
    }
  }

  void _applySorting() {
    setState(() {
      if (sortBy == "name") {
        videoList.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        audioList.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      } else if (sortBy == "size") {
        videoList.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        audioList.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      } else if (sortBy == "time") {
        videoList.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
        audioList.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
      }
    });
  }

  void _showSortDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161722),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Sort By", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ListTile(
              leading: const Icon(Icons.access_time_rounded),
              title: const Text("Date / Time"),
              trailing: sortBy == "time" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () { setState(() => sortBy = "time"); _applySorting(); Navigator.pop(ctx); },
            ),
            ListTile(
              leading: const Icon(Icons.sort_by_alpha_rounded),
              title: const Text("Name (A - Z)"),
              trailing: sortBy == "name" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () { setState(() => sortBy = "name"); _applySorting(); Navigator.pop(ctx); },
            ),
            ListTile(
              leading: const Icon(Icons.data_usage_rounded),
              title: const Text("Size (Large First)"),
              trailing: sortBy == "size" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () { setState(() => sortBy = "size"); _applySorting(); Navigator.pop(ctx); },
            ),
          ],
        ),
      ),
    );
  }

  void _showDownloaderDialog() {
    final urlController = TextEditingController();
    String downloadType = "mp4";
    List<String> qualities = ["Auto Best", "1080p", "720p", "480p", "ZIP / Torrent / Direct"];
    List<String> audioFx = ["Standard MP3", "8D Audio", "16D Audio", "Lofi Chill"];
    String selectedQuality = "Auto Best";
    String selectedAudioEffect = "Standard MP3";
    bool isDownloading = false;
    double downloadProgress = 0.0;
    int progressPercent = 0;

    showDialog(
      context: context,
      barrierDismissible: !isDownloading,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF171822),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: const [
              Icon(Icons.download_rounded, color: Color(0xFF00E676)),
              SizedBox(width: 10),
              Text("Universal Downloader", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: urlController,
                  enabled: !isDownloading,
                  decoration: InputDecoration(
                    hintText: "Paste YouTube, Insta, Torrent, ZIP link...",
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                    filled: true,
                    fillColor: Colors.black38,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text("Video / ZIP"),
                      selected: downloadType == "mp4",
                      selectedColor: const Color(0xFF00E676),
                      onSelected: isDownloading ? null : (_) => setDialogState(() => downloadType = "mp4"),
                    ),
                    ChoiceChip(
                      label: const Text("MP3 Audio"),
                      selected: downloadType == "mp3",
                      selectedColor: const Color(0xFF00E676),
                      onSelected: isDownloading ? null : (_) => setDialogState(() => downloadType = "mp3"),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: (downloadType == "mp4" ? qualities : audioFx).map((opt) {
                    final isSel = (downloadType == "mp4" ? selectedQuality : selectedAudioEffect) == opt;
                    return ChoiceChip(
                      label: Text(opt, style: TextStyle(color: isSel ? Colors.black : Colors.white, fontSize: 11)),
                      selected: isSel,
                      selectedColor: const Color(0xFF00E676),
                      onSelected: isDownloading ? null : (_) => setDialogState(() {
                        if (downloadType == "mp4") selectedQuality = opt; else selectedAudioEffect = opt;
                      }),
                    );
                  }).toList(),
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: downloadProgress > 0 ? downloadProgress : null, color: const Color(0xFF00E676)),
                  ),
                  const SizedBox(height: 6),
                  Text("Downloading: $progressPercent%", style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ]
              ],
            ),
          ),
          actions: [
            if (!isDownloading) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
              onPressed: isDownloading
                  ? null
                  : () async {
                      final u = urlController.text.trim();
                      if (u.isEmpty || !u.startsWith("http")) return;
                      setDialogState(() { isDownloading = true; progressPercent = 1; });
                      try {
                        final isVid = downloadType == "mp4";
                        final dir = await _getAppDir(isVid);
                        final ext = u.contains('.zip') ? 'zip' : (isVid ? 'mp4' : 'mp3');
                        final path = "$dir/Mehra_${DateTime.now().millisecondsSinceEpoch}.$ext";
                        final req = http.Request('GET', Uri.parse(u));
                        final res = await req.send();
                        final total = res.contentLength ?? 0;
                        int got = 0;
                        final sink = File(path).openWrite();
                        await res.stream.listen((chunk) {
                          sink.add(chunk);
                          got += chunk.length;
                          setDialogState(() {
                            if (total > 0) {
                              downloadProgress = (got / total).clamp(0.0, 1.0);
                              progressPercent = (downloadProgress * 100).toInt();
                            }
                          });
                        }).asFuture();
                        await sink.close();
                        Navigator.pop(ctx);
                        _scanStorage();
                      } catch (_) {
                        setDialogState(() => isDownloading = false);
                      }
                    },
              child: const Text("Download", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
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
      backgroundColor: const Color(0xFF0C0D11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0D11),
        title: const Text('Mehra Player', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
        actions: [
          IconButton(icon: const Icon(Icons.sort_rounded), onPressed: _showSortDialog),
          IconButton(icon: const Icon(Icons.download_rounded, color: Color(0xFF00E676)), onPressed: _showDownloaderDialog),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _scanStorage),
        ],
      ),
      body: _currentNavIndex == 0 ? _buildVideosTab() : _buildMusicTab(),
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
    return ListView.builder(
      itemCount: videoList.length,
      itemBuilder: (ctx, index) {
        final item = videoList[index];
        return ListTile(
          onTap: () => _launchPlayer(videoList, index),
          leading: Container(
            width: 90,
            height: 55,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1F2B),
              borderRadius: BorderRadius.circular(6),
              image: item.thumbPath != null ? DecorationImage(image: FileImage(File(item.thumbPath!)), fit: BoxFit.cover) : null,
            ),
            child: item.thumbPath == null ? const Icon(Icons.movie_creation_outlined, color: Colors.white38) : null,
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
          subtitle: Text("${item.folderName} | ${item.formattedSize}", style: const TextStyle(fontSize: 11, color: Colors.white38)),
        );
      },
    );
  }

  Widget _buildMusicTab() {
    return ListView.builder(
      itemCount: audioList.length,
      itemBuilder: (ctx, i) {
        final item = audioList[i];
        return ListTile(
          onTap: () => _launchPlayer(audioList, i),
          leading: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.audiotrack_rounded, color: Color(0xFF00E676)),
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
          subtitle: Text(item.formattedSize, style: const TextStyle(fontSize: 11, color: Colors.white38)),
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

class _PlayitVideoPlayerState extends State<PlayitVideoPlayer> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final player = Player(configuration: const PlayerConfiguration(bufferSize: 256 * 1024 * 1024, pitch: true));
  late final controller = VideoController(player);
  late TransformationController _transformController;
  late int currentIndex;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  bool controlsVisible = true;
  bool isLocked = false;
  bool isMuted = false;
  bool isFloatingPip = false;
  Offset pipOffset = const Offset(20, 100);

  double brightness = 0.5;
  double volume = 1.0;
  bool showGesture = false;
  String gestureName = "";
  double gestureVal = 0.0;
  Tracks currentTracks = const Tracks();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    currentIndex = widget.initialIndex;
    _transformController = TransformationController();

    player.stream.playing.listen((p) { if (mounted) setState(() => isPlaying = p); });
    player.stream.position.listen((pos) { if (mounted) setState(() => position = pos); });
    player.stream.duration.listen((d) { if (mounted) setState(() => duration = d); });
    player.stream.tracks.listen((tr) { if (mounted) setState(() => currentTracks = tr); });

    _openMedia(currentIndex);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (isPlaying) player.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  void _showTrackSheet(bool isAudio) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161722),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isAudio ? "Audio Language" : "Subtitles", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (!isAudio)
              ListTile(
                title: const Text("Turn OFF Subtitles"),
                onTap: () { player.setSubtitleTrack(SubtitleTrack.no()); Navigator.pop(ctx); },
              ),
            ...(isAudio ? currentTracks.audio : currentTracks.subtitle).map((t) {
              final title = (t as dynamic).title ?? (t as dynamic).language ?? "Track ${(t as dynamic).id}";
              return ListTile(
                title: Text(title),
                onTap: () {
                  if (isAudio) player.setAudioTrack(t as AudioTrack); else player.setSubtitleTrack(t as SubtitleTrack);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.playlist[currentIndex];
    final screenW = MediaQuery.of(context).size.width;

    if (isFloatingPip) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned(
              left: pipOffset.dx,
              top: pipOffset.dy,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => pipOffset += d.delta),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 200,
                    height: 115,
                    color: Colors.black,
                    child: Stack(
                      children: [
                        Video(controller: controller, controls: NoVideoControls),
                        Positioned(
                          right: 4, top: 4,
                          child: GestureDetector(
                            onTap: () => setState(() => isFloatingPip = false),
                            child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 20),
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
        onTap: () { if (!isLocked) setState(() => controlsVisible = !controlsVisible); },
        onVerticalDragUpdate: isLocked ? null : (details) {
          final isLeft = details.globalPosition.dx < (screenW / 2);
          final delta = -details.primaryDelta! / 200.0;
          setState(() {
            showGesture = true;
            if (isLeft) {
              gestureName = "Brightness";
              brightness = (brightness + delta).clamp(0.05, 1.0);
              gestureVal = brightness * 100;
            } else {
              gestureName = "Volume";
              volume = (volume + delta).clamp(0.0, 1.0);
              gestureVal = volume * 100;
              player.setVolume(gestureVal);
            }
          });
        },
        onVerticalDragEnd: (_) => Future.delayed(const Duration(milliseconds: 700), () => setState(() => showGesture = false)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (currentItem.isVideo)
              InteractiveViewer(
                transformationController: _transformController,
                minScale: 1.0,
                maxScale: 3.5,
                child: SizedBox.expand(child: Video(controller: controller, controls: NoVideoControls)),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 180,
                      height: 180,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1E1F2B)),
                      child: const Icon(Icons.music_note_rounded, color: Color(0xFF00E676), size: 70),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(currentItem.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

            if (showGesture)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                  child: Text("$gestureName: ${gestureVal.toInt()}%", style: const TextStyle(fontSize: 16, color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                ),
              ),

            if (controlsVisible) ...[
              Positioned(
                left: 12, top: 120,
                child: Column(
                  children: [
                    IconButton(
                      icon: Icon(isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                      onPressed: () { setState(() => isMuted = !isMuted); player.setVolume(isMuted ? 0 : 100); },
                    ),
                    IconButton(
                      icon: Icon(isLocked ? Icons.lock : Icons.lock_open, color: isLocked ? Colors.red : Colors.white),
                      onPressed: () => setState(() => isLocked = !isLocked),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12, top: 120,
                child: IconButton(
                  icon: const Icon(Icons.picture_in_picture_alt, color: Color(0xFF00E676)),
                  onPressed: () => setState(() => isFloatingPip = true),
                ),
              ),

              Positioned(
                top: 0, left: 0, right: 0,
                child: AppBar(
                  backgroundColor: Colors.black54,
                  elevation: 0,
                  leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                  title: Text(currentItem.title, style: const TextStyle(fontSize: 14)),
                  actions: [
                    if (currentItem.isVideo) ...[
                      IconButton(icon: const Icon(Icons.audiotrack), tooltip: "Audio Track", onPressed: () => _showTrackSheet(true)),
                      IconButton(icon: const Icon(Icons.subtitles), tooltip: "Subtitles", onPressed: () => _showTrackSheet(false)),
                    ]
                  ],
                ),
              ),

              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Slider(
                        value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
                        max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                        activeColor: const Color(0xFF00E676),
                        onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous, size: 28),
                            onPressed: () { if (currentIndex > 0) _openMedia(currentIndex - 1); },
                          ),
                          IconButton(
                            icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 40, color: const Color(0xFF00E676)),
                            onPressed: () => player.playOrPause(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next, size: 28),
                            onPressed: () { if (currentIndex + 1 < widget.playlist.length) _openMedia(currentIndex + 1); },
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
