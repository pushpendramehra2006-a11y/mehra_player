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
      title: 'Mehra Player Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF09090C),
        primaryColor: Colors.deepPurpleAccent,
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

  late AnimationController visualizerController;

  List<FileSystemEntity> videoList = [];
  List<FileSystemEntity> audioList = [];
  int currentIndex = -1;
  bool isAudioMode = false;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  // Features State
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

  @override
  void initState() {
    super.initState();
    visualizerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
    visualizerController.dispose();
    player.dispose();
    super.dispose();
  }

  void showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<String> getOutputDir() async {
    final home = Platform.isWindows ? (Platform.environment['USERPROFILE'] ?? 'C:') : '/storage/emulated/0/Download';
    final dir = Directory('$home/MehraPlayer');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
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
    int next = currentIndex + 1;
    if (isShuffle) {
      next = (next * 7) % list.length;
    } else if (next >= list.length) {
      next = 0;
    }
    playMedia(next, isAudioMode);
  }

  void prevTrack() {
    final list = isAudioMode ? audioList : videoList;
    if (list.isEmpty) return;
    int prev = currentIndex - 1;
    if (prev < 0) prev = list.length - 1;
    playMedia(prev, isAudioMode);
  }

  void toggleDolby() {
    setState(() => dolbyAtmos = !dolbyAtmos);
    player.setVolume(dolbyAtmos ? 125.0 : 100.0);
    showMsg(dolbyAtmos ? "Dolby Atmos 3D Boost: ON" : "Dolby Atmos: OFF");
  }

  void cycleAspectRatio() {
    setState(() {
      if (currentFit == BoxFit.contain) {
        currentFit = BoxFit.cover;
        fitLabel = "Zoom";
      } else if (currentFit == BoxFit.cover) {
        currentFit = BoxFit.fill;
        fitLabel = "Fill Screen";
      } else {
        currentFit = BoxFit.contain;
        fitLabel = "Fit";
      }
    });
    showMsg("Aspect Ratio: $fitLabel");
  }

  void openSubtitleMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1B22),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.subtitles, color: Colors.deepPurpleAccent),
              title: Text('Subtitle Toggle (${showSubtitles ? "ON" : "OFF"})'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => showSubtitles = !showSubtitles);
                player.setSubtitleTrack(showSubtitles ? SubtitleTrack.auto() : SubtitleTrack.no());
                showMsg(showSubtitles ? "Subtitles ON" : "Subtitles OFF");
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder, color: Colors.cyanAccent),
              title: const Text('Add Local .SRT / .VTT Subtitle'),
              onTap: () async {
                Navigator.pop(ctx);
                final res = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['srt', 'vtt', 'ass'],
                );
                if (res != null && res.files.single.path != null) {
                  await player.setSubtitleTrack(SubtitleTrack.uri(res.files.single.path!));
                  showMsg("Subtitle Loaded: ${res.files.single.name}");
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void openDownloadDialog() {
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download Video / Audio (yt-dlp)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: urlCtrl, decoration: const InputDecoration(hintText: 'Paste YouTube / Media Link')),
            const SizedBox(height: 14),
            const Text("Choose Quality to Download:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(label: const Text('1080p MP4'), onPressed: () => startDownload(urlCtrl.text.trim(), '1080', false, ctx)),
                ActionChip(label: const Text('720p MP4'), onPressed: () => startDownload(urlCtrl.text.trim(), '720', false, ctx)),
                ActionChip(label: const Text('Best MP4'), onPressed: () => startDownload(urlCtrl.text.trim(), 'best', false, ctx)),
                ActionChip(label: const Text('MP3 320k'), onPressed: () => startDownload(urlCtrl.text.trim(), 'best', true, ctx)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> startDownload(String url, String quality, bool isAudio, BuildContext ctx) async {
    Navigator.pop(ctx);
    if (url.isEmpty) return;
    final outDir = await getOutputDir();
    final filename = 'dl_${DateTime.now().millisecondsSinceEpoch}.${isAudio ? "mp3" : "mp4"}';
    final outPath = Platform.isWindows ? '$outDir\\$filename' : '$outDir/$filename';
    showMsg("Downloading shuru hui...");

    List<String> args = isAudio
        ? ['-x', '--audio-format', 'mp3', '-o', outPath, url]
        : ['-f', quality == 'best' ? 'bestvideo+bestaudio/best' : 'bestvideo[height<=$quality]+bestaudio/best', '-o', outPath, url];

    final res = await Process.run('yt-dlp', args);
    if (res.exitCode == 0) {
      showMsg("Downloaded! Library me add ho gaya.");
      await scanAllMediaFiles();
      if (!isAudio) {
        videoList.insert(0, File(outPath));
        playMedia(0, false);
      } else {
        audioList.insert(0, File(outPath));
        playMedia(0, true);
      }
    } else {
      showMsg("Download Error: URL check karein.");
    }
  }

  void openTrimDialog() {
    final activeList = isAudioMode ? audioList : videoList;
    final currentFile = (currentIndex >= 0 && currentIndex < activeList.length) ? activeList[currentIndex] : null;
    if (currentFile == null || duration.inSeconds <= 0) return;

    double startVal = 0.0;
    double endVal = duration.inSeconds.toDouble().clamp(0.0, 30.0);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Exact Cut / Trim Video'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Start: ${formatTime(Duration(seconds: startVal.toInt()))}  |  End: ${formatTime(Duration(seconds: endVal.toInt()))}"),
              RangeSlider(
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
              onPressed: () async {
                Navigator.pop(ctx);
                final outDir = await getOutputDir();
                final filename = 'clip_${DateTime.now().millisecondsSinceEpoch}.mp4';
                final outPath = Platform.isWindows ? '$outDir\\$filename' : '$outDir/$filename';
                showMsg("Cutting clip... Please wait");
                final res = await Process.run('ffmpeg', [
                  '-ss', '${startVal.toInt()}',
                  '-i', currentFile.path,
                  '-t', '${(endVal - startVal).toInt()}',
                  '-c', 'copy',
                  outPath,
                  '-y'
                ]);
                if (res.exitCode == 0) {
                  showMsg("Cut Clip Saved: $outPath");
                  await scanAllMediaFiles();
                } else {
                  showMsg("Cut failed: FFmpeg check karein");
                }
              },
              child: const Text('Export Cut Clip'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> extractMp3() async {
    final activeList = isAudioMode ? audioList : videoList;
    final currentFile = (currentIndex >= 0 && currentIndex < activeList.length) ? activeList[currentIndex] : null;
    if (currentFile == null) return;
    final outDir = await getOutputDir();
    final filename = 'audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final outPath = Platform.isWindows ? '$outDir\\$filename' : '$outDir/$filename';
    showMsg("Video se MP3 nikal raha hai...");

    final res = await Process.run('ffmpeg', [
      '-i', currentFile.path,
      '-vn',
      '-acodec', 'libmp3lame',
      '-q:a', '2',
      outPath,
      '-y'
    ]);
    if (res.exitCode == 0) {
      showMsg("MP3 Audio Saved: $outPath");
      await scanAllMediaFiles();
    } else {
      showMsg("MP3 conversion failed");
    }
  }

  Future<void> takeScreenshot() async {
    final activeList = isAudioMode ? audioList : videoList;
    final currentFile = (currentIndex >= 0 && currentIndex < activeList.length) ? activeList[currentIndex] : null;
    if (currentFile == null) return;
    final outDir = await getOutputDir();
    final filename = 'screenshot_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outPath = Platform.isWindows ? '$outDir\\$filename' : '$outDir/$filename';
    showMsg("Screenshot save ho raha hai...");

    final res = await Process.run('ffmpeg', [
      '-ss', '${position.inSeconds}',
      '-i', currentFile.path,
      '-vframes', '1',
      '-q:v', '2',
      outPath,
      '-y'
    ]);
    if (res.exitCode == 0) {
      showMsg("Screenshot Saved in MehraPlayer");
    }
  }

  String formatTime(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  Widget _buildPlayerContent(FileSystemEntity? currentFile, String currentTitle) {
    if (currentFile == null) {
      return const Center(
        child: Text("Neeche Library se Video ya Song play karein", style: TextStyle(color: Colors.white54, fontSize: 16)),
      );
    }

    if (isAudioMode) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [Colors.deepPurple.withOpacity(0.45), Colors.black],
            radius: 1.1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: visualizerController,
              builder: (context, child) {
                double scale = isPlaying ? 1.0 + (visualizerController.value * 0.08) : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1E1E28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepPurpleAccent.withOpacity(0.6),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                      border: Border.all(color: Colors.white24, width: 3),
                    ),
                    child: const Center(
                      child: Icon(Icons.music_note, size: 70, color: Colors.cyanAccent),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                currentTitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dolbyAtmos ? "Dolby Audio 3D Surround Enabled" : "High-Fidelity Audio Mode",
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (ambientLight)
          Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.deepPurpleAccent.withOpacity(0.45),
                  blurRadius: 70,
                  spreadRadius: 30,
                ),
              ],
            ),
          ),
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
        if (!isLocked) ...[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width * 0.35,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: () => player.seek(position - const Duration(seconds: 10)),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width * 0.35,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: () => player.seek(position + const Duration(seconds: 10)),
            ),
          ),
        ],
        if (isLocked)
          Positioned(
            top: 16,
            left: 16,
            child: FloatingActionButton.small(
              backgroundColor: Colors.redAccent.withOpacity(0.8),
              child: const Icon(Icons.lock),
              onPressed: () {
                setState(() => isLocked = false);
                showMsg("Screen Unlocked");
              },
            ),
          ),
      ],
    );
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
          title: const Text('Mehra Player Pro', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: Icon(isLocked ? Icons.lock : Icons.lock_open, color: isLocked ? Colors.redAccent : Colors.white),
              tooltip: 'Screen Lock',
              onPressed: () => setState(() => isLocked = !isLocked),
            ),
            IconButton(
              icon: const Icon(Icons.subtitles),
              tooltip: 'Subtitles',
              onPressed: openSubtitleMenu,
            ),
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Download Media',
              onPressed: openDownloadDialog,
            ),
            IconButton(
              icon: const Icon(Icons.aspect_ratio),
              tooltip: 'Aspect Ratio: $fitLabel',
              onPressed: cycleAspectRatio,
            ),
            IconButton(
              icon: Icon(ambientLight ? Icons.blur_on : Icons.blur_off, color: ambientLight ? Colors.amberAccent : Colors.grey),
              tooltip: 'Ambient Light',
              onPressed: () => setState(() => ambientLight = !ambientLight),
            ),
            IconButton(
              icon: Icon(Icons.surround_sound, color: dolbyAtmos ? Colors.cyanAccent : Colors.grey),
              tooltip: 'Dolby Boost',
              onPressed: toggleDolby,
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Browse Single File',
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
          ],
        ),
        body: Column(
          children: [
            Expanded(
              flex: 5,
              child: _buildPlayerContent(currentFile, currentTitle),
            ),
            if (!isLocked)
              Container(
                color: const Color(0xFF131318),
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(formatTime(position), style: const TextStyle(fontSize: 12)),
                        Expanded(
                          child: Slider(
                            activeColor: Colors.deepPurpleAccent,
                            value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
                            max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                            onChanged: (val) => player.seek(Duration(milliseconds: val.toInt())),
                          ),
                        ),
                        Text(formatTime(duration), style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(Icons.shuffle, color: isShuffle ? Colors.cyanAccent : Colors.grey),
                          onPressed: () => setState(() => isShuffle = !isShuffle),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous, size: 30),
                          onPressed: prevTrack,
                        ),
                        IconButton(
                          iconSize: 42,
                          icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.deepPurpleAccent),
                          onPressed: () => player.playOrPause(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next, size: 30),
                          onPressed: nextTrack,
                        ),
                        IconButton(
                          icon: Icon(Icons.repeat, color: isRepeat ? Colors.cyanAccent : Colors.grey),
                          onPressed: () => setState(() => isRepeat = !isRepeat),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, bottom: 2.0),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.content_cut, size: 16),
                            label: const Text('Trim / Cut Video'),
                            onPressed: openTrimDialog,
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.audio_file, size: 16),
                            label: const Text('Save as MP3'),
                            onPressed: extractMp3,
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.camera_alt, size: 16),
                            label: const Text('Screenshot'),
                            onPressed: takeScreenshot,
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Speed: '),
                              DropdownButton<double>(
                                value: speed,
                                dropdownColor: Colors.grey[900],
                                items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                                    .map((s) => DropdownMenuItem(value: s, child: Text('${s}x')))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => speed = val);
                                    player.setRate(val);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              color: const Color(0xFF171720),
              child: const TabBar(
                indicatorColor: Colors.deepPurpleAccent,
                tabs: [
                  Tab(icon: Icon(Icons.video_library), text: "Videos"),
                  Tab(icon: Icon(Icons.library_music), text: "Audio Songs"),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: TabBarView(
                children: [
                  videoList.isEmpty
                      ? const Center(child: Text("Koi video nahi mili (Folder check karein)"))
                      : ListView.builder(
                          itemCount: videoList.length,
                          itemBuilder: (ctx, i) {
                            final name = videoList[i].path.split(Platform.pathSeparator).last;
                            final isSel = !isAudioMode && currentIndex == i;
                            return ListTile(
                              dense: true,
                              selected: isSel,
                              selectedTileColor: Colors.deepPurple.withOpacity(0.35),
                              leading: const Icon(Icons.video_collection, color: Colors.deepPurpleAccent),
                              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () => playMedia(i, false),
                            );
                          },
                        ),
                  audioList.isEmpty
                      ? const Center(child: Text("Koi audio song nahi mila"))
                      : ListView.builder(
                          itemCount: audioList.length,
                          itemBuilder: (ctx, i) {
                            final name = audioList[i].path.split(Platform.pathSeparator).last;
                            final isSel = isAudioMode && currentIndex == i;
                            return ListTile(
                              dense: true,
                              selected: isSel,
                              selectedTileColor: Colors.deepPurple.withOpacity(0.35),
                              leading: const Icon(Icons.music_note, color: Colors.cyanAccent),
                              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () => playMedia(i, true),
                            );
                          },
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
