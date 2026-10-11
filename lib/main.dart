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
  List<MediaFile> historyList = [];
  bool isLoading = false;
  String sortBy = "time"; // "name", "size", "time"

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
    if (Platform.isAndroid) {
      final base = isVideo ? '/storage/emulated/0/Movies/MehraPlayer' : '/storage/emulated/0/Music/MehraPlayer';
      final dir = Directory(base);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir.path;
    } else {
      final home = Platform.environment['USERPROFILE'] ?? 'C:';
      final dir = Directory('$home\\Downloads\\MehraPlayer');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir.path;
    }
  }

  // Deep Scan to find all videos present across internal storage
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
              // Skip private system and cache directories
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
              final stat = e.statSync();
              final size = stat.size;
              final modified = stat.modified;

              if (p.endsWith('.mp4') || p.endsWith('.mkv') || p.endsWith('.avi') || p.endsWith('.mov') || p.endsWith('.webm') || p.endsWith('.3gp') || p.endsWith('.flv') || p.endsWith('.ts')) {
                vids.add(MediaFile(file: e, title: name, sizeBytes: size, isVideo: true, folderName: folder, modifiedTime: modified));
              } else if (p.endsWith('.mp3') || p.endsWith('.wav') || p.endsWith('.m4a') || p.endsWith('.flac') || p.endsWith('.ogg') || p.endsWith('.aac')) {
                auds.add(MediaFile(file: e, title: name, sizeBytes: size, isVideo: false, folderName: folder, modifiedTime: modified));
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
        if (vids.isNotEmpty) historyList = vids.take(6).toList();
      });
      _applySorting();
      _generateThumbnails(vids);
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Sort By", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 14),
            ListTile(
              leading: Icon(Icons.access_time_rounded, color: sortBy == "time" ? const Color(0xFF00E676) : Colors.white54),
              title: const Text("Date / Time (Newest First)"),
              trailing: sortBy == "time" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () {
                setState(() => sortBy = "time");
                _applySorting();
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.sort_by_alpha_rounded, color: sortBy == "name" ? const Color(0xFF00E676) : Colors.white54),
              title: const Text("File Name (A - Z)"),
              trailing: sortBy == "name" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () {
                setState(() => sortBy = "name");
                _applySorting();
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.data_usage_rounded, color: sortBy == "size" ? const Color(0xFF00E676) : Colors.white54),
              title: const Text("File Size (Large to Small)"),
              trailing: sortBy == "size" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () {
                setState(() => sortBy = "size");
                _applySorting();
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Reliable Native Thumbnail Generator via MPV/MediaKit Player Engine
  Future<void> _generateThumbnails(List<MediaFile> vids) async {
    final cacheDir = Directory("${Directory.systemTemp.path}/mehra_player_thumbs");
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

    for (var v in vids.take(40)) {
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

  void _showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: const Color(0xFF1E1F30)));
  }

  void _showDownloaderDialog() {
    final urlController = TextEditingController();
    String downloadType = "mp4";
    bool isDownloading = false;
    double downloadProgress = 0.0;
    int progressPercent = 0;
    String progressSubtitle = "";

    showDialog(
      context: context,
      barrierDismissible: !isDownloading,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF171822),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: const [
              Icon(Icons.download_rounded, color: Color(0xFF00E676), size: 26),
              SizedBox(width: 10),
              Text("Universal Downloader", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.white)),
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
                    hintText: "Paste YouTube, Insta or media link...",
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                    filled: true,
                    fillColor: Colors.black38,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text("MP4 Video"),
                      selected: downloadType == "mp4",
                      selectedColor: const Color(0xFF00E676),
                      onSelected: isDownloading ? null : (_) => setDialogState(() => downloadType = "mp4"),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text("MP3 Audio"),
                      selected: downloadType == "mp3",
                      selectedColor: const Color(0xFF00E676),
                      onSelected: isDownloading ? null : (_) => setDialogState(() => downloadType = "mp3"),
                    ),
                  ],
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("$progressPercent%", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF00E676))),
                      Text(progressSubtitle, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: downloadProgress > 0.0 ? downloadProgress : null,
                      minHeight: 7,
                      color: const Color(0xFF00E676),
                      backgroundColor: Colors.white12,
                    ),
                  ),
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
                      setDialogState(() {
                        isDownloading = true;
                        progressPercent = 1;
                        progressSubtitle = "Connecting...";
                      });
                      try {
                        final dir = await _getAppDir(downloadType == "mp4");
                        final path = "$dir/Mehra_${DateTime.now().millisecondsSinceEpoch}.$downloadType";
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
                              progressSubtitle = "${(got / (1024 * 1024)).toStringAsFixed(1)} MB / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB";
                            }
                          });
                        }).asFuture();
                        await sink.close();
                        Navigator.pop(ctx);
                        _showMsg("Downloaded successfully!");
                        await _scanStorage();
                      } catch (e) {
                        setDialogState(() => isDownloading = false);
                        _showMsg("Download Error: $e");
                      }
                    },
              child: const Text("Download Now", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _openTrimDialog(MediaFile item) {
    double start = 0.0;
    double end = 30.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setTrimState) => AlertDialog(
          backgroundColor: const Color(0xFF171822),
          title: Text("Cut & Trim ${item.isVideo ? 'Video' : 'Audio'}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Start: ${start.toInt()}s | End: ${end.toInt()}s", style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
              RangeSlider(
                values: RangeValues(start, end),
                min: 0,
                max: 180,
                activeColor: const Color(0xFF00E676),
                onChanged: (vals) {
                  setTrimState(() {
                    start = vals.start;
                    end = vals.end;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
              onPressed: () async {
                Navigator.pop(ctx);
                _showMsg("Saving trimmed file...");
                final outDir = await _getAppDir(item.isVideo);
                final ext = item.isVideo ? "mp4" : "mp3";
                final outPath = "$outDir/cut_${DateTime.now().millisecondsSinceEpoch}.$ext";

                await Process.run('ffmpeg', [
                  '-ss', '${start.toInt()}',
                  '-i', item.file.path,
                  '-t', '${(end - start).toInt()}',
                  '-c', 'copy',
                  outPath,
                  '-y'
                ]);
                await _scanStorage();
                _showMsg("Trimmed file saved!");
              },
              child: const Text("Save Cut", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
        elevation: 0,
        titleSpacing: 16,
        title: const Text('Mehra Player', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.sort_rounded, color: Colors.white70), tooltip: "Sort Files", onPressed: _showSortDialog),
          IconButton(icon: const Icon(Icons.download_rounded, color: Color(0xFF00E676)), tooltip: "Downloader", onPressed: _showDownloaderDialog),
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: Colors.white70),
            onPressed: () async {
              final res = await FilePicker.platform.pickFiles(type: FileType.media);
              if (res != null && res.files.single.path != null) {
                final f = File(res.files.single.path!);
                _launchPlayer([MediaFile(file: f, title: f.path.split(Platform.pathSeparator).last, sizeBytes: f.lengthSync(), isVideo: !f.path.endsWith('.mp3'), folderName: 'Browse', modifiedTime: DateTime.now())], 0);
              }
            },
          ),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white70), onPressed: _scanStorage),
          const SizedBox(width: 8),
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
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1C26),
                      borderRadius: BorderRadius.circular(8),
                      image: item.thumbPath != null ? DecorationImage(image: FileImage(File(item.thumbPath!)), fit: BoxFit.cover) : null,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.thumbPath == null) Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white.withOpacity(0.3), size: 36)),
                        Positioned(
                          left: 0, right: 0, bottom: 0,
                          child: Container(
                            color: Colors.black54, padding: const EdgeInsets.all(4),
                            child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
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

          return InkWell(
            onTap: () => _launchPlayer(videoList, index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 124,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1F2B),
                      borderRadius: BorderRadius.circular(8),
                      image: item.thumbPath != null ? DecorationImage(image: FileImage(File(item.thumbPath!)), fit: BoxFit.cover) : null,
                    ),
                    child: item.thumbPath == null ? Center(child: Icon(Icons.movie_creation_outlined, color: Colors.white.withOpacity(0.3), size: 32)) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        const SizedBox(height: 4),
                        Text("${item.folderName} | ${item.formattedSize}", style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5))),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: Colors.white.withOpacity(0.4)),
                    color: const Color(0xFF1C1D27),
                    onSelected: (val) {
                      if (val == "play") _launchPlayer(videoList, index);
                      if (val == "trim") _openTrimDialog(item);
                      if (val == "delete") {
                        item.file.deleteSync();
                        _scanStorage();
                      }
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: "play", child: Row(children: [Icon(Icons.play_arrow, size: 18), SizedBox(width: 8), Text("Play")])),
                      PopupMenuItem(value: "trim", child: Row(children: [Icon(Icons.content_cut, size: 18), SizedBox(width: 8), Text("Cut / Trim")])),
                      PopupMenuItem(value: "delete", child: Row(children: [Icon(Icons.delete, color: Colors.redAccent, size: 18), SizedBox(width: 8), Text("Delete")])),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMusicTab() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: audioList.length,
      itemBuilder: (ctx, i) {
        final item = audioList[i];
        return ListTile(
          onTap: () => _launchPlayer(audioList, i),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.audiotrack_rounded, color: Color(0xFF00E676)),
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
          subtitle: Text("${item.folderName} | ${item.formattedSize}", style: const TextStyle(fontSize: 11, color: Colors.white38)),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white38),
            color: const Color(0xFF1C1D27),
            onSelected: (val) {
              if (val == "play") _launchPlayer(audioList, i);
              if (val == "trim") _openTrimDialog(item);
              if (val == "delete") {
                item.file.deleteSync();
                _scanStorage();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: "play", child: Row(children: [Icon(Icons.play_arrow, size: 18), SizedBox(width: 8), Text("Play")])),
              PopupMenuItem(value: "trim", child: Row(children: [Icon(Icons.content_cut, size: 18), SizedBox(width: 8), Text("Cut / Trim")])),
              PopupMenuItem(value: "delete", child: Row(children: [Icon(Icons.delete, color: Colors.redAccent, size: 18), SizedBox(width: 8), Text("Delete")])),
            ],
          ),
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
  late AnimationController _flowAnimCtrl;
  late TransformationController _transformController;
  late int currentIndex;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  bool controlsVisible = true;
  bool isLocked = false;
  bool isMuted = false;
  bool isLandscape = false;
  double playbackSpeed = 1.0;
  BoxFit currentFit = BoxFit.contain;

  // Swipe Gestures
  double brightness = 0.5;
  double volume = 1.0;
  bool showGestureIndicator = false;
  String gestureType = "";
  double gestureValue = 0.0;

  // Floating PiP Window State
  bool isFloatingPip = false;
  Offset pipOffset = const Offset(20, 100);

  // Zoom modes
  int aspectIndex = 0;
  final List<String> aspectModes = ["FIT", "FILL", "ZOOM 100%", "ZOOM 125%", "ZOOM 150%", "ZOOM 200%"];
  double currentScale = 1.0;

  final List<double> availableSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 5.0, 10.0];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    currentIndex = widget.initialIndex;

    _discAnimCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8));
    _flowAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    _transformController = TransformationController();

    try {
      (player.platform as dynamic)?.setProperty('framedrop', 'vo');
      (player.platform as dynamic)?.setProperty('video-sync', 'audio');
      (player.platform as dynamic)?.setProperty('demuxer-max-bytes', '157286400');
      (player.platform as dynamic)?.setProperty('vd-lavc-fast', 'yes');
      (player.platform as dynamic)?.setProperty('scale', 'bilinear');
      (player.platform as dynamic)?.setProperty('dscale', 'bilinear');
    } catch (_) {}

    player.stream.playing.listen((p) {
      if (mounted) {
        setState(() => isPlaying = p);
        if (p) {
          _discAnimCtrl.repeat();
          _flowAnimCtrl.repeat(reverse: true);
        } else {
          _discAnimCtrl.stop();
          _flowAnimCtrl.stop();
        }
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
    if (state == AppLifecycleState.paused) {
      if (isPlaying) player.play();
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
    _flowAnimCtrl.dispose();
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

  void _cycleAspectAndZoom() {
    setState(() {
      aspectIndex = (aspectIndex + 1) % aspectModes.length;
      final mode = aspectModes[aspectIndex];
      if (mode == "FIT") {
        currentFit = BoxFit.contain;
        currentScale = 1.0;
      } else if (mode == "FILL") {
        currentFit = BoxFit.cover;
        currentScale = 1.0;
      } else if (mode == "ZOOM 100%") {
        currentFit = BoxFit.contain;
        currentScale = 1.0;
      } else if (mode == "ZOOM 125%") {
        currentFit = BoxFit.cover;
        currentScale = 1.25;
      } else if (mode == "ZOOM 150%") {
        currentFit = BoxFit.cover;
        currentScale = 1.5;
      } else if (mode == "ZOOM 200%") {
        currentFit = BoxFit.cover;
        currentScale = 2.0;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Mode: ${aspectModes[aspectIndex]}"), duration: const Duration(milliseconds: 900)));
  }

  void _setSpeed(double s) {
    setState(() => playbackSpeed = s);
    player.setRate(s);
  }

  void _openSpeedSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141522),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text("Playback Speed", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 10,
              children: availableSpeeds.map((s) {
                final isSel = playbackSpeed == s;
                return ChoiceChip(
                  label: Text("${s}x", style: TextStyle(color: isSel ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
                  selected: isSel,
                  selectedColor: const Color(0xFF00E676),
                  backgroundColor: const Color(0xFF22232E),
                  onSelected: (_) {
                    Navigator.pop(ctx);
                    _setSpeed(s);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidePillButton({required IconData icon, Color color = Colors.white, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white24)),
        child: Icon(icon, color: color, size: 20),
      ),
    );
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
            animation: _flowAnimCtrl,
            builder: (context, child) {
              final flowGlow = _flowAnimCtrl.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 270 + (flowGlow * 20),
                    height: 270 + (flowGlow * 20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF00E676).withOpacity(0.35 * flowGlow),
                          Colors.cyanAccent.withOpacity(0.15 * flowGlow),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _discAnimCtrl,
                    builder: (context, discChild) {
                      return Transform.rotate(
                        angle: _discAnimCtrl.value * 2 * math.pi,
                        child: discChild,
                      );
                    },
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.9), blurRadius: 30, spreadRadius: 4),
                        ],
                        gradient: const SweepGradient(
                          colors: [
                            Color(0xFF14151C),
                            Color(0xFF282A38),
                            Color(0xFF14151C),
                            Color(0xFF282A38),
                            Color(0xFF14151C),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF00E676), width: 3),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00E676), Colors.tealAccent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.music_note_rounded, size: 50, color: Colors.black),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 36),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              item.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Text(item.formattedSize, style: const TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 22),
          AnimatedBuilder(
            animation: _flowAnimCtrl,
            builder: (context, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(16, (idx) {
                  final h = 6 + (28 * math.sin((_flowAnimCtrl.value * math.pi) + (idx * 0.45)).abs());
                  return Container(
                    width: 4,
                    height: isPlaying ? h : 5,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      color: idx % 2 == 0 ? const Color(0xFF00E676) : Colors.cyanAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.playlist[currentIndex];
    final remainingDuration = duration - position;
    final screenWidth = MediaQuery.of(context).size.width;

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
                    ),
                    child: Stack(
                      children: [
                        Video(controller: controller, controls: NoVideoControls, fit: BoxFit.cover),
                        Positioned(
                          right: 4, top: 4,
                          child: GestureDetector(
                            onTap: () => setState(() => isFloatingPip = false),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18),
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
              ClipRect(
                child: Transform.scale(
                  scale: currentScale,
                  alignment: Alignment.center,
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 1.0,
                    maxScale: 3.5,
                    scaleEnabled: !isLocked,
                    child: SizedBox.expand(
                      child: Video(controller: controller, controls: NoVideoControls, fit: currentFit),
                    ),
                  ),
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

            // Left Side Pills (Mute, Lock)
            if (controlsVisible)
              Positioned(
                left: 14,
                top: MediaQuery.of(context).size.height * 0.44,
                child: Column(
                  children: [
                    _sidePillButton(
                      icon: isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      onTap: () {
                        setState(() => isMuted = !isMuted);
                        player.setVolume(isMuted ? 0 : 100);
                      },
                    ),
                    const SizedBox(height: 12),
                    _sidePillButton(
                      icon: isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      color: isLocked ? Colors.redAccent : const Color(0xFF00E676),
                      onTap: () => setState(() => isLocked = !isLocked),
                    ),
                  ],
                ),
              ),

            // Right Side Pills (Crop/Fit, PiP)
            if (controlsVisible && !isLocked && currentItem.isVideo)
              Positioned(
                right: 14,
                top: MediaQuery.of(context).size.height * 0.44,
                child: Column(
                  children: [
                    _sidePillButton(
                      icon: Icons.picture_in_picture_alt_rounded,
                      color: const Color(0xFF00E676),
                      onTap: () => setState(() => isFloatingPip = true),
                    ),
                    const SizedBox(height: 12),
                    _sidePillButton(
                      icon: Icons.crop_portrait_rounded,
                      onTap: _cycleAspectAndZoom,
                    ),
                  ],
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
                          InkWell(
                            onTap: () {
                              int next = (availableSpeeds.indexOf(playbackSpeed) + 1) % availableSpeeds.length;
                              _setSpeed(availableSpeeds[next]);
                            },
                            onLongPress: _openSpeedSelector,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                              child: Text("${playbackSpeed}x", style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.fullscreen_rounded, color: Color(0xFF00E676), size: 26),
                            onPressed: _cycleAspectAndZoom,
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
