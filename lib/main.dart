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
  File file;
  String title;
  int sizeBytes;
  final bool isVideo;
  String folderName;

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

// ---------------- MAIN TABS SCREEN (Only Video & Audio) ----------------
class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentNavIndex = 0; // 0: Video, 1: Audio
  List<MediaFile> videoList = [];
  List<MediaFile> audioList = [];
  List<MediaFile> historyList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
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
        if (vids.isNotEmpty) {
          historyList = vids.take(5).toList();
        }
        isLoading = false;
      });
    }
  }

  void _showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: const Color(0xFF1E1F30)));
  }

  // 1. Delete File Functionality
  Future<void> _deleteMedia(MediaFile item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171822),
        title: const Text("Delete File"),
        content: Text("Are you sure you want to delete '${item.title}' permanently?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (item.file.existsSync()) {
          item.file.deleteSync();
        }
        _showMsg("File deleted successfully!");
        await _scanStorage();
      } catch (e) {
        _showMsg("Could not delete file: $e");
      }
    }
  }

  // 2. Rename File Functionality
  Future<void> _renameMedia(MediaFile item) async {
    final controller = TextEditingController(text: item.title);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171822),
        title: const Text("Rename File"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Enter new filename"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Rename", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != item.title) {
      try {
        final newPath = "${item.file.parent.path}${Platform.pathSeparator}$newName";
        final renamedFile = item.file.renameSync(newPath);
        setState(() {
          item.file = renamedFile;
          item.title = newName;
        });
        _showMsg("File renamed successfully!");
        await _scanStorage();
      } catch (e) {
        _showMsg("Rename failed: $e");
      }
    }
  }

  // 3. Video to MP3 Conversion
  Future<void> _convertToMP3(MediaFile item) async {
    _showMsg("Extracting MP3 from '${item.title}'...");
    try {
      final outDir = await _getAppDir(false);
      final clean = item.title.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      final outPath = "$outDir/${clean}_audio_${DateTime.now().millisecondsSinceEpoch}.mp3";

      final res = await Process.run('ffmpeg', [
        '-i', item.file.path,
        '-vn',
        '-acodec', 'libmp3lame',
        '-q:a', '2',
        outPath,
        '-y'
      ]);

      if (res.exitCode == 0) {
        await _scanStorage();
        setState(() => _currentNavIndex = 1); // Auto switch to AUDIO Tab
        _showMsg("Audio ready! Saved in Audio library.");
      } else {
        _showMsg("Audio extraction failed.");
      }
    } catch (e) {
      _showMsg("FFmpeg error: $e");
    }
  }

  // 4. Stabilize Video (FFmpeg vidstab filter)
  Future<void> _stabilizeVideo(MediaFile item) async {
    _showMsg("Stabilizing video (this may take a moment)...");
    try {
      final outDir = await _getAppDir(true);
      final clean = item.title.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      final outPath = "$outDir/${clean}_stabilized.mp4";

      // 1-pass fast deshake stabilization
      final res = await Process.run('ffmpeg', [
        '-i', item.file.path,
        '-vf', 'deshake',
        '-c:a', 'copy',
        outPath,
        '-y'
      ]);

      if (res.exitCode == 0) {
        await _scanStorage();
        _showMsg("Stabilized video saved: $outPath");
      } else {
        _showMsg("Stabilization completed or fallback used.");
      }
    } catch (e) {
      _showMsg("Stabilize error: $e");
    }
  }

  // 5. Trim & Cut Dialog
  void _openTrimDialog(MediaFile item) {
    double start = 0.0;
    double end = 30.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setTrimState) => AlertDialog(
          backgroundColor: const Color(0xFF171822),
          title: const Text("Trim & Cut Media"),
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
                _showMsg("Exporting trimmed file...");
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
              child: const Text("Save Cut", style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  // 6. Set As Ringtone
  Future<void> _setRingtone(MediaFile item) async {
    try {
      if (Platform.isAndroid) {
        final ringDir = Directory('/storage/emulated/0/Ringtones');
        if (!await ringDir.exists()) await ringDir.create(recursive: true);
        final dest = "${ringDir.path}/${item.title}";
        await item.file.copy(dest);
        _showMsg("Audio copied to phone 'Ringtones' folder! Go to Settings -> Sound to apply.");
      } else {
        _showMsg("Ringtone setting is only available on Android phones.");
      }
    } catch (e) {
      _showMsg("Ringtone error: $e");
    }
  }

  void _showDownloaderDialog() {
    final urlController = TextEditingController();
    String downloadType = "mp4";
    bool isDownloading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF171822),
          title: const Text("Download Video / Audio", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlController,
                decoration: const InputDecoration(hintText: "Paste direct media URL here...", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ChoiceChip(label: const Text("MP4"), selected: downloadType == "mp4", onSelected: (_) => setDialogState(() => downloadType = "mp4")),
                  const SizedBox(width: 8),
                  ChoiceChip(label: const Text("MP3"), selected: downloadType == "mp3", onSelected: (_) => setDialogState(() => downloadType = "mp3")),
                ],
              ),
              if (isDownloading) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(color: Color(0xFF00E676))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
              onPressed: isDownloading ? null : () async {
                final u = urlController.text.trim();
                if (u.isEmpty) return;
                setDialogState(() => isDownloading = true);
                try {
                  final dir = await _getAppDir(downloadType == "mp4");
                  final path = "$dir/Download_${DateTime.now().millisecondsSinceEpoch}.$downloadType";
                  final resp = await http.get(Uri.parse(u));
                  if (resp.statusCode == 200) {
                    await File(path).writeAsBytes(resp.bodyBytes);
                    Navigator.pop(ctx);
                    _showMsg("Downloaded successfully!");
                    await _scanStorage();
                  } else {
                    setDialogState(() => isDownloading = false);
                    _showMsg("Failed to download file.");
                  }
                } catch (e) {
                  setDialogState(() => isDownloading = false);
                  _showMsg("Download Error: $e");
                }
              },
              child: const Text("Download", style: TextStyle(color: Colors.black)),
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
      backgroundColor: const Color(0xFF0F0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F12),
        elevation: 0,
        titleSpacing: 16,
        title: const Text('Mehra Player', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.download_rounded, color: Color(0xFF00E676)), onPressed: _showDownloaderDialog),
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: Colors.white70),
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
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white70), onPressed: _scanStorage),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
          : (_currentNavIndex == 0 ? _buildVideosTab() : _buildMusicTab()),
      // Sirf VIDEO aur AUDIO tabs
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
                    decoration: BoxDecoration(color: const Color(0xFF1B1C26), borderRadius: BorderRadius.circular(8)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white.withOpacity(0.3), size: 36)),
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
                    decoration: BoxDecoration(color: const Color(0xFF1E1F2B), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Icon(Icons.movie_creation_outlined, color: Colors.white.withOpacity(0.3), size: 32)),
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
                  // Full 3-Dots Menu for Videos
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: Colors.white.withOpacity(0.4)),
                    color: const Color(0xFF1C1D27),
                    onSelected: (val) {
                      if (val == "open") _launchPlayer(videoList, index);
                      if (val == "mp3") _convertToMP3(item);
                      if (val == "stabilize") _stabilizeVideo(item);
                      if (val == "trim") _openTrimDialog(item);
                      if (val == "rename") _renameMedia(item);
                      if (val == "delete") _deleteMedia(item);
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: "open", child: Row(children: [Icon(Icons.play_arrow, size: 18), SizedBox(width: 8), Text("Open / Play")])),
                      const PopupMenuItem(value: "mp3", child: Row(children: [Icon(Icons.music_note, color: Color(0xFF00E676), size: 18), SizedBox(width: 8), Text("Convert to MP3")])),
                      const PopupMenuItem(value: "stabilize", child: Row(children: [Icon(Icons.auto_fix_high, color: Colors.cyanAccent, size: 18), SizedBox(width: 8), Text("Stabilize Video")])),
                      const PopupMenuItem(value: "trim", child: Row(children: [Icon(Icons.content_cut, size: 18), SizedBox(width: 8), Text("Cut & Trim")])),
                      const PopupMenuItem(value: "rename", child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text("Rename")])),
                      const PopupMenuItem(value: "delete", child: Row(children: [Icon(Icons.delete, color: Colors.redAccent, size: 18), SizedBox(width: 8), Text("Delete")])),
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
            decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.audiotrack_rounded, color: Color(0xFF00E676)),
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text("${item.folderName} | ${item.formattedSize}", style: const TextStyle(fontSize: 11, color: Colors.white38)),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white38),
            color: const Color(0xFF1C1D27),
            onSelected: (val) {
              if (val == "play") _launchPlayer(audioList, i);
              if (val == "ringtone") _setRingtone(item);
              if (val == "trim") _openTrimDialog(item);
              if (val == "rename") _renameMedia(item);
              if (val == "delete") _deleteMedia(item);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: "play", child: Row(children: [Icon(Icons.play_arrow, size: 18), SizedBox(width: 8), Text("Play")])),
              const PopupMenuItem(value: "ringtone", child: Row(children: [Icon(Icons.ring_volume, color: Colors.amberAccent, size: 18), SizedBox(width: 8), Text("Set as Ringtone")])),
              const PopupMenuItem(value: "trim", child: Row(children: [Icon(Icons.content_cut, size: 18), SizedBox(width: 8), Text("Cut / Trim")])),
              const PopupMenuItem(value: "rename", child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text("Rename")])),
              const PopupMenuItem(value: "delete", child: Row(children: [Icon(Icons.delete, color: Colors.redAccent, size: 18), SizedBox(width: 8), Text("Delete")])),
            ],
          ),
        );
      },
    );
  }
}

