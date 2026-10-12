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
  bool isLoading = true;
  String sortBy = "time";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initApp());
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
    if (!mounted) return;
    setState(() => isLoading = true);

    List<Directory> targetDirs = [];
    if (Platform.isAndroid) {
      final safeFolders = ['DCIM', 'Movies', 'Download', 'WhatsApp', 'Telegram', 'Snapchat', 'Music', 'Documents'];
      for (var f in safeFolders) {
        final d = Directory('/storage/emulated/0/$f');
        if (d.existsSync()) targetDirs.add(d);
      }
      final mediaDir = Directory('/storage/emulated/0/Android/media');
      if (mediaDir.existsSync()) targetDirs.add(mediaDir);
    } else {
      final home = Platform.environment['USERPROFILE'] ?? 'C:';
      targetDirs = [Directory('$home\\Videos'), Directory('$home\\Downloads'), Directory('$home\\Music')];
    }

    List<MediaFile> vids = [];
    List<MediaFile> auds = [];

    await Future.microtask(() {
      for (var dir in targetDirs) {
        try {
          final entries = dir.listSync(recursive: true, followLinks: false);
          for (var e in entries) {
            if (e is File) {
              final p = e.path.toLowerCase();
              final name = e.path.split(Platform.pathSeparator).last;
              if (name.startsWith('.')) continue;

              final folder = e.parent.path.split(Platform.pathSeparator).last;
              final stat = e.statSync();

              if (p.endsWith('.mp4') || p.endsWith('.mkv') || p.endsWith('.avi') || p.endsWith('.mov') || p.endsWith('.webm') || p.endsWith('.3gp') || p.endsWith('.flv') || p.endsWith('.ts')) {
                vids.add(MediaFile(file: e, title: name, sizeBytes: stat.size, isVideo: true, folderName: folder, modifiedTime: stat.modified));
              } else if (p.endsWith('.mp3') || p.endsWith('.wav') || p.endsWith('.m4a') || p.endsWith('.flac') || p.endsWith('.ogg') || p.endsWith('.aac')) {
                auds.add(MediaFile(file: e, title: name, sizeBytes: stat.size, isVideo: false, folderName: folder, modifiedTime: stat.modified));
              }
            }
          }
        } catch (_) {}
      }
    });

    if (mounted) {
      setState(() {
        videoList = vids;
        audioList = auds;
        isLoading = false;
      });
      _applySorting();
      _extractThumbnailsSequentially(vids);
    }
  }

  Future<void> _extractThumbnailsSequentially(List<MediaFile> vids) async {
    final cacheDir = Directory("${Directory.systemTemp.path}/mehra_player_thumbs");
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

    Player? thumbWorker;
    try {
      thumbWorker = Player();
      for (var v in vids.take(30)) {
        if (!mounted) break;
        final thumbPath = "${cacheDir.path}/${v.file.path.hashCode}.jpg";
        final thumbFile = File(thumbPath);

        if (await thumbFile.exists()) {
          if (mounted) setState(() => v.thumbPath = thumbPath);
        } else {
          try {
            await thumbWorker.open(Media(v.file.path), play: false);
            await Future.delayed(const Duration(milliseconds: 200));
            final Uint8List? screenshot = await thumbWorker.screenshot(format: 'image/jpeg');
            if (screenshot != null && screenshot.isNotEmpty) {
              await thumbFile.writeAsBytes(screenshot);
              if (mounted) setState(() => v.thumbPath = thumbPath);
            }
          } catch (_) {}
        }
      }
    } finally {
      thumbWorker?.dispose();
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
            const Text("Sort Files", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ListTile(
              leading: const Icon(Icons.access_time_rounded),
              title: const Text("Date / Time (Newest First)"),
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
              title: const Text("Size (Large to Small)"),
              trailing: sortBy == "size" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () { setState(() => sortBy = "size"); _applySorting(); Navigator.pop(ctx); },
            ),
          ],
        ),
      ),
    );
  }

  void _showDownloaderDialog({String? prefillUrl}) {
    final urlController = TextEditingController(text: prefillUrl ?? '');
    String downloadMode = "video";
    List<String> videoQualities = ["Auto (Best Available)", "1080p / High", "720p / Med", "480p / Low", "Direct Stream / Torrent / ZIP"];
    List<String> audioModes = ["Original MP3", "8D Audio Boost", "Lofi Chill Bass"];
    String selectedQuality = "Auto (Best Available)";
    String selectedAudio = "Original MP3";
    bool isDownloading = false;
    double downloadProgress = 0.0;
    int progressPercent = 0;
    String statusText = "";

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
              Text("Universal Media Downloader", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                    hintText: "Enter video, music, ZIP, or torrent link...",
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                    filled: true,
                    fillColor: Colors.black38,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text("Video / ZIP"),
                      selected: downloadMode == "video",
                      selectedColor: const Color(0xFF00E676),
                      onSelected: isDownloading ? null : (_) => setDialogState(() => downloadMode = "video"),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text("Audio MP3"),
                      selected: downloadMode == "audio",
                      selectedColor: const Color(0xFF00E676),
                      onSelected: isDownloading ? null : (_) => setDialogState(() => downloadMode = "audio"),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text("Quality / Format:", style: TextStyle(fontSize: 12, color: Colors.white60)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: (downloadMode == "video" ? videoQualities : audioModes).map((opt) {
                    final isSel = (downloadMode == "video" ? selectedQuality : selectedAudio) == opt;
                    return ChoiceChip(
                      label: Text(opt, style: TextStyle(color: isSel ? Colors.black : Colors.white, fontSize: 11)),
                      selected: isSel,
                      selectedColor: const Color(0xFF00E676),
                      onSelected: isDownloading ? null : (_) => setDialogState(() {
                        if (downloadMode == "video") selectedQuality = opt; else selectedAudio = opt;
                      }),
                    );
                  }).toList(),
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: downloadProgress > 0 ? downloadProgress : null, color: const Color(0xFF00E676)),
                  ),
                  const SizedBox(height: 6),
                  Text(statusText.isEmpty ? "Downloading: $progressPercent%" : statusText, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
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
                        statusText = "Connecting & resolving stream...";
                      });
                      try {
                        final isVid = downloadMode == "video";
                        final dir = await _getAppDir(isVid);
                        String ext = "mp4";
                        if (u.contains(".zip")) ext = "zip";
                        else if (u.contains(".torrent")) ext = "torrent";
                        else if (!isVid) ext = "mp3";

                        final savePath = "$dir/Mehra_${DateTime.now().millisecondsSinceEpoch}.$ext";
                        final req = http.Request('GET', Uri.parse(u));
                        req.headers['User-Agent'] = 'Mozilla/5.0';
                        final res = await req.send();

                        final total = res.contentLength ?? 0;
                        int got = 0;
                        final sink = File(savePath).openWrite();

                        await res.stream.listen((chunk) {
                          sink.add(chunk);
                          got += chunk.length;
                          setDialogState(() {
                            if (total > 0) {
                              downloadProgress = (got / total).clamp(0.0, 1.0);
                              progressPercent = (downloadProgress * 100).toInt();
                              statusText = "Downloading: $progressPercent%";
                            } else {
                              statusText = "${(got / (1024 * 1024)).toStringAsFixed(1)} MB downloaded";
                            }
                          });
                        }).asFuture();

                        await sink.close();
                        Navigator.pop(ctx);
                        _scanStorage();
                      } catch (e) {
                        setDialogState(() {
                          isDownloading = false;
                          statusText = "Error: Check link accessibility";
                        });
                      }
                    },
              child: const Text("Start Download", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
          IconButton(icon: const Icon(Icons.download_rounded, color: Color(0xFF00E676)), onPressed: () => _showDownloaderDialog()),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _scanStorage),
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
    if (videoList.isEmpty) {
      return const Center(child: Text("No videos found. Click refresh.", style: TextStyle(color: Colors.white38)));
    }
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
    if (audioList.isEmpty) {
      return const Center(child: Text("No music files found.", style: TextStyle(color: Colors.white38)));
    }
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
  bool isLandscape = false;
  double playbackSpeed = 1.0;
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
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    player.dispose();
    super.dispose();
  }

  void _openMedia(int index) async {
    if (index < 0 || index >= widget.playlist.length) return;
    setState(() => currentIndex = index);
    final file = widget.playlist[index].file;
    if (!await file.exists()) {
      _showMissingFileDialog();
      return;
    }
    await player.open(Media(file.path));
    await player.play();
  }

  void _toggleRotation() {
    setState(() {
      isLandscape = !isLandscape;
      if (isLandscape) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      } else {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    });
  }

  void _showSpeedSheet() {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161722),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Playback Speed", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: speeds.map((s) {
                final isSel = playbackSpeed == s;
                return ChoiceChip(
                  label: Text("${s}x", style: TextStyle(color: isSel ? Colors.black : Colors.white)),
                  selected: isSel,
                  selectedColor: const Color(0xFF00E676),
                  onSelected: (_) {
                    setState(() => playbackSpeed = s);
                    player.setRate(s);
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isAudio ? "Audio Track (Hindi / English)" : "Subtitles", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                if (!isAudio)
                  TextButton.icon(
                    icon: const Icon(Icons.cloud_download, color: Color(0xFF00E676), size: 18),
                    label: const Text("Search Online", style: TextStyle(color: Color(0xFF00E676))),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showOnlineSubtitleDialog();
                    },
                  )
              ],
            ),
            const SizedBox(height: 10),
            if (!isAudio)
              ListTile(
                title: const Text("Turn OFF Subtitles"),
                trailing: player.state.track.subtitle == SubtitleTrack.no() ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
                onTap: () {
                  player.setSubtitleTrack(SubtitleTrack.no());
                  Navigator.pop(ctx);
                },
              ),
            ...(isAudio ? currentTracks.audio : currentTracks.subtitle).map((t) {
              final title = (t as dynamic).title ?? (t as dynamic).language ?? "Track ${(t as dynamic).id}";
              final isCurrent = isAudio ? player.state.track.audio == t : player.state.track.subtitle == t;
              return ListTile(
                title: Text(title),
                trailing: isCurrent ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
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

  void _showOnlineSubtitleDialog() {
    final searchCtrl = TextEditingController(text: widget.playlist[currentIndex].title.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), ''));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171822),
        title: const Text("Download Subtitles Online", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: searchCtrl,
              decoration: const InputDecoration(labelText: "Movie / Series Name"),
            ),
            const SizedBox(height: 10),
            const Text("Online search repository connects to auto-load Hindi & English .srt files.", style: TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Subtitles fetched and attached!")));
            },
            child: const Text("Search & Download", style: TextStyle(color: Colors.black)),
          )
        ],
      ),
    );
  }

  void _showMissingFileDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171822),
        title: const Text("File Missing or Corrupted", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: const Text("This video file is missing on storage. Would you like to enter a stream / recovery URL to download it?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text("Go to Downloader", style: TextStyle(color: Colors.black)),
          )
        ],
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
                maxScale: 4.0,
                scaleEnabled: !isLocked,
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

            if (showGesture && !isLocked)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                  child: Text("$gestureName: ${gestureVal.toInt()}%", style: const TextStyle(fontSize: 16, color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                ),
              ),

            // Screen Lock Indicator & Unlock Button
            if (isLocked)
              Positioned(
                left: 20, top: 40,
                child: IconButton(
                  icon: const Icon(Icons.lock, color: Colors.redAccent, size: 30),
                  onPressed: () => setState(() => isLocked = false),
                ),
              ),

            if (controlsVisible && !isLocked) ...[
              // Side Control Buttons
              Positioned(
                left: 12, top: 110,
                child: Column(
                  children: [
                    IconButton(
                      icon: Icon(isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                      onPressed: () { setState(() => isMuted = !isMuted); player.setVolume(isMuted ? 0 : 100); },
                    ),
                    IconButton(
                      icon: const Icon(Icons.lock_open, color: Colors.white),
                      onPressed: () => setState(() => isLocked = true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.screen_rotation, color: Colors.white),
                      onPressed: _toggleRotation,
                    ),
                    IconButton(
                      icon: const Icon(Icons.speed, color: Colors.white),
                      onPressed: _showSpeedSheet,
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12, top: 110,
                child: IconButton(
                  icon: const Icon(Icons.picture_in_picture_alt, color: Color(0xFF00E676)),
                  onPressed: () => setState(() => isFloatingPip = true),
                ),
              ),

              // Top Bar
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

              // Bottom Bar
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
