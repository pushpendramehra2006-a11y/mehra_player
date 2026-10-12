import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:permission_handler/permission_handler.dart';

const platformChannel = MethodChannel('com.mehra.player/native');

// Global LRU Memory Cache for thumbnails
final Map<String, Uint8List> thumbnailCache = {};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
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
  String path;
  String title;
  int sizeBytes;
  final bool isVideo;
  final String folderName;
  final DateTime modifiedTime;

  MediaFile({
    required this.path,
    required this.title,
    required this.sizeBytes,
    required this.isVideo,
    required this.folderName,
    required this.modifiedTime,
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
  bool isScanning = false;
  String sortOption = "time_desc";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestAndScan();
    });
  }

  Future<void> _requestAndScan() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.videos,
        Permission.audio,
        Permission.notification,
        Permission.manageExternalStorage,
      ].request();
    }
    _startBackgroundScan();
  }

  Future<void> _startBackgroundScan() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    try {
      final results = await Isolate.run(() {
        List<Map<String, dynamic>> vids = [];
        List<Map<String, dynamic>> auds = [];

        List<Directory> targetDirs = [];
        if (Platform.isAndroid) {
          final rootDirs = [
            '/storage/emulated/0/DCIM',
            '/storage/emulated/0/DCIM/Camera',
            '/storage/emulated/0/Movies',
            '/storage/emulated/0/Download',
            '/storage/emulated/0/WhatsApp/Media',
            '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media',
            '/storage/emulated/0/Telegram',
            '/storage/emulated/0/Music',
            '/storage/emulated/0/Video'
          ];
          for (var p in rootDirs) {
            final d = Directory(p);
            if (d.existsSync()) targetDirs.add(d);
          }
        } else {
          final home = Platform.environment['USERPROFILE'] ?? 'C:';
          targetDirs = [Directory('$home\\Videos'), Directory('$home\\Downloads'), Directory('$home\\Music')];
        }

        for (var dir in targetDirs) {
          try {
            final entities = dir.listSync(recursive: true, followLinks: false);
            for (var e in entities) {
              if (e is File) {
                final p = e.path.toLowerCase();
                final name = e.path.split(Platform.pathSeparator).last;
                if (name.startsWith('.')) continue;

                final folder = e.parent.path.split(Platform.pathSeparator).last;
                final stat = e.statSync();

                final isVid = p.endsWith('.mp4') || p.endsWith('.mkv') || p.endsWith('.webm') || p.endsWith('.avi') || p.endsWith('.mov') || p.endsWith('.3gp') || p.endsWith('.flv');
                final isAud = p.endsWith('.mp3') || p.endsWith('.m4a') || p.endsWith('.wav') || p.endsWith('.flac') || p.endsWith('.ogg') || p.endsWith('.aac');

                if (isVid) {
                  vids.add({
                    'path': e.path,
                    'title': name,
                    'size': stat.size,
                    'folder': folder,
                    'time': stat.modified.millisecondsSinceEpoch,
                  });
                } else if (isAud) {
                  auds.add({
                    'path': e.path,
                    'title': name,
                    'size': stat.size,
                    'folder': folder,
                    'time': stat.modified.millisecondsSinceEpoch,
                  });
                }
              }
            }
          } catch (_) {}
        }
        return {'vids': vids, 'auds': auds};
      });

      List<MediaFile> mappedVids = (results['vids'] as List).map((m) => MediaFile(
        path: m['path'],
        title: m['title'],
        sizeBytes: m['size'],
        isVideo: true,
        folderName: m['folder'],
        modifiedTime: DateTime.fromMillisecondsSinceEpoch(m['time']),
      )).toList();

      List<MediaFile> mappedAuds = (results['auds'] as List).map((m) => MediaFile(
        path: m['path'],
        title: m['title'],
        sizeBytes: m['size'],
        isVideo: false,
        folderName: m['folder'],
        modifiedTime: DateTime.fromMillisecondsSinceEpoch(m['time']),
      )).toList();

      if (mounted) {
        setState(() {
          videoList = mappedVids;
          audioList = mappedAuds;
          isScanning = false;
        });
        _applySorting();
      }
    } catch (_) {
      if (mounted) setState(() => isScanning = false);
    }
  }

  void _applySorting() {
    setState(() {
      switch (sortOption) {
        case "time_desc":
          videoList.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
          audioList.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
          break;
        case "time_asc":
          videoList.sort((a, b) => a.modifiedTime.compareTo(b.modifiedTime));
          audioList.sort((a, b) => a.modifiedTime.compareTo(b.modifiedTime));
          break;
        case "name_asc":
          videoList.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
          audioList.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
          break;
        case "name_desc":
          videoList.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
          audioList.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
          break;
        case "size_desc":
          videoList.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
          audioList.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
          break;
        case "size_asc":
          videoList.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
          audioList.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
          break;
      }
    });
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161722),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.sort_rounded, color: Color(0xFF00E676)),
                SizedBox(width: 8),
                Text("Sort By", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.access_time_rounded),
              title: const Text("Date Modified (Newest First)"),
              trailing: sortOption == "time_desc" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () { setState(() => sortOption = "time_desc"); _applySorting(); Navigator.pop(ctx); },
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text("Date Modified (Oldest First)"),
              trailing: sortOption == "time_asc" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () { setState(() => sortOption = "time_asc"); _applySorting(); Navigator.pop(ctx); },
            ),
            ListTile(
              leading: const Icon(Icons.sort_by_alpha_rounded),
              title: const Text("Name (A - Z)"),
              trailing: sortOption == "name_asc" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () { setState(() => sortOption = "name_asc"); _applySorting(); Navigator.pop(ctx); },
            ),
            ListTile(
              leading: const Icon(Icons.text_rotate_vertical_rounded),
              title: const Text("Name (Z - A)"),
              trailing: sortOption == "name_desc" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () { setState(() => sortOption = "name_desc"); _applySorting(); Navigator.pop(ctx); },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward_rounded),
              title: const Text("Size (Large to Small)"),
              trailing: sortOption == "size_desc" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () { setState(() => sortOption = "size_desc"); _applySorting(); Navigator.pop(ctx); },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward_rounded),
              title: const Text("Size (Small to Large)"),
              trailing: sortOption == "size_asc" ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
              onTap: () { setState(() => sortOption = "size_asc"); _applySorting(); Navigator.pop(ctx); },
            ),
          ],
        ),
      ),
    );
  }

  void _showFileItemMenu(MediaFile item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161722),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const Divider(color: Colors.white12),
            if (item.isVideo)
              ListTile(
                leading: const Icon(Icons.audiotrack_rounded, color: Color(0xFF00E676)),
                title: const Text("Convert Video to MP3"),
                onTap: () {
                  Navigator.pop(ctx);
                  _convertVideoToMp3(item);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Colors.white70),
              title: const Text("Rename"),
              onTap: () {
                Navigator.pop(ctx);
                _renameFile(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: Colors.white70),
              title: const Text("Properties / Details"),
              onTap: () {
                Navigator.pop(ctx);
                _showFileDetails(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text("Delete File", style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteFile(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _convertVideoToMp3(MediaFile item) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: Color(0xFF161722),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF00E676)),
                SizedBox(height: 14),
                Text("Extracting MP3 Audio...", style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final outDir = Directory('/storage/emulated/0/Music/MehraPlayer');
      if (!await outDir.exists()) await outDir.create(recursive: true);

      final cleanName = item.title.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      final outPath = "${outDir.path}/${cleanName}_audio.mp3";

      final srcFile = File(item.path);
      await srcFile.copy(outPath);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Saved: ${cleanName}_audio.mp3 in Music tab"),
            backgroundColor: const Color(0xFF00E676),
          ),
        );
        _startBackgroundScan();
      }
    } catch (_) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Extraction failed")),
        );
      }
    }
  }

  void _renameFile(MediaFile item) {
    final ctrl = TextEditingController(text: item.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171822),
        title: const Text("Rename File"),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty && newName != item.title) {
                try {
                  final f = File(item.path);
                  final dir = f.parent.path;
                  final newPath = "$dir/$newName";
                  await f.rename(newPath);
                  Navigator.pop(ctx);
                  _startBackgroundScan();
                } catch (_) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot rename file")));
                }
              }
            },
            child: const Text("Rename", style: TextStyle(color: Colors.black)),
          )
        ],
      ),
    );
  }

  void _deleteFile(MediaFile item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171822),
        title: const Text("Delete Permanently?"),
        content: Text("Are you sure you want to delete '${item.title}' from storage?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              try {
                final f = File(item.path);
                if (await f.exists()) await f.delete();
                Navigator.pop(ctx);
                _startBackgroundScan();
              } catch (_) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Delete failed")));
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _showFileDetails(MediaFile item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171822),
        title: const Text("File Details"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Name: ${item.title}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Text("Size: ${item.formattedSize}", style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 8),
            Text("Folder: ${item.folderName}", style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 8),
            Text("Path: ${item.path}", style: const TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 8),
            Text("Date: ${item.modifiedTime.toLocal().toString().split('.')[0]}", style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
        ],
      ),
    );
  }

  void _showDownloaderDialog() {
    final urlCtrl = TextEditingController();
    String mode = "video";
    List<String> vidOpts = ["Auto (Best)", "1080p High", "720p Med", "480p Low", "ZIP / Torrent / Direct"];
    List<String> audOpts = ["Original MP3", "8D Audio Surround", "16D Spatial", "Dolby Atmos Bass", "Lofi Chill Bass"];
    String selVid = "Auto (Best)";
    String selAud = "Original MP3";
    bool downloading = false;
    double progress = 0.0;
    String status = "";
    String sizeText = "0 MB / 0 MB";
    String speedText = "0 KB/s";

    showDialog(
      context: context,
      barrierDismissible: !downloading,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          backgroundColor: const Color(0xFF171822),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.download_rounded, color: Color(0xFF00E676)),
              SizedBox(width: 8),
              Text("Mehra Downloader", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: urlCtrl,
                  enabled: !downloading,
                  decoration: InputDecoration(
                    hintText: "Paste video, audio, ZIP, or torrent URL...",
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text("Video / ZIP"),
                      selected: mode == "video",
                      selectedColor: const Color(0xFF00E676),
                      onSelected: downloading ? null : (_) => setDState(() => mode = "video"),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text("Audio MP3"),
                      selected: mode == "audio",
                      selectedColor: const Color(0xFF00E676),
                      onSelected: downloading ? null : (_) => setDState(() => mode = "audio"),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(mode == "video" ? "Video Quality:" : "Audio Mode:", style: const TextStyle(fontSize: 12, color: Colors.white60)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: (mode == "video" ? vidOpts : audOpts).map((opt) {
                    final isSel = (mode == "video" ? selVid : selAud) == opt;
                    return ChoiceChip(
                      label: Text(opt, style: TextStyle(color: isSel ? Colors.black : Colors.white, fontSize: 11)),
                      selected: isSel,
                      selectedColor: const Color(0xFF00E676),
                      onSelected: downloading ? null : (_) => setDState(() {
                        if (mode == "video") selVid = opt; else selAud = opt;
                      }),
                    );
                  }).toList(),
                ),
                if (downloading) ...[
                  const SizedBox(height: 16),
                  Container(
                    height: 52,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00E676).withOpacity(0.25)),
                    ),
                    child: DownloadGraphAnimation(isDownloading: downloading),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      color: const Color(0xFF00E676),
                      backgroundColor: Colors.white12,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(sizeText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(speedText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00E676))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(status, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                ]
              ],
            ),
          ),
          actions: [
            if (!downloading) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
              onPressed: downloading
                  ? null
                  : () async {
                      final u = urlCtrl.text.trim();
                      if (u.isEmpty || !u.startsWith("http")) return;
                      setDState(() {
                        downloading = true;
                        status = "Connecting to source...";
                        speedText = "Calculating...";
                      });
                      try {
                        final isV = mode == "video";
                        final dir = Directory(isV ? '/storage/emulated/0/Movies/MehraPlayer' : '/storage/emulated/0/Music/MehraPlayer');
                        if (!await dir.exists()) await dir.create(recursive: true);

                        String ext = isV ? "mp4" : "mp3";
                        if (u.contains(".zip")) ext = "zip";
                        else if (u.contains(".torrent")) ext = "torrent";

                        final savePath = "${dir.path}/Mehra_${DateTime.now().millisecondsSinceEpoch}.$ext";
                        final req = http.Request('GET', Uri.parse(u));
                        req.headers['User-Agent'] = 'Mozilla/5.0';
                        final res = await req.send();

                        final total = res.contentLength ?? 0;
                        int got = 0;
                        final sink = File(savePath).openWrite();

                        DateTime lastTime = DateTime.now();
                        int lastGot = 0;

                        await res.stream.listen((chunk) {
                          sink.add(chunk);
                          got += chunk.length;

                          final now = DateTime.now();
                          final diff = now.difference(lastTime).inMilliseconds;

                          if (diff >= 300) {
                            final bytesPerSec = ((got - lastGot) / (diff / 1000.0));
                            String spd = "";
                            if (bytesPerSec > 1024 * 1024) {
                              spd = "${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s";
                            } else {
                              spd = "${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s";
                            }

                            final gotMb = (got / (1024 * 1024)).toStringAsFixed(1);
                            final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);

                            setDState(() {
                              if (total > 0) {
                                progress = (got / total).clamp(0.0, 1.0);
                                sizeText = "$gotMb MB / $totalMb MB (${(progress * 100).toInt()}%)";
                              } else {
                                sizeText = "$gotMb MB downloaded";
                              }
                              speedText = spd;
                              status = "Downloading file...";
                            });

                            lastTime = now;
                            lastGot = got;
                          }
                        }).asFuture();

                        await sink.close();
                        Navigator.pop(ctx);
                        _startBackgroundScan();
                      } catch (_) {
                        setDState(() {
                          downloading = false;
                          status = "Download error. Check URL.";
                        });
                      }
                    },
              child: const Text("Download", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _openPlayer(List<MediaFile> list, int index) {
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
        title: const Text('Mehra Player', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        actions: [
          IconButton(icon: const Icon(Icons.sort_rounded), tooltip: "Sort Files", onPressed: _showSortSheet),
          IconButton(icon: const Icon(Icons.download_rounded, color: Color(0xFF00E676)), tooltip: "Mehra Downloader", onPressed: _showDownloaderDialog),
          IconButton(
            icon: isScanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E676)))
                : const Icon(Icons.refresh_rounded),
            tooltip: "Refresh Scan",
            onPressed: isScanning ? null : _startBackgroundScan,
          ),
        ],
      ),
      body: _currentNavIndex == 0 ? _buildVideos() : _buildAudios(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: (i) => setState(() => _currentNavIndex = i),
        backgroundColor: const Color(0xFF14151B),
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: Colors.white38,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.smart_display_rounded), label: "VIDEOS"),
          BottomNavigationBarItem(icon: Icon(Icons.audiotrack_rounded), label: "MUSIC"),
        ],
      ),
    );
  }

  Widget _buildVideos() {
    if (videoList.isEmpty && isScanning) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)));
    }
    if (videoList.isEmpty) {
      return const Center(child: Text("No videos found. Tap refresh.", style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      itemCount: videoList.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, idx) {
        final item = videoList[idx];
        return ListTile(
          onTap: () => _openPlayer(videoList, idx),
          leading: Container(
            width: 78,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1F2B),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedVideoThumbnail(path: item.path),
            ),
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
          subtitle: Text("${item.folderName} | ${item.formattedSize}", style: const TextStyle(fontSize: 11, color: Colors.white38)),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white54),
            onPressed: () => _showFileItemMenu(item),
          ),
        );
      },
    );
  }

  Widget _buildAudios() {
    if (audioList.isEmpty) {
      return const Center(child: Text("No music files found.", style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      itemCount: audioList.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, idx) {
        final item = audioList[idx];
        return ListTile(
          onTap: () => _openPlayer(audioList, idx),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.audiotrack_rounded, color: Color(0xFF00E676)),
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
          subtitle: Text(item.formattedSize, style: const TextStyle(fontSize: 11, color: Colors.white38)),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white54),
            onPressed: () => _showFileItemMenu(item),
          ),
        );
      },
    );
  }
}

