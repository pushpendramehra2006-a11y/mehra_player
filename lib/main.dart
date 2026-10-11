import 'dart:io';
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
  final File file;
  final String title;
  final int sizeBytes;
  final bool isVideo;
  final String folderName;

  MediaFile({
    required this.file,
    required this.title,
    required this.sizeBytes,
    required this.isVideo,
    required this.folderName,
  });

  String get formattedSize {
    if (sizeBytes < 1024 * 1024) return "${(sizeBytes / 1024).toStringAsFixed(1)} KB";
    return "${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB";
  }
}

// ---------------- MAIN TABS SCREEN (PLAYit Style + Downloader) ----------------
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

  Future<String> _getDownloadDir(bool isVideo) async {
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

              if (p.endsWith('.mp4') || p.endsWith('.mkv') || p.endsWith('.avi') || p.endsWith('.mov') || p.endsWith('.webm')) {
                vids.add(MediaFile(file: e, title: name, sizeBytes: e.lengthSync(), isVideo: true, folderName: folder));
              } else if (p.endsWith('.mp3') || p.endsWith('.wav') || p.endsWith('.m4a') || p.endsWith('.flac') || p.endsWith('.ogg')) {
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
        if (vids.isNotEmpty) {
          historyList = vids.take(5).toList();
        }
        isLoading = false;
      });
    }
  }

  void _showDownloaderDialog() {
    final urlController = TextEditingController();
    String downloadType = "mp4"; // mp4 or mp3
    bool isDownloading = false;
    double progress = 0.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF171822),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.download_for_offline_rounded, color: Color(0xFF00E676)),
              SizedBox(width: 8),
              Text("Download MP4 / MP3", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  hintText: "Paste direct MP4 or MP3 Link here...",
                  hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                  filled: true,
                  fillColor: Colors.black26,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text("Format: ", style: TextStyle(color: Colors.white70)),
                  ChoiceChip(
                    label: const Text("MP4 Video"),
                    selected: downloadType == "mp4",
                    selectedColor: const Color(0xFF00E676),
                    onSelected: (s) => setDialogState(() => downloadType = "mp4"),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text("MP3 Audio"),
                    selected: downloadType == "mp3",
                    selectedColor: const Color(0xFF00E676),
                    onSelected: (s) => setDialogState(() => downloadType = "mp3"),
                  ),
                ],
              ),
              if (isDownloading) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(color: Color(0xFF00E676)),
                const SizedBox(height: 6),
                const Text("Downloading in progress...", style: TextStyle(fontSize: 11, color: Colors.white54)),
              ]
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
              onPressed: isDownloading
                  ? null
                  : () async {
                      final url = urlController.text.trim();
                      if (url.isEmpty || !url.startsWith("http")) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Valid URL enter karein!")));
                        return;
                      }

                      setDialogState(() => isDownloading = true);

                      try {
                        final outDir = await _getDownloadDir(downloadType == "mp4");
                        final fileName = "Download_${DateTime.now().millisecondsSinceEpoch}.$downloadType";
                        final filePath = "$outDir/$fileName";

                        final response = await http.get(Uri.parse(url));
                        if (response.statusCode == 200) {
                          final file = File(filePath);
                          await file.writeAsBytes(response.bodyBytes);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Downloaded Successfully: $fileName")));
                          await _scanStorage();
                        } else {
                          setDialogState(() => isDownloading = false);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download failed. Link check karein.")));
                        }
                      } catch (e) {
                        setDialogState(() => isDownloading = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                      }
                    },
              child: const Text("Download Now", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _convertVideoToAudio(MediaFile video) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Extracting MP3 from '${video.title}'...")));
    try {
      final outDir = await _getDownloadDir(false);
      final clean = video.title.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      final outPath = "$outDir/${clean}_audio.mp3";

      final res = await Process.run('ffmpeg', [
        '-i', video.file.path,
        '-vn',
        '-acodec', 'libmp3lame',
        '-q:a', '2',
        outPath,
        '-y'
      ]);

      if (res.exitCode == 0) {
        await _scanStorage();
        setState(() => _currentNavIndex = 1); // Switch to MUSIC Tab
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("MP3 ready! Switched to Music tab.")));
      }
    } catch (_) {}
  }

  void _launchPlayer(List<MediaFile> list, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayitVideoPlayer(
          playlist: list,
          initialIndex: index,
          onConvertAudio: _convertVideoToAudio,
        ),
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
        titleSpacing: 16,
        title: const Text(
          'Mehra Player',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5, color: Colors.white),
        ),
        actions: [
          // PLAYit Direct Download Button
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Color(0xFF00E676), size: 24),
            tooltip: 'Download MP4 / MP3',
            onPressed: _showDownloaderDialog,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: Colors.white70, size: 24),
            onPressed: () async {
              final res = await FilePicker.platform.pickFiles(type: FileType.media);
              if (res != null && res.files.single.path != null) {
                final f = File(res.files.single.path!);
                final item = MediaFile(
                  file: f,
                  title: f.path.split(Platform.pathSeparator).last,
                  sizeBytes: f.lengthSync(),
                  isVideo: !f.path.toLowerCase().endsWith('.mp3'),
                  folderName: 'Browse',
                );
                _launchPlayer([item], 0);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 24),
            onPressed: _scanStorage,
          ),
          const SizedBox(width: 8),
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
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.smart_display_rounded), label: "VIDEO"),
          BottomNavigationBarItem(icon: Icon(Icons.music_note_rounded), label: "MUSIC"),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_rounded), label: "EFFECTS"),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: "ME"),
        ],
      ),
    );
  }

  Widget _buildVideosTab() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        if (historyList.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                Icon(Icons.delete_outline_rounded, color: Colors.white.withOpacity(0.35), size: 20),
              ],
            ),
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
                      border: Border.all(color: Colors.white10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white.withOpacity(0.3), size: 36)),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.all(4),
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, color: Colors.white),
                            ),
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

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text(
                "Video",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF00E676),
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF00E676),
                  decorationThickness: 2,
                ),
              ),
              const SizedBox(width: 20),
              const Text("Folder", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white54)),
              const SizedBox(width: 20),
              const Text("Playlist", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white54)),
              const Spacer(),
              const Icon(Icons.swap_vert_rounded, color: Colors.white54, size: 20),
              const SizedBox(width: 12),
              const Icon(Icons.grid_view_rounded, color: Colors.white54, size: 18),
            ],
          ),
        ),

        const SizedBox(height: 10),

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
                      border: Border.all(color: Colors.white10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(child: Icon(Icons.movie_creation_outlined, color: Colors.white.withOpacity(0.25), size: 32)),
                        Positioned(
                          right: 6,
                          bottom: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(4)),
                            child: const Text("HD", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "1080p | ${item.formattedSize}",
                          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.55)),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.folder_outlined, size: 12, color: Colors.white.withOpacity(0.4)),
                            const SizedBox(width: 4),
                            Text(
                              item.folderName,
                              style: TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(0.4)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: Colors.white.withOpacity(0.4)),
                    color: const Color(0xFF1C1D27),
                    onSelected: (val) {
                      if (val == "audio") _convertVideoToAudio(item);
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: "audio",
                        child: Row(
                          children: [
                            Icon(Icons.music_note_rounded, color: Color(0xFF00E676), size: 18),
                            SizedBox(width: 8),
                            Text("Convert to MP3"),
                          ],
                        ),
                      ),
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
      padding: const EdgeInsets.all(12),
      itemCount: audioList.length,
      itemBuilder: (ctx, i) {
        final item = audioList[i];
        return ListTile(
          onTap: () => _launchPlayer(audioList, i),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.audiotrack_rounded, color: Color(0xFF00E676)),
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: Colors.white)),
          subtitle: Text("${item.folderName} | ${item.formattedSize}", style: const TextStyle(fontSize: 11, color: Colors.white38)),
          trailing: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF00E676)),
        );
      },
    );
  }
}

