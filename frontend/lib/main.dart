/// Just Now - Main Application Entry Point
/// Intent-Driven GenUI for Android
/// Uses Record & Upload architecture for voice input (Route B)
/// All UI text in Simplified Chinese (简体中文)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'core/app_state.dart';
import 'core/renderer.dart';
import 'services/intent_service.dart';

void main() {
  runApp(const JustNowApp());
}

class JustNowApp extends StatelessWidget {
  const JustNowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Just Now',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _textController = TextEditingController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isProcessingVoice = false;
  String? _currentRecordingPath;

  @override
  void dispose() {
    _textController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  /// Start recording audio
  Future<void> _startRecording() async {
    try {
      // Check permission
      if (!await _audioRecorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('需要麦克风权限才能录音'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Get temporary directory for saving recording
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/voice_input_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Start recording with AAC encoder for compatibility
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      setState(() {
        _isRecording = true;
        _currentRecordingPath = filePath;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('录音启动失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Stop recording and send to backend
  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    try {
      final path = await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
      });

      if (path != null && path.isNotEmpty) {
        // Check if file exists and has content
        final file = File(path);
        if (await file.exists() && await file.length() > 0) {
          await _processVoiceInput(path);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('录音文件为空，请重试'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('录音停止失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Process voice input by uploading to backend
  Future<void> _processVoiceInput(String filePath) async {
    setState(() {
      _isProcessingVoice = true;
    });

    try {
      final response = await IntentService.sendVoiceCommand(filePath: filePath);

      if (mounted) {
        final appState = context.read<AppState>();
        appState.setResponse(response);
      }
    } catch (e) {
      if (mounted) {
        final appState = context.read<AppState>();
        appState.setError(e.toString());
      }
    } finally {
      setState(() {
        _isProcessingVoice = false;
      });

      // Clean up temporary file
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  /// Submit text intent to backend
  void _submitIntent(String text) {
    if (text.trim().isEmpty) return;
    final appState = context.read<AppState>();
    appState.processIntent(text.trim());
    _textController.clear();
  }

  void _processWithScenario(String scenario) {
    final appState = context.read<AppState>();
    appState.processIntent(
      'Demo request for $scenario',
      mockScenario: scenario,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Just Now'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Demo scenario selector
          PopupMenuButton<String>(
            icon: const Icon(Icons.science_outlined),
            tooltip: '演示场景',
            onSelected: _processWithScenario,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'taxi_default',
                child: ListTile(
                  leading: Icon(Icons.local_taxi),
                  title: Text('打车场景'),
                  subtitle: Text('MapView + ActionList'),
                ),
              ),
              const PopupMenuItem(
                value: 'code_demo',
                child: ListTile(
                  leading: Icon(Icons.code),
                  title: Text('代码演示'),
                  subtitle: Text('InfoCard with Markdown'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Main content area
          Expanded(
            child: _MainBody(
              isRecording: _isRecording,
              isProcessingVoice: _isProcessingVoice,
            ),
          ),
          // Text input field
          SafeArea(
            top: false,
            child: _buildTextInputBar(),
          ),
        ],
      ),
      // The Orb - Floating Action Button
      floatingActionButton: _buildTheOrb(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// Build text input bar for text input
  Widget _buildTextInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), // Extra bottom padding for FAB
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: '输入指令（如："去南京南站"）',
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: _submitIntent,
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          Consumer<AppState>(
            builder: (context, appState, _) {
              final isLoading = appState.isLoading || _isProcessingVoice;
              return IconButton.filled(
                onPressed: isLoading
                    ? null
                    : () => _submitIntent(_textController.text),
                icon: const Icon(Icons.send),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Build The Orb (FAB with mic) - supports long press to record
  Widget _buildTheOrb() {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final isLoading = appState.isLoading || _isProcessingVoice;

        return GestureDetector(
          onLongPressStart: isLoading ? null : (_) => _startRecording(),
          onLongPressEnd: isLoading ? null : (_) => _stopRecording(),
          child: FloatingActionButton.large(
            onPressed: isLoading
                ? null
                : () {
                    // Show instruction on tap
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('长按按钮开始录音，松开结束'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
            backgroundColor: _isRecording
                ? Colors.red.shade600
                : (isLoading ? Colors.grey : Colors.blue.shade600),
            child: isLoading
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    size: 36,
                    color: Colors.white,
                  ),
          ),
        );
      },
    );
  }
}

/// Main body content - shows GenUI response or instructions
class _MainBody extends StatelessWidget {
  final bool isRecording;
  final bool isProcessingVoice;

  const _MainBody({
    required this.isRecording,
    required this.isProcessingVoice,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Show recording indicator
    if (isRecording) {
      return _buildRecordingState(context);
    }

    // Show processing indicator for voice
    if (isProcessingVoice) {
      return _buildProcessingVoiceState();
    }

    switch (appState.uiState) {
      case AppUIState.idle:
        return _buildIdleState(context);
      case AppUIState.thinking:
        return _buildThinkingState();
      case AppUIState.rendering:
        return _buildRenderingState(context, appState);
      case AppUIState.error:
        return _buildErrorState(context, appState);
    }
  }

  Widget _buildRecordingState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mic,
                size: 50,
                color: Colors.red.shade600,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '正在聆听...',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '松开按钮结束录音',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 24),
            // Animated recording indicator
            SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                color: Colors.red.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingVoiceState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_upload,
              size: 40,
              color: Colors.blue.shade600,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '正在处理语音...',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '正在上传并识别您的语音指令',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 24),
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            Text(
              '长按语音按钮开始',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '长按麦克风按钮录音\n或在下方输入框输入文字指令',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.blue.shade600, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '试试说："打车去南京南站"',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
          const SizedBox(height: 24),
          Text(
            '正在思考...',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRenderingState(BuildContext context, AppState appState) {
    final response = appState.currentResponse!;
    final components = response.uiPayload.components;

    return Stack(
      children: [
        // Scrollable GenUI content
        SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header showing intent info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: response.category == 'SERVICE'
                                ? Colors.green.shade100
                                : Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            response.category == 'SERVICE' ? '服务' : '聊天',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: response.category == 'SERVICE'
                                  ? Colors.green.shade800
                                  : Colors.purple.shade800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => appState.dismiss(),
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                    if (response.slots.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      // Wrap destination info with Expanded and ellipsis
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              response.slots.entries
                                  .map((e) => '${e.key}: ${e.value}')
                                  .join(' | '),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Render GenUI components using the registry
              GenUIRenderer.render(components),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, AppState appState) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              '出错了',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                appState.errorMessage ?? '未知错误',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => appState.reset(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
