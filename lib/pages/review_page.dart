import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_strings.dart';
import '../models/recorded_draft.dart';
import '../models/video_record.dart';
import '../services/app_database.dart';
import '../services/media_processing_service.dart';
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
  XFile? _presentation;
  String? _processingError;

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
    if (_presentation == null) {
      setState(
        () => _processingError = context.strings.get('presentationRequired'),
      );
      return;
    }
    setState(() {
      _saving = true;
      _processingError = null;
    });
    try {
      final documents = await getApplicationDocumentsDirectory();
      final videoFile = File(widget.draft.localPath);
      final audioDirectory = Directory(p.join(documents.path, 'audio'));
      final presentationDirectory = Directory(
        p.join(documents.path, 'presentations'),
      );
      await audioDirectory.create(recursive: true);
      await presentationDirectory.create(recursive: true);

      final extension = p.extension(_presentation!.name).toLowerCase();
      final presentationFile = File(
        p.join(presentationDirectory.path, '${widget.draft.id}$extension'),
      );
      await File(_presentation!.path).copy(presentationFile.path);
      final audioPath = p.join(audioDirectory.path, '${widget.draft.id}.wav');
      await MediaProcessingService().extractAudio(
        videoPath: videoFile.path,
        outputPath: audioPath,
      );
      final audioFile = File(audioPath);

      final videoDigest = await sha256.bind(videoFile.openRead()).first;
      final audioDigest = await sha256.bind(audioFile.openRead()).first;
      final presentationDigest = await sha256
          .bind(presentationFile.openRead())
          .first;
      final video = VideoRecord(
        id: widget.draft.id,
        localPath: widget.draft.localPath,
        recordedAt: widget.draft.recordedAt,
        durationSeconds: widget.draft.durationSeconds,
        resolution: widget.draft.resolution,
        fileSize: await videoFile.length(),
        sha256: videoDigest.toString(),
        audioPath: audioFile.path,
        audioSize: await audioFile.length(),
        audioSha256: audioDigest.toString(),
        presentationPath: presentationFile.path,
        presentationName: _presentation!.name,
        presentationSize: await presentationFile.length(),
        presentationSha256: presentationDigest.toString(),
        status: UploadStatus.waiting,
        title: _title.text.trim(),
        experimentId: _experiment.text.trim(),
        participantId: _participant.text.trim(),
        notes: _notes.text.trim(),
      );
      await AppDatabase.instance.save(video);
      unawaited(UploadService().enqueue(video).catchError((_) {}));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _processingError = context.strings.get('processingFailed');
        });
      }
    }
  }

  Future<void> _pickPresentation() async {
    const typeGroup = XTypeGroup(
      label: 'Presentation',
      extensions: ['ppt', 'pptx', 'pdf'],
    );
    final selected = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (selected != null && mounted) {
      setState(() {
        _presentation = selected;
        _processingError = null;
      });
    }
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

  Widget _videoPreview() => ColoredBox(
    color: Colors.black,
    child: Center(
      child: _video.value.isInitialized
          ? GestureDetector(
              onTap: () => setState(() {
                _video.value.isPlaying ? _video.pause() : _video.play();
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
  );

  Widget _metadataForm() => Form(
    key: _formKey,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Flexible(child: Text(context.strings.get('savedInApp'))),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _title,
          decoration: InputDecoration(labelText: context.strings.get('title')),
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
          decoration: InputDecoration(labelText: context.strings.get('notes')),
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: InputDecoration(
            labelText: context.strings.get('presentationFile'),
          ),
          child: Row(
            children: [
              const Icon(Icons.slideshow_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _presentation?.name ??
                      context.strings.get('choosePresentation'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _pickPresentation,
                child: Text(context.strings.get('choosePresentation')),
              ),
            ],
          ),
        ),
        if (_processingError != null) ...[
          const SizedBox(height: 8),
          Text(
            _processingError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload),
          label: Text(
            context.strings.get(_saving ? 'preparingBundle' : 'save'),
          ),
        ),
        TextButton(
          onPressed: _saving ? null : _retake,
          child: Text(context.strings.get('retake')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.strings.get('review'))),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 700) {
              return Row(
                children: [
                  Expanded(flex: 3, child: _videoPreview()),
                  Expanded(flex: 2, child: _metadataForm()),
                ],
              );
            }
            return Column(
              children: [
                SizedBox(
                  height: constraints.maxHeight * 0.38,
                  child: _videoPreview(),
                ),
                Expanded(child: _metadataForm()),
              ],
            );
          },
        ),
      ),
    );
  }
}
