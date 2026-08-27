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
      'signIn': 'Sign in',
      'account': 'Email or username',
      'password': 'Password',
      'demoHint': 'Demo: demo@nus.edu.sg / demo1234',
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
      'preparingCamera': 'Preparing camera…',
      'cameraError': 'Camera could not be opened',
      'landscapeHint': 'Rotate your iPhone to landscape',
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
      'savedPhotos': 'Saved to Photos',
      'waiting': 'Waiting',
      'uploading': 'Uploading',
      'uploaded': 'Uploaded',
      'failed': 'Failed',
      'localOnly': 'Local only',
      'retry': 'Retry',
      'serverUrl': 'Server URL',
      'cellular': 'Allow mobile data uploads',
      'saveSettings': 'Save settings',
      'loginFailed': 'Sign-in failed. Check the account and server.',
      'uploadUnavailable':
          'Saved locally. Upload will resume when the server is available.',
    },
    'zh': {
      'appName': 'NUS 演示视频采集',
      'signIn': '登录',
      'account': '邮箱或用户名',
      'password': '密码',
      'demoHint': '演示账号：demo@nus.edu.sg / demo1234',
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
      'preparingCamera': '正在准备摄像头…',
      'cameraError': '无法打开摄像头',
      'landscapeHint': '请将 iPhone 横向放置',
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
      'savedPhotos': '已保存到照片',
      'waiting': '等待上传',
      'uploading': '正在上传',
      'uploaded': '上传成功',
      'failed': '上传失败',
      'localOnly': '仅本地',
      'retry': '重试',
      'serverUrl': '服务器地址',
      'cellular': '允许使用移动网络上传',
      'saveSettings': '保存设置',
      'loginFailed': '登录失败，请检查账号和服务器。',
      'uploadUnavailable': '视频已保存在本地，服务器可用后将继续上传。',
    },
  };

  String get(String key) =>
      _values[languageCode]?[key] ?? _values['en']![key] ?? key;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStringsScope.of(this);
}