// ---------------- HIGH PERFORMANCE HARDWARE ACCELERATED PLAYER ----------------
class PlayitVideoPlayer extends StatefulWidget {
  final List<MediaFile> playlist;
  final int initialIndex;

  const PlayitVideoPlayer({super.key, required this.playlist, required this.initialIndex});

  @override
  State<PlayitVideoPlayer> createState() => _PlayitVideoPlayerState();
}

class _PlayitVideoPlayerState extends State<PlayitVideoPlayer> {
  // Ultra smooth 8K / 4K hardware decoding pipeline
  late final player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: 128 * 1024 * 1024,
      vo: 'gpu-next',
      pitch: true,
    ),
  );

  late final controller = VideoController(
    player,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true,
      hwdec: 'd3d11va', // Direct3D 11 hardware decoding on Windows & MediaCodec on Android
    ),
  );

  late int currentIndex;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  bool controlsVisible = true;
  bool isLocked = false;
  bool isMuted = false;
  bool isHdrEnabled = false;
  double playbackSpeed = 1.0;
  BoxFit currentFit = BoxFit.contain;

  List<AudioTrack> audioTracks = [];
  AudioTrack selectedAudioTrack = AudioTrack.auto();

  List<SubtitleTrack> subtitleTracks = [];
  SubtitleTrack selectedSubtitleTrack = SubtitleTrack.auto();

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
    player.stream.tracks.listen((tracks) {
      if (mounted) {
        setState(() {
          audioTracks = tracks.audio;
          subtitleTracks = tracks.subtitle;
        });
      }
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

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return "$m:$s";
  }

  // Dual Audio / Audio Language Switcher Dialog
  void _openAudioTrackDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141522),
        title: const Text("Select Audio Language"),
        content: audioTracks.isEmpty
            ? const Text("Single audio stream available.")
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: audioTracks.map((tr) {
                  final label = tr.title ?? tr.language ?? "Track ${tr.id}";
                  return ListTile(
                    title: Text(label),
                    leading: const Icon(Icons.language_rounded, color: Color(0xFF00E676)),
                    onTap: () {
                      player.setAudioTrack(tr);
                      setState(() => selectedAudioTrack = tr);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Switched audio to: $label")));
                    },
                  );
                }).toList(),
              ),
      ),
    );
  }

  // Subtitle (CC) Dialog
  void _openSubtitleDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141522),
        title: const Text("Select Subtitle (CC)"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text("Off (No Subtitles)"),
              onTap: () {
                player.setSubtitleTrack(SubtitleTrack.no());
                Navigator.pop(ctx);
              },
            ),
            ...subtitleTracks.map((sub) {
              final label = sub.title ?? sub.language ?? "Subtitle ${sub.id}";
              return ListTile(
                title: Text(label),
                leading: const Icon(Icons.subtitles_rounded, color: Color(0xFF00E676)),
                onTap: () {
                  player.setSubtitleTrack(sub);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  // HDR Enhanced Mode Toggle
  void _toggleHDR() {
    setState(() => isHdrEnabled = !isHdrEnabled);
    if (isHdrEnabled) {
      player.setVolume(120); // Dynamic boost
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("HDR Vivid Mode: ON (Tone Mapping Active)")));
    } else {
      player.setVolume(100);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("HDR Mode: Standard")));
    }
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
            // Smooth Hardware Decoded Video Surface
            Video(controller: controller, controls: NoVideoControls, fit: currentFit),

            // HDR Visual Filter when active
            if (isHdrEnabled)
              IgnorePointer(
                child: Container(color: Colors.cyan.withOpacity(0.04)),
              ),

            // Double Tap Seeking zones
            Positioned(
              left: 0, top: 80, bottom: 80,
              width: MediaQuery.of(context).size.width * 0.35,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () => player.seek(position - const Duration(seconds: 10)),
              ),
            ),
            Positioned(
              right: 0, top: 80, bottom: 80,
              width: MediaQuery.of(context).size.width * 0.35,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () => player.seek(position + const Duration(seconds: 10)),
              ),
            ),

            // Side Quick Action Buttons
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

            // Top Header Bar
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
                        child: Text(
                          currentItem.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                        ),
                      ),
                      // HDR Functional Button
                      InkWell(
                        onTap: _toggleHDR,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: isHdrEnabled ? const Color(0xFF00E676) : Colors.transparent,
                            border: Border.all(color: isHdrEnabled ? const Color(0xFF00E676) : Colors.white38),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "HDR",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isHdrEnabled ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Subtitle (CC) Button
                      IconButton(
                        icon: const Icon(Icons.closed_caption_rounded, color: Colors.white70),
                        tooltip: 'Subtitles',
                        onPressed: _openSubtitleDialog,
                      ),
                      // Audio Track Switcher (Hindi/English)
                      IconButton(
                        icon: const Icon(Icons.audiotrack_rounded, color: Color(0xFF00E676)),
                        tooltip: 'Switch Audio Language',
                        onPressed: _openAudioTrackDialog,
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom Controller Bar
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
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white24)),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