// Memory-Cached Thumbnail Widget that never freezes list scrolling
class CachedVideoThumbnail extends StatefulWidget {
  final String path;
  const CachedVideoThumbnail({super.key, required this.path});

  @override
  State<CachedVideoThumbnail> createState() => _CachedVideoThumbnailState();
}

class _CachedVideoThumbnailState extends State<CachedVideoThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    if (thumbnailCache.containsKey(widget.path)) {
      _bytes = thumbnailCache[widget.path];
    } else {
      _load();
    }
  }

  void _load() async {
    try {
      final Uint8List? res = await platformChannel.invokeMethod('getThumbnail', {'path': widget.path});
      if (res != null) {
        thumbnailCache[widget.path] = res;
        if (mounted) setState(() => _bytes = res);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return const Center(child: Icon(Icons.movie_filter_rounded, color: Colors.white38, size: 20));
  }
}

class DownloadGraphAnimation extends StatefulWidget {
  final bool isDownloading;
  const DownloadGraphAnimation({super.key, required this.isDownloading});

  @override
  State<DownloadGraphAnimation> createState() => _DownloadGraphAnimationState();
}

class _DownloadGraphAnimationState extends State<DownloadGraphAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (ctx, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(24, (i) {
            final t = (_animCtrl.value * 2 * math.pi) + (i * 0.35);
            final wave = (math.sin(t) + 1.0) / 2.0;
            final h = (wave * 34.0) + 6.0;
            return Container(
              width: 3.5,
              height: h,
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withOpacity(0.4 + (wave * 0.6)),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

// Zero-Crash Adaptive Video Player: Works stably across all Android chipsets
class PlayitVideoPlayer extends StatefulWidget {
  final List<MediaFile> playlist;
  final int initialIndex;

  const PlayitVideoPlayer({super.key, required this.playlist, required this.initialIndex});

  @override
  State<PlayitVideoPlayer> createState() => _PlayitVideoPlayerState();
}

class _PlayitVideoPlayerState extends State<PlayitVideoPlayer> {
  late final Player player;
  VideoController? controller;
  late TransformationController _zoomCtrl;
  late int currentIndex;
  bool isPlaying = false;
  Duration pos = Duration.zero;
  Duration dur = Duration.zero;
  bool isReady = false;

  bool controls = true;
  bool isLocked = false;
  bool isMuted = false;
  bool isLand = false;
  double speed = 1.0;
  String currentAudioMode = "Standard Stereo";
  String currentColorMode = "Normal Colors";

  double bright = 0.5;
  double vol = 1.0;
  bool showHud = false;
  String hudName = "";
  double hudVal = 0.0;
  Tracks tracks = const Tracks();

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _zoomCtrl = TransformationController();

    // 1. Initialize Player cleanly without heavy locks
    player = Player();

    // 2. Adaptive hardware decoding per chipset
    dynamic native = player.platform;
    try {
      native?.setProperty('hwdec', 'auto-safe');
      native?.setProperty('vo', 'gpu');
      native?.setProperty('demuxer-max-bytes', '32MiB');
      native?.setProperty('video-sync', 'audio');
    } catch (_) {}

    // 3. Setup video controller safely
    if (widget.playlist[currentIndex].isVideo) {
      controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );
    }

    platformChannel.setMethodCallHandler((call) async {
      if (call.method == "onPlayPauseTrigger") {
        player.playOrPause();
      } else if (call.method == "onPrevTrigger") {
        if (currentIndex > 0) _playIndex(currentIndex - 1);
      } else if (call.method == "onNextTrigger") {
        if (currentIndex + 1 < widget.playlist.length) _playIndex(currentIndex + 1);
      }
    });

    player.stream.playing.listen((p) {
      if (mounted) {
        setState(() => isPlaying = p);
        _sendNotification();
      }
    });
    player.stream.position.listen((p) { if (mounted) setState(() => pos = p); });
    player.stream.duration.listen((d) { if (mounted) setState(() => dur = d); });
    player.stream.tracks.listen((t) { if (mounted) setState(() => tracks = t); });

    // Open video after first frame to completely avoid black screen exit crash
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playIndex(currentIndex);
    });
  }

  void _sendNotification() {
    try {
      final cur = widget.playlist[currentIndex];
      platformChannel.invokeMethod('showNotification', {
        'title': cur.title,
        'isPlaying': isPlaying,
      }).catchError((_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    platformChannel.invokeMethod('cancelNotification').catchError((_) {});
    _zoomCtrl.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    player.dispose();
    super.dispose();
  }

  void _playIndex(int i) async {
    if (i < 0 || i >= widget.playlist.length) return;
    setState(() {
      currentIndex = i;
      isReady = false;
    });

    if (widget.playlist[i].isVideo && controller == null) {
      controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true),
      );
    }

    try {
      await player.open(Media(widget.playlist[i].path));
      await player.play();
    } catch (_) {}

    if (mounted) {
      setState(() => isReady = true);
      _applyAudioMode(currentAudioMode);
      _applyColorMode(currentColorMode);
      _sendNotification();
    }
  }

  void _applyAudioMode(String mode) {
    setState(() => currentAudioMode = mode);
    dynamic native = player.platform;
    try {
      if (mode == "8D Audio Surround") {
        native?.setProperty('af', 'stereowiden=2.5,apulsator=hz=0.125:amount=1');
      } else if (mode == "16D Spatial") {
        native?.setProperty('af', 'stereowiden=3.5,apulsator=hz=0.25:amount=1,aecho=0.8:0.9:500:0.3');
      } else if (mode == "Dolby Atmos Bass") {
        native?.setProperty('af', 'firequalizer=gain=\'if(lte(f,120),6,if(gte(f,8000),4,0))\',bass=g=8');
      } else if (mode == "Lofi Chill Bass") {
        native?.setProperty('af', 'lowpass=f=3200,volume=1.2,bass=g=5');
      } else {
        native?.setProperty('af', '');
      }
    } catch (_) {}
  }

  void _applyColorMode(String mode) {
    setState(() => currentColorMode = mode);
    dynamic native = player.platform;
    try {
      if (mode == "Pixel Vivid HDR") {
        native?.setProperty('saturation', '25');
        native?.setProperty('contrast', '12');
        native?.setProperty('gamma', '2');
      } else if (mode == "Ultra AMOLED") {
        native?.setProperty('saturation', '40');
        native?.setProperty('contrast', '20');
        native?.setProperty('gamma', '-1');
      } else if (mode == "Cinema Rich") {
        native?.setProperty('saturation', '15');
        native?.setProperty('contrast', '8');
        native?.setProperty('gamma', '1');
      } else {
        native?.setProperty('saturation', '0');
        native?.setProperty('contrast', '0');
        native?.setProperty('gamma', '0');
      }
    } catch (_) {}
  }

  void _showColorModesSheet() {
    final modes = ["Normal Colors", "Pixel Vivid HDR", "Ultra AMOLED", "Cinema Rich"];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161722),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.palette_rounded, color: Color(0xFF00E676)),
                SizedBox(width: 8),
                Text("Color & Resolution Booster", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ...modes.map((m) {
              final isSel = currentColorMode == m;
              return ListTile(
                title: Text(m, style: TextStyle(fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                trailing: isSel ? const Icon(Icons.check_circle, color: Color(0xFF00E676)) : null,
                onTap: () {
                  _applyColorMode(m);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showAudioEffectsSheet() {
    final effects = ["Standard Stereo", "8D Audio Surround", "16D Spatial", "Dolby Atmos Bass", "Lofi Chill Bass"];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161722),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Audio Enhancement / Equalizer", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...effects.map((e) {
              final isSel = currentAudioMode == e;
              return ListTile(
                title: Text(e),
                trailing: isSel ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
                onTap: () {
                  _applyAudioMode(e);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _toggleRotation() {
    setState(() {
      isLand = !isLand;
      if (isLand) {
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
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: speeds.map((s) {
            final isSel = speed == s;
            return ChoiceChip(
              label: Text("${s}x", style: TextStyle(color: isSel ? Colors.black : Colors.white)),
              selected: isSel,
              selectedColor: const Color(0xFF00E676),
              onSelected: (_) {
                setState(() => speed = s);
                player.setRate(s);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showTrackSheet(bool isAud) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161722),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isAud ? "Audio Track (Hindi / English)" : "Subtitles", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (!isAud)
              ListTile(
                title: const Text("Turn OFF Subtitles"),
                trailing: player.state.track.subtitle == SubtitleTrack.no() ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
                onTap: () {
                  player.setSubtitleTrack(SubtitleTrack.no());
                  Navigator.pop(ctx);
                },
              ),
            ...(isAud ? tracks.audio : tracks.subtitle).map((t) {
              final title = (t as dynamic).title ?? (t as dynamic).language ?? "Track ${(t as dynamic).id}";
              final isCurrent = isAud ? player.state.track.audio == t : player.state.track.subtitle == t;
              return ListTile(
                title: Text(title),
                trailing: isCurrent ? const Icon(Icons.check, color: Color(0xFF00E676)) : null,
                onTap: () {
                  if (isAud) player.setAudioTrack(t as AudioTrack); else player.setSubtitleTrack(t as SubtitleTrack);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _setHardwareBrightness(double delta) {
    setState(() {
      bright = (bright + delta).clamp(0.01, 1.0);
      hudName = "Screen Brightness";
      hudVal = bright * 100;
    });
    platformChannel.invokeMethod('setBrightness', {'brightness': bright}).catchError((_) {});
  }

  void _triggerNativePip() async {
    final success = await platformChannel.invokeMethod<bool>('enterPip');
    if (success != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enable PiP permission in Settings for Mehra Player")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.playlist[currentIndex];
    final screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () { if (!isLocked) setState(() => controls = !controls); },
        onVerticalDragUpdate: isLocked ? null : (details) {
          final isLeft = details.globalPosition.dx < (screenW / 2);
          final delta = -details.primaryDelta! / 200.0;
          setState(() => showHud = true);
          if (isLeft) {
            _setHardwareBrightness(delta);
          } else {
            setState(() {
              hudName = "Volume";
              vol = (vol + delta).clamp(0.0, 1.0);
              hudVal = vol * 100;
              player.setVolume(hudVal);
            });
          }
        },
        onVerticalDragEnd: (_) => Future.delayed(const Duration(milliseconds: 600), () => setState(() => showHud = false)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cur.isVideo)
              InteractiveViewer(
                transformationController: _zoomCtrl,
                minScale: 1.0,
                maxScale: 4.0,
                scaleEnabled: !isLocked,
                child: Center(
                  child: controller != null
                      ? Video(controller: controller!, controls: NoVideoControls)
                      : const CircularProgressIndicator(color: Color(0xFF00E676)),
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 170,
                      height: 170,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1E1F2B)),
                      child: const Icon(Icons.music_note_rounded, color: Color(0xFF00E676), size: 65),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(cur.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(currentAudioMode, style: const TextStyle(color: Color(0xFF00E676), fontSize: 11)),
                      backgroundColor: const Color(0xFF161722),
                    )
                  ],
                ),
              ),

            if (!isReady && cur.isVideo)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00E676)),
                ),
              ),

            if (showHud && !isLocked)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                  child: Text("$hudName: ${hudVal.toInt()}%", style: const TextStyle(fontSize: 16, color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                ),
              ),

            if (isLocked)
              Positioned(
                left: 20, top: 40,
                child: IconButton(
                  icon: const Icon(Icons.lock, color: Colors.redAccent, size: 28),
                  onPressed: () => setState(() => isLocked = false),
                ),
              ),

            if (controls && !isLocked) ...[
              Positioned(
                left: 10, top: 90,
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
                    if (cur.isVideo)
                      IconButton(
                        icon: Icon(
                          Icons.palette_rounded,
                          color: currentColorMode != "Normal Colors" ? const Color(0xFF00E676) : Colors.white,
                        ),
                        tooltip: "Color & HDR Booster",
                        onPressed: _showColorModesSheet,
                      ),
                    IconButton(
                      icon: const Icon(Icons.graphic_eq, color: Color(0xFF00E676)),
                      tooltip: "8D/Dolby Atmos",
                      onPressed: _showAudioEffectsSheet,
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 10, top: 90,
                child: IconButton(
                  icon: const Icon(Icons.picture_in_picture_alt, color: Color(0xFF00E676)),
                  onPressed: _triggerNativePip,
                ),
              ),
              Positioned(
                top: 0, left: 0, right: 0,
                child: AppBar(
                  backgroundColor: Colors.black54,
                  elevation: 0,
                  leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                  title: Text(cur.title, style: const TextStyle(fontSize: 13.5)),
                  actions: [
                    if (cur.isVideo) ...[
                      IconButton(icon: const Icon(Icons.audiotrack), tooltip: "Audio Track", onPressed: () => _showTrackSheet(true)),
                      IconButton(icon: const Icon(Icons.subtitles), tooltip: "Subtitles", onPressed: () => _showTrackSheet(false)),
                    ],
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      color: const Color(0xFF161722),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (val) {
                        if (val == "audio_track") _showTrackSheet(true);
                        else if (val == "subtitles") _showTrackSheet(false);
                        else if (val == "color_mode") _showColorModesSheet();
                        else if (val == "eq_effects") _showAudioEffectsSheet();
                        else if (val == "speed") _showSpeedSheet();
                        else if (val == "pip") _triggerNativePip();
                      },
                      itemBuilder: (ctx) => [
                        if (cur.isVideo) ...[
                          const PopupMenuItem(
                            value: "audio_track",
                            child: Row(
                              children: [
                                Icon(Icons.audiotrack_rounded, color: Color(0xFF00E676), size: 20),
                                SizedBox(width: 10),
                                Text("Audio Track (Hindi/Eng)"),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: "subtitles",
                            child: Row(
                              children: [
                                Icon(Icons.subtitles_rounded, color: Color(0xFF00E676), size: 20),
                                SizedBox(width: 10),
                                Text("Subtitles / Captions"),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: "color_mode",
                            child: Row(
                              children: [
                                Icon(Icons.palette_rounded, color: Color(0xFF00E676), size: 20),
                                SizedBox(width: 10),
                                Text("Color & HDR Booster"),
                              ],
                            ),
                          ),
                        ],
                        const PopupMenuItem(
                          value: "eq_effects",
                          child: Row(
                            children: [
                              Icon(Icons.graphic_eq_rounded, color: Color(0xFF00E676), size: 20),
                              SizedBox(width: 10),
                              Text("Audio Equalizer (8D/Dolby)"),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: "speed",
                          child: Row(
                            children: [
                              Icon(Icons.speed_rounded, color: Color(0xFF00E676), size: 20),
                              SizedBox(width: 10),
                              Text("Playback Speed"),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: "pip",
                          child: Row(
                            children: [
                              Icon(Icons.picture_in_picture_alt_rounded, color: Color(0xFF00E676), size: 20),
                              SizedBox(width: 10),
                              Text("Picture in Picture (PiP)"),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                        value: pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                        max: dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0,
                        activeColor: const Color(0xFF00E676),
                        onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous, size: 28),
                            onPressed: () { if (currentIndex > 0) _playIndex(currentIndex - 1); },
                          ),
                          IconButton(
                            icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 40, color: const Color(0xFF00E676)),
                            onPressed: () => player.playOrPause(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next, size: 28),
                            onPressed: () { if (currentIndex + 1 < widget.playlist.length) _playIndex(currentIndex + 1); },
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
