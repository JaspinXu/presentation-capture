import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/video_record.dart';
import '../services/app_database.dart';
import '../services/auth_service.dart';
import '../services/upload_service.dart';
import 'local_video_page.dart';
import 'record_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.authService,
    required this.languageCode,
    required this.onLanguageChanged,
    required this.onSignedOut,
  });

  final AuthService authService;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onSignedOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  List<VideoRecord>? _videos;
  Timer? _pollTimer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load(reconcile: true));
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_load(reconcile: true)),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load(reconcile: true));
  }

  Future<void> _load({bool reconcile = false}) async {
    if (_loading) return;
    _loading = true;
    try {
      var videos = await AppDatabase.instance.allVideos();
      if (mounted) setState(() => _videos = videos);
      if (reconcile) {
        final uploader = UploadService(authService: widget.authService);
        await Future.wait(videos.map(uploader.reconcile));
        videos = await AppDatabase.instance.allVideos();
        if (mounted) setState(() => _videos = videos);
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _record() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecordPage()),
    );
    await _load(reconcile: true);
  }

  Future<void> _retry(VideoRecord video) async {
    try {
      await UploadService(authService: widget.authService)
          .enqueue(video, force: true);
    } catch (_) {}
    await _load();
  }

  String _statusText(BuildContext context, UploadStatus status) {
    return context.strings.get(switch (status) {
      UploadStatus.localOnly => 'localOnly',
      UploadStatus.waiting => 'waiting',
      UploadStatus.uploading => 'uploading',
      UploadStatus.uploaded => 'uploaded',
      UploadStatus.failed => 'failed',
    });
  }

  Color _statusColor(UploadStatus status) => switch (status) {
    UploadStatus.uploaded => Colors.green,
    UploadStatus.failed => Colors.red,
    UploadStatus.uploading => Colors.blue,
    UploadStatus.waiting => Colors.orange,
    UploadStatus.localOnly => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final videos = _videos;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.strings.get('videos')),
        actions: [
          IconButton(
            tooltip: context.strings.get('settings'),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    languageCode: widget.languageCode,
                    onLanguageChanged: widget.onLanguageChanged,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: context.strings.get('logout'),
            onPressed: () async {
              await widget.authService.signOut();
              widget.onSignedOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: videos == null
          ? const Center(child: CircularProgressIndicator())
          : videos.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.video_library_outlined,
                    size: 72,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(context.strings.get('empty')),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(reconcile: true),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: videos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final video = videos[index];
                  final exists = File(video.localPath).existsSync();
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: const CircleAvatar(
                        radius: 28,
                        child: Icon(Icons.videocam),
                      ),
                      title: Text(
                        video.title.isEmpty ? video.experimentId : video.title,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            '${video.participantId} • ${video.resolution} • '
                            '${Duration(seconds: video.durationSeconds).inMinutes}m '
                            '${video.durationSeconds % 60}s',
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 10,
                                color: _statusColor(video.status),
                              ),
                              const SizedBox(width: 6),
                              Text(_statusText(context, video.status)),
                            ],
                          ),
                          if (video.status == UploadStatus.uploading)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: LinearProgressIndicator(
                                value: video.progress,
                              ),
                            ),
                        ],
                      ),
                      onTap: exists
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LocalVideoPage(
                                  path: video.localPath,
                                  title: video.title.isEmpty
                                      ? video.experimentId
                                      : video.title,
                                ),
                              ),
                            )
                          : null,
                      trailing: video.status == UploadStatus.failed
                          ? IconButton(
                              tooltip: context.strings.get('retry'),
                              onPressed: () => _retry(video),
                              icon: const Icon(Icons.refresh),
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _record,
        icon: const Icon(Icons.fiber_manual_record),
        label: Text(context.strings.get('record')),
      ),
    );
  }
}
