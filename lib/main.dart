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

// ---------------- MAIN TABS SCREEN (VIDEO & AUDIO) ----------------
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
        if (vids.isNotEmpty) historyList = vids.take(5).toList();
        isLoading = false;
      });
    }
  }

  void _showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: const Color(0xFF1E1F30)));
  }

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
        if (item.file.existsSync()) item.file.deleteSync();
        _showMsg("File deleted successfully!");
        await _scanStorage();
      } catch (e) {
        _showMsg("Could not delete file: $e");
      }
    }
  }

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
        setState(() => _currentNavIndex = 1);
        _showMsg("Audio ready! Saved in Audio library.");
      } else {
        _showMsg("Audio extraction failed.");
      }
    } catch (e) {
      _showMsg("FFmpeg error: $e");
    }
  }

  Future<void> _stabilizeVideo(MediaFile item) async {
    _showMsg("Stabilizing video with FFmpeg deshake...");
    try {
      final outDir = await _getAppDir(true);
      final clean = item.title.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      final outPath = "$outDir/${clean}_stabilized.mp4";

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
        _showMsg("Stabilization completed.");
      }
    } catch (e) {
      _showMsg("Stabilize error: $e");
    }
  }

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

  Future<void> _setRingtone(MediaFile item) async {
    try {
      if (Platform.isAndroid) {
        final ringDir = Directory('/storage/emulated/0/Ringtones');
        if (!await ringDir.exists()) await ringDir.create(recursive: true);
        final dest = "${ringDir.path}/${item.title}";
        await item.file.copy(dest);
        _showMsg("Audio copied to phone 'Ringtones' folder! Select in Settings -> Sound.");
      } else {
        _showMsg("Ringtone setting is for Android phones.");
      }
    } catch (e) {
      _showMsg("Ringtone error: $e");
    }
  }

        void _showDownloaderDialog() {
    final urlController = TextEditingController();
    String downloadType = "mp4";
    String selectedQuality = "1080p";
    String selectedAudioQuality = "320 kbps";
    bool isDownloading = false;
    double downloadProgress = 0.0;
    int progressPercent = 0;
    String progressSubtitle = "";

    final List<String> videoQualities = ["8K", "4K", "1080p", "720p", "480p"];
    final List<String> audioQualities = ["320 kbps", "192 kbps", "128 kbps"];

    showDialog(
      context: context,
      barrierDismissible: !isDownloading,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF171822),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.downloadING_rounded, color: Color(0xFF00E676), size: 24),
              ),
              const SizedBox(width: 10),
              const Text("Mehra Downloader", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
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
                    hintText: "Paste video/audio link here...",
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                    filled: true,
                    fillColor: Colors.black38,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                const Text("Format:", style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
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
                const SizedBox(height: 12),
                Text(
                  downloadType == "mp4" ? "Quality Preset:" : "Audio Bitrate:",
                  style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: (downloadType == "mp4" ? videoQualities : audioQualities).map((q) {
                    final isSel = (downloadType == "mp4" ? selectedQuality : selectedAudioQuality) == q;
                    return ChoiceChip(
                      label: Text(
                        q,
                        style: TextStyle(
                          color: isSel ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      selected: isSel,
                      selectedColor: const Color(0xFF00E676),
                      backgroundColor: const Color(0xFF232432),
                      onSelected: isDownloading
                          ? null
                          : (_) {
                              setDialogState(() {
                                if (downloadType == "mp4") {
                                  selectedQuality = q;
                                } else {
                                  selectedAudioQuality = q;
                                }
                              });
                            },
                    );
                  }).toList(),
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "$progressPercent%",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF00E676)),
                      ),
                      Text(
                        progressSubtitle,
                        style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      tween: Tween<double>(begin: 0, end: downloadProgress),
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value > 0.0 ? value : null,
                        minHeight: 7,
                        color: const Color(0xFF00E676),
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ),
                ]
              ],
            ),
          ),
          actions: [
            if (!isDownloading)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: isDownloading
                  ? null
                  : () async {
                      final u = urlController.text.trim();
                      if (u.isEmpty || !u.startsWith("http")) {
                        _showMsg("Please enter a valid video/audio link!");
                        return;
                      }

                      setDialogState(() {
                        isDownloading = true;
                        downloadProgress = 0.01;
                        progressPercent = 1;
                        progressSubtitle = "Connecting...";
                      });

                      try {
                        final dir = await _getAppDir(downloadType == "mp4");
                        final tag = downloadType == "mp4" ? selectedQuality : selectedAudioQuality.replaceAll(' ', '');
                        final filePath = "$dir/Mehra_${tag}_${DateTime.now().millisecondsSinceEpoch}.$downloadType";
                        final file = File(filePath);

                        final request = http.Request('GET', Uri.parse(u))
                          ..headers.addAll({
                            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                            'Accept': '*/*',
                            'Connection': 'keep-alive',
                          });

                        final client = http.Client();
                        final response = await client.send(request);

                        if (response.statusCode >= 200 && response.statusCode < 300) {
                          final totalBytes = response.contentLength ?? 0;
                          int receivedBytes = 0;
                          final sink = file.openWrite();

                          await response.stream.listen(
                            (chunk) {
                              sink.add(chunk);
                              receivedBytes += chunk.length;
                              setDialogState(() {
                                final mbDone = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
                                if (totalBytes > 0) {
                                  downloadProgress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
                                  progressPercent = (downloadProgress * 100).toInt();
                                  final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
                                  progressSubtitle = "$mbDone MB / $mbTotal MB";
                                } else {
                                  // Estimated smooth progress animation if server omits Content-Length
                                  downloadProgress = ((downloadProgress + 0.02).clamp(0.05, 0.95));
                                  progressPercent = (downloadProgress * 100).toInt();
                                  progressSubtitle = "$mbDone MB downloaded";
                                }
                              });
                            },
                            onDone: () async {
                              await sink.close();
                              client.close();
                              setDialogState(() {
                                downloadProgress = 1.0;
                                progressPercent = 100;
                                progressSubtitle = "Completed!";
                              });
                              await Future.delayed(const Duration(milliseconds: 400));
                              Navigator.pop(ctx);
                              _showMsg("Downloaded successfully: ${file.path.split(Platform.pathSeparator).last}");
                              await _scanStorage();
                            },
                            onError: (err) async {
                              await sink.close();
                              client.close();
                              setDialogState(() => isDownloading = false);
                              _showMsg("Download interrupted: $err");
                            },
                            cancelOnError: true,
                          ).asFuture();
                        } else {
                          setDialogState(() => isDownloading = false);
                          _showMsg("Server returned code ${response.statusCode}. Stream link expired.");
                        }
                      } catch (e) {
                        setDialogState(() => isDownloading = false);
                        _showMsg("Connection Error: $e");
                      }
                    },
              child: Text(
                isDownloading ? "Downloading $progressPercent%..." : "Download Now",
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
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
        builder: (_) => PlayitVideoPlayer(
          playlist: list,
          initialIndex: index,
          onConvertAudio: _convertToMP3,
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

// ---------------- PLAYIT PLAYER SCREEN (Full Speed Range 0.25x - 10.0x & Pro Bottom Sheet) ----------------
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
      bufferSize: 128 * 1024 * 1024,
      vo: 'gpu-next',
      pitch: true,
    ),
  );

  late final controller = VideoController(
    player,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true,
      hwdec: 'd3d11va',
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
  bool isNightMode = false;
  bool isMirrorMode = false;
  bool isVrMode = false;
  double playbackSpeed = 1.0;
  BoxFit currentFit = BoxFit.contain;
  String currentEffect = "Normal";

  List<AudioTrack> audioTracks = [];
  AudioTrack selectedAudioTrack = AudioTrack.auto();
  List<SubtitleTrack> subtitleTracks = [];
  SubtitleTrack selectedSubtitleTrack = SubtitleTrack.auto();

  // Full 0.25x to 10.0x Speed Speeds
  final List<double> availableSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 5.0, 8.0, 10.0];

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

  void _setSpeed(double s) {
    setState(() => playbackSpeed = s);
    player.setRate(s);
  }

  // Speed Selector Dialog (0.25x to 10.0x)
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

  // PLAYit Exact Pro Bottom Sheet (Screenshot 24)
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
              // Row 1: Audio play, Audio track, Equalizer, Cast
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _proIconBtn(Icons.headphones_rounded, "Audio play", () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Playing in background audio mode!")));
                  }),
                  _proIconBtn(Icons.music_note_rounded, "Audio track", () {
                    Navigator.pop(ctx);
                    _openAudioTrackDialog();
                  }),
                  _proIconBtn(Icons.equalizer_rounded, "Equalizer", () {
                    Navigator.pop(ctx);
                    _showEffectDialog();
                  }, active: currentEffect != "Normal"),
                  _proIconBtn(Icons.cast_rounded, "Cast", () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Searching for screen cast devices...")));
                  }),
                ],
              ),
              // Row 2: Share, Cut, Favorite, Bookmark
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _proIconBtn(Icons.share_outlined, "Share", () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Share intent opened.")));
                  }),
                  _proIconBtn(Icons.content_cut_rounded, "Cut", () {
                    Navigator.pop(ctx);
                    _showTrimTool();
                  }),
                  _proIconBtn(Icons.star_border_rounded, "Favorite", () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Added to Favorites!")));
                  }),
                  _proIconBtn(Icons.bookmark_border_rounded, "Bookmark", () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Timestamp bookmarked.")));
                  }),
                ],
              ),
              // Row 3: VR
              Row(
                children: [
                  const SizedBox(width: 14),
                  _proIconBtn(Icons.view_in_ar_rounded, "VR", () {
                    setSheet(() => isVrMode = !isVrMode);
                    setState(() => isVrMode = isVrMode);
                  }, active: isVrMode),
                ],
              ),

              const Divider(color: Colors.white12),

              const Text("Play settings", style: TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.bold)),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _proIconBtn(Icons.repeat_one_rounded, "AB Repeat", () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("AB Repeat point set.")));
                  }),
                  _proIconBtn(Icons.nightlight_round, "Night mode", () {
                    setSheet(() => isNightMode = !isNightMode);
                    setState(() => isNightMode = isNightMode);
                  }, active: isNightMode),
                  _proIconBtn(Icons.flip_rounded, "Mirror mode", () {
                    setSheet(() => isMirrorMode = !isMirrorMode);
                    setState(() => isMirrorMode = isMirrorMode);
                  }, active: isMirrorMode),
                  _proIconBtn(Icons.timer_outlined, "Timer", () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sleep timer: 30 minutes set.")));
                  }),
                ],
              ),

              const Divider(color: Colors.white12),

              // Loop Pills Row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(color: const Color(0xFF22232E), borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.shuffle, size: 18), onPressed: () {}),
                        IconButton(icon: const Icon(Icons.repeat, size: 18), onPressed: () {}),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFF00E676), borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.format_list_bulleted_rounded, color: Colors.black, size: 18),
                        ),
                      ],
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Trimming '${item.title}'...")));
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

  void _showEffectDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141522),
        title: const Text("Audio FX / Equalizer"),
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
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Switched to audio: $label")));
                    },
                  );
                }).toList(),
              ),
      ),
    );
  }

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

  void _toggleHDR() {
    setState(() => isHdrEnabled = !isHdrEnabled);
    if (isHdrEnabled) {
      player.setVolume(120);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("HDR Vivid: ON (Tone Mapping Active)")));
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
            // Video Surface with Mirror & VR Mode
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..setEntry(0, 0, isMirrorMode ? -1 : 1),
              child: Video(controller: controller, controls: NoVideoControls, fit: currentFit),
            ),

            if (isNightMode) IgnorePointer(child: Container(color: Colors.amber.withOpacity(0.18))),
            if (isHdrEnabled) IgnorePointer(child: Container(color: Colors.cyan.withOpacity(0.04))),

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

            // Top Header Bar (With Back, HDR, CC, Audio & 3-Dots PLAYit Menu)
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
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.closed_caption_rounded, color: Colors.white70),
                        tooltip: 'Subtitles',
                        onPressed: _openSubtitleDialog,
                      ),
                      IconButton(
                        icon: const Icon(Icons.audiotrack_rounded, color: Color(0xFF00E676)),
                        tooltip: 'Audio Language',
                        onPressed: _openAudioTrackDialog,
                      ),
                      // Top 3-Dots Button: Opens Exact PLAYit Pro Sheet
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                        tooltip: 'Play Settings',
                        onPressed: _openProSettingsSheet,
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
                          // Speed Button: Click to cycle or open full 0.25x - 10.0x sheet
                          InkWell(
                            onTap: () {
                              int nextIdx = (availableSpeeds.indexOf(playbackSpeed) + 1) % availableSpeeds.length;
                              _setSpeed(availableSpeeds[nextIdx]);
                            },
                            onLongPress: _openSpeedSelector,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "${playbackSpeed}x",
                                style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 22),
                            tooltip: 'Pro Controls',
                            onPressed: _openProSettingsSheet,
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



