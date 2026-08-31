import 'package:flutter/widgets.dart';

class AppStringsScope extends InheritedWidget {
  const AppStringsScope({
    super.key,
    required this.languageCode,
    required super.child,
  });

  final String languageCode;

  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    return AppStrings(scope?.languageCode ?? 'en');
  }

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) =>
      languageCode != oldWidget.languageCode;
}

class AppStrings {
  AppStrings(this.languageCode);
  final String languageCode;

  static const Map<String, Map<String, String>> _values = {
    'en': {
      'appName': 'NUS Presentation Capture',
      'continueGoogle': 'Continue with Google',
      'videos': 'My recordings',
      'empty': 'No recordings yet',
      'record': 'Record presentation',
      'settings': 'Settings',
      'logout': 'Sign out',
      'resolution': 'Recording resolution',
      'language': 'Language',
      'english': 'English',
      'chinese': '中文',
      'start': 'Start recording',
      'stop': 'Stop',
      'pause': 'Pause',
      'resume': 'Resume',
      'preparingCamera': 'Preparing camera…',
      'cameraError': 'Camera could not be opened',
      'resolutionFallback': 'This iPhone does not support the selected mode; a compatible resolution is being used.',
      'landscapeHint': 'Rotate your iPhone to the recording orientation',
      'presentationFile': 'Presentation file',
      'choosePresentation': 'Choose PPT, PPTX or PDF',
      'presentationRequired': 'Choose a PPT, PPTX or PDF before uploading.',
      'preparingBundle': 'Preparing video, audio and presentation…',
      'processingFailed':
          'Could not prepare the upload bundle. Please try again.',
      'review': 'Review recording',
      'title': 'Title (optional)',
      'experimentId': 'Experiment ID',
      'participantId': 'Participant ID',
      'notes': 'Notes (optional)',
      'save': 'Save and upload',
      'retake': 'Record again',
      'keepOld': 'Keep original',
      'deleteOld': 'Delete original',
      'cancel': 'Cancel',
      'retakeQuestion': 'What should happen to this recording?',
      'required': 'Required',
      'savedInApp': 'Saved securely inside the app',
      'lowStorage': 'Low storage space',
      'lowStorageMessage': 'High-resolution recording can consume several GB. Free some storage before a long recording.',
      'recordAnyway': 'Continue',
      'waiting': 'Waiting',
      'uploading': 'Uploading',
      'uploaded': 'Uploaded',
      'failed': 'Failed',
      'localOnly': 'Local only',
      'retry': 'Retry',
      'delete': 'Delete local files',
      'deleteConfirm': 'Delete the local video, audio, and presentation? Uploaded server files will not be deleted.',
      'serverUrl': 'Server URL',
      'cellular': 'Allow mobile data uploads',
      'saveSettings': 'Save settings',
      'socialLoginFailed':
          'Social sign-in failed. Check the provider and server configuration.',
      'uploadUnavailable':
          'Saved locally. Upload will resume when the server is available.',
    },
    'zh': {
      'appName': 'NUS 演示视频采集',
      'continueGoogle': '使用 Google 登录',
      'videos': '我的录制',
      'empty': '暂无录制视频',
      'record': '录制演示视频',
      'settings': '设置',
      'logout': '退出登录',
      'resolution': '录制分辨率',
      'language': '语言',
      'english': 'English',
      'chinese': '中文',
      'start': '开始录制',
      'stop': '停止',
      'pause': '暂停',
      'resume': '继续',
      'preparingCamera': '正在准备摄像头…',
      'cameraError': '无法打开摄像头',
      'resolutionFallback': '此 iPhone 不支持所选模式，已自动使用兼容的分辨率。',
      'landscapeHint': '请将 iPhone 旋转到需要录制的方向',
      'presentationFile': '演示文稿文件',
      'choosePresentation': '选择 PPT、PPTX 或 PDF',
      'presentationRequired': '上传前请选择 PPT、PPTX 或 PDF 文件。',
      'preparingBundle': '正在准备视频、音频和演示文稿…',
      'processingFailed': '无法准备上传文件，请重试。',
      'review': '预览录制',
      'title': '标题（选填）',
      'experimentId': '实验编号',
      'participantId': '参与者编号',
      'notes': '备注（选填）',
      'save': '保存并上传',
      'retake': '重新录制',
      'keepOld': '保留原视频',
      'deleteOld': '删除原视频',
      'cancel': '取消',
      'retakeQuestion': '如何处理当前录制？',
      'required': '必填',
      'savedInApp': '已安全保存在 App 内',
      'lowStorage': '存储空间不足',
      'lowStorageMessage': '高分辨率长时间录制可能占用数 GB，请先清理存储空间。',
      'recordAnyway': '仍要继续',
      'waiting': '等待上传',
      'uploading': '正在上传',
      'uploaded': '上传成功',
      'failed': '上传失败',
      'localOnly': '仅本地',
      'retry': '重试',
      'delete': '删除本地文件',
      'deleteConfirm': '删除本地视频、音频和演示文稿？已经上传到服务器的文件不会被删除。',
      'serverUrl': '服务器地址',
      'cellular': '允许使用移动网络上传',
      'saveSettings': '保存设置',
      'socialLoginFailed': '第三方登录失败，请检查登录提供商与服务器配置。',
      'uploadUnavailable': '视频已保存在本地，服务器可用后将继续上传。',
    },
  };

  String get(String key) =>
      _values[languageCode]?[key] ?? _values['en']![key] ?? key;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStringsScope.of(this);
}
