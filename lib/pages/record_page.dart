import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_strings.dart';
import '../models/recorded_draft.dart';
import 'review_page.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> with WidgetsBindingObserver {
  CameraController? _controller;
  Timer? _timer;
  int _seconds = 0;
  String _resolution = '720p';
  Object? _error;
  bool _stopping = false;

  bool get _recording => _controller?.value.isRecordingVideo ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      final preferences = await SharedPreferences.getInstance();
      _resolution = preferences.getString('resolution') ?? '720p';
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        _resolution == '1080p'
            ? ResolutionPreset.veryHigh
            : ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused) &&
        _recording) {
      unawaited(_stopRecording());
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.lockCaptureOrientation();
    await controller.prepareForVideoRecording();
    await controller.startVideoRecording();
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    setState(() {});
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    if (controller == null || !_recording || _stopping) return;
    _stopping = true;
    _timer?.cancel();
    try {
      final captured = await controller.stopVideoRecording();
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(p.join(documents.path, 'recordings'));
      await directory.create(recursive: true);
      final id = const Uuid().v4();
      final destination = File(p.join(directory.path, '$id.mp4'));
      await File(captured.path).copy(destination.path);

      var photoAssetId = '';
      final permission = await PhotoManager.requestPermissionExtend();
      if (permission.isAuth) {
        final asset = await PhotoManager.editor.saveVideo(
          destination,
          title: 'NUS_Presentation_$id.mp4',
          creationDate: DateTime.now(),
        );
        photoAssetId = asset.id;
      }
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewPage(
            draft: RecordedDraft(
              id: id,
              localPath: destination.path,
              photoAssetId: photoAssetId,
              recordedAt: DateTime.now(),
              durationSeconds: _seconds,
              resolution: _resolution,
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      _stopping = false;
    }
  }

  String get _duration {
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller?.value.isInitialized ?? false)
              Center(
                child: AspectRatio(
                  aspectRatio: controller!.value.aspectRatio,
                  child: CameraPreview(controller),
                ),
              )
            else
              Center(
                child: _error == null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            context.strings.get('preparingCamera'),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      )
                    : Text(
                        context.strings.get('cameraError'),
                        style: const TextStyle(color: Colors.white),
                      ),
              ),
            Positioned(
              top: 16,
              left: 16,
              child: IconButton.filledTonal(
                onPressed: _recording ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Positioned(
              top: 20,
              right: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    '$_resolution  •  $_duration',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 28,
              top: 0,
              bottom: 0,
              child: Center(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _recording ? Colors.red : Colors.white,
                    foregroundColor: _recording ? Colors.white : Colors.red,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                  ),
                  onPressed:
                      controller?.value.isInitialized != true || _stopping
                      ? null
                      : (_recording ? _stopRecording : _startRecording),
                  icon: Icon(
                    _recording ? Icons.stop : Icons.fiber_manual_record,
                  ),
                  label: Text(
                    context.strings.get(_recording ? 'stop' : 'start'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