// ---------------- PLAYER SCREEN WITH PRO SHEET & AUDIO FX ----------------
class PlayitVideoPlayer extends StatefulWidget {
  final List<MediaFile> playlist;
  final int initialIndex;
  final Function(MediaFile)? onConvertAudio;

  const PlayitVideoPlayer({
    super.key,
    required this.playlist,
    required this.initialIndex,
    this.onConvertAudio,
  });

  @override
  State<PlayitVideoPlayer> createState() => _PlayitVideoPlayerState();
}

class _PlayitVideoPlayerState extends State<PlayitVideoPlayer> {
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

  bool controlsVisible = true;
  bool isLocked = false;
  bool isMuted = false;
  bool isNightMode = false;
  bool isMirrorMode = false;
  double brightness = 1.0;
  double playbackSpeed = 1.0;
  BoxFit currentFit = BoxFit.contain;
  String currentEffect = "Normal";

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;

    player.stream.playing.listen((p) {
      if (mounted) setState(() => isPlaying = p);
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
  void dispose() {
    player.dispose();
    super.dispose();
  }

  void _openMedia(int index) async {
    if (index < 0 || index >= widget.playlist.length) return;
    setState(() => currentIndex = index);
    await player.open(Media(widget.playlist[index].file.path));
    await player.play();
  }

  void _applyAudioEffect(String mode) {
    setState(() => currentEffect = mode);
    if (mode == "8D") {
      player.setRate(1.0);
      player.setVolume(125);
    } else if (mode == "16D") {
      player.setRate(1.0);
      player.setVolume(140);
    } else if (mode == "Lofi") {
      player.setRate(0.88);
      player.setVolume(110);
    } else {
      player.setRate(playbackSpeed);
      player.setVolume(100);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$mode Audio Effect Active!")));
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return "$m:$s";
  }

  void _openProSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14151B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Wrap(
            runSpacing: 18,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _proIconBtn(Icons.headphones_rounded, "Audio play", () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Playing audio in background!")));
                  }),
                  _proIconBtn(Icons.music_note_rounded, "MP3 Extract", () {
                    Navigator.pop(ctx);
                    if (widget.onConvertAudio != null) {
                      widget.onConvertAudio!(widget.playlist[currentIndex]);
                    }
                  }),
                  _proIconBtn(Icons.equalizer_rounded, "8D / FX\n($currentEffect)", () {
                    Navigator.pop(ctx);
                    _showEffectDialog();
                  }, active: currentEffect != "Normal"),
                  _proIconBtn(Icons.cast_rounded, "Cast", () {}),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _proIconBtn(Icons.share_outlined, "Share", () {}),
                  _proIconBtn(Icons.content_cut_rounded, "Cut/Trim", () {
                    Navigator.pop(ctx);
                    _showTrimTool();
                  }),
                  _proIconBtn(Icons.star_border_rounded, "Favorite", () {}),
                  _proIconBtn(Icons.bookmark_border_rounded, "Bookmark", () {}),
                ],
              ),

              const Divider(color: Colors.white12),

              const Text("Play settings", style: TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.bold)),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _proIconBtn(Icons.repeat_one_rounded, "AB Repeat", () {}),
                  _proIconBtn(Icons.nightlight_round, "Night mode", () {
                    setSheet(() => isNightMode = !isNightMode);
                    setState(() => isNightMode = isNightMode);
                  }, active: isNightMode),
                  _proIconBtn(Icons.flip_rounded, "Mirror mode", () {
                    setSheet(() => isMirrorMode = !isMirrorMode);
                    setState(() => isMirrorMode = isMirrorMode);
                  }, active: isMirrorMode),
                  _proIconBtn(Icons.timer_outlined, "Timer", () {}),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEffectDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141522),
        title: const Text("Audio FX Profile"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ["Normal", "8D Audio", "16D Audio", "Lofi Chill"].map((mode) {
            return ListTile(
              title: Text(mode),
              leading: Icon(Icons.graphic_eq_rounded, color: currentEffect == mode ? const Color(0xFF00E676) : Colors.white38),
              onTap: () {
                Navigator.pop(context);
                _applyAudioEffect(mode);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _proIconBtn(IconData icon, String label, VoidCallback onTap, {bool active = false}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? const Color(0xFF00E676).withOpacity(0.2) : Colors.white.withOpacity(0.06),
              border: Border.all(color: active ? const Color(0xFF00E676) : Colors.transparent),
            ),
            child: Icon(icon, color: active ? const Color(0xFF00E676) : Colors.white70, size: 21),
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
        ],
      ),
    );
  }

  void _showTrimTool() {
    final item = widget.playlist[currentIndex];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Trimming '${item.title}' with FFmpeg...")));
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.playlist[currentIndex];
    final remainingDuration = duration - position;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => controlsVisible = !controlsVisible),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..setEntry(0, 0, isMirrorMode ? -1 : 1),
              child: Video(controller: controller, controls: NoVideoControls, fit: currentFit),
            ),

            if (isNightMode) IgnorePointer(child: Container(color: Colors.amber.withOpacity(0.18))),

            // Double Tap Seeking zones
            Positioned(
              left: 0,
              top: 80,
              bottom: 80,
              width: MediaQuery.of(context).size.width * 0.35,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () => player.seek(position - const Duration(seconds: 10)),
              ),
            ),
            Positioned(
              right: 0,
              top: 80,
              bottom: 80,
              width: MediaQuery.of(context).size.width * 0.35,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () => player.seek(position + const Duration(seconds: 10)),
              ),
            ),

            // Left Side Action Buttons
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
                      color: isLocked ? Colors.redAccent : Colors.white,
                      onTap: () => setState(() => isLocked = !isLocked),
                    ),
                  ],
                ),
              ),

            // Right Side Action Buttons
            if (controlsVisible && !isLocked)
              Positioned(
                right: 14,
                top: MediaQuery.of(context).size.height * 0.44,
                child: Column(
                  children: [
                    _sidePillButton(icon: Icons.content_cut_rounded, onTap: _showTrimTool),
                    const SizedBox(height: 12),
                    _sidePillButton(
                      icon: Icons.crop_portrait_rounded,
                      onTap: () {
                        setState(() {
                          currentFit = currentFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
                        });
                      },
                    ),
                  ],
                ),
              ),

            // Top Header Bar
            if (controlsVisible && !isLocked)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
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
                        child: Text(
                          currentItem.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(4)),
                        child: const Text("HDR", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                        onPressed: _openProSettingsSheet,
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom Controller
            if (controlsVisible && !isLocked)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
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
                            iconSize: 32,
                            icon: Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: Colors.white),
                            onPressed: () => player.playOrPause(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 26),
                            onPressed: () {
                              if (currentIndex > 0) _openMedia(currentIndex - 1);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 26),
                            onPressed: () {
                              if (currentIndex + 1 < widget.playlist.length) _openMedia(currentIndex + 1);
                            },
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                playbackSpeed = playbackSpeed == 1.0 ? 1.5 : (playbackSpeed == 1.5 ? 2.0 : 1.0);
                                player.setRate(playbackSpeed);
                              });
                            },
                            child: Text("${playbackSpeed}x", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.crop_free_rounded, color: Colors.white70, size: 22),
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
  }

  Widget _sidePillButton({required IconData icon, Color color = Colors.white, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
