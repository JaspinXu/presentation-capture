import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_strings.dart';
import '../models/recorded_draft.dart';
import '../models/video_record.dart';
import '../services/app_database.dart';
import '../services/upload_service.dart';
import 'record_page.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.draft});
  final RecordedDraft draft;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _experiment = TextEditingController();
  final _participant = TextEditingController();
  final _notes = TextEditingController();
  late final VideoPlayerController _video;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _video = VideoPlayerController.file(File(widget.draft.localPath))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _video.dispose();
    _title.dispose();
    _experiment.dispose();
    _participant.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final file = File(widget.draft.localPath);
    final digest = await sha256.bind(file.openRead()).first;
    final video = VideoRecord(
      id: widget.draft.id,
      localPath: widget.draft.localPath,
      recordedAt: widget.draft.recordedAt,
      durationSeconds: widget.draft.durationSeconds,
      resolution: widget.draft.resolution,
      fileSize: await file.length(),
      sha256: digest.toString(),
      status: UploadStatus.waiting,
      title: _title.text.trim(),
      experimentId: _experiment.text.trim(),
      participantId: _participant.text.trim(),
      notes: _notes.text.trim(),
    );
    await AppDatabase.instance.save(video);
    unawaited(UploadService().enqueue(video).catchError((_) {}));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _retake() async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.get('retakeQuestion')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.strings.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: Text(context.strings.get('keepOld')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: Text(context.strings.get('deleteOld')),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    final file = File(widget.draft.localPath);
    if (action == 'delete') {
      if (await file.exists()) await file.delete();
      if (widget.draft.photoAssetId.isNotEmpty) {
        await PhotoManager.editor.deleteWithIds([widget.draft.photoAssetId]);
      }
    } else {
      final digest = await sha256.bind(file.openRead()).first;
      await AppDatabase.instance.save(
        VideoRecord(
          id: widget.draft.id,
          localPath: widget.draft.localPath,
          recordedAt: widget.draft.recordedAt,
          durationSeconds: widget.draft.durationSeconds,
          resolution: widget.draft.resolution,
          fileSize: await file.length(),
          sha256: digest.toString(),
          status: UploadStatus.localOnly,
        ),
      );
    }
    if (!mounted) return;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RecordPage()),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? context.strings.get('required')
      : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.strings.get('review'))),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: _video.value.isInitialized
                      ? GestureDetector(
                          onTap: () => setState(() {
                            _video.value.isPlaying
                                ? _video.pause()
                                : _video.play();
                          }),
                          child: AspectRatio(
                            aspectRatio: _video.value.aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(_video),
                                if (!_video.value.isPlaying)
                                  const Icon(
                                    Icons.play_circle_fill,
                                    size: 72,
                                    color: Colors.white70,
                                  ),
                              ],
                            ),
                          ),
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(context.strings.get('savedPhotos')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _title,
                      decoration: InputDecoration(
                        labelText: context.strings.get('title'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _experiment,
                      validator: _required,
                      decoration: InputDecoration(
                        labelText: context.strings.get('experimentId'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _participant,
                      validator: _required,
                      decoration: InputDecoration(
                        labelText: context.strings.get('participantId'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notes,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: context.strings.get('notes'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.cloud_upload),
                      label: Text(context.strings.get('save')),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _retake,
                      child: Text(context.strings.get('retake')),
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
