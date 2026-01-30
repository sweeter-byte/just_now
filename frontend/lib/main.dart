/// Just Now - Main Application Entry Point
/// Intent-Driven GenUI for Android (Walking Skeleton Demo)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'core/app_state.dart';
import 'core/renderer.dart';

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
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _recognizedText = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _textController.dispose();
    _speech.stop();
    super.dispose();
  }

  /// Initialize speech recognition
  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Speech error: ${error.errorMsg}'),
            backgroundColor: Colors.orange,
          ),
        );
      },
    );
    setState(() {});
  }

  /// Start listening for speech input
  Future<void> _startListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition not available. Use text input below.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isListening = true;
      _recognizedText = '';
    });

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _recognizedText = result.recognizedWords;
        });
        // Auto-submit when speech is final
        if (result.finalResult && _recognizedText.isNotEmpty) {
          _submitIntent(_recognizedText);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      localeId: 'zh_CN', // Chinese locale for better recognition
    );
  }

  /// Stop listening
  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
    // Submit if we have recognized text
    if (_recognizedText.isNotEmpty) {
      _submitIntent(_recognizedText);
    }
  }

  /// Submit intent to backend
  void _submitIntent(String text) {
    if (text.trim().isEmpty) return;
    final appState = context.read<AppState>();
    appState.processIntent(text.trim());
    _textController.clear();
    setState(() => _recognizedText = '');
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
      appBar: AppBar(
        title: const Text('Just Now'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Demo scenario selector
          PopupMenuButton<String>(
            icon: const Icon(Icons.science_outlined),
            tooltip: 'Demo Scenarios',
            onSelected: _processWithScenario,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'taxi_default',
                child: ListTile(
                  leading: Icon(Icons.local_taxi),
                  title: Text('Taxi Scenario'),
                  subtitle: Text('MapView + ActionList'),
                ),
              ),
              const PopupMenuItem(
                value: 'code_demo',
                child: ListTile(
                  leading: Icon(Icons.code),
                  title: Text('Code Demo'),
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
            child: _MainBody(recognizedText: _isListening ? _recognizedText : null),
          ),
          // Text input field for emulator testing
          _buildTextInputBar(),
        ],
      ),
      // The Orb - Floating Action Button
      floatingActionButton: _buildTheOrb(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// Build text input bar for emulator testing
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
                hintText: 'Type a command (e.g., "Go to Nanjing South Station")',
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
              return IconButton.filled(
                onPressed: appState.isLoading
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

  /// Build The Orb (FAB with mic)
  Widget _buildTheOrb() {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final isLoading = appState.isLoading;

        return FloatingActionButton.large(
          onPressed: isLoading
              ? null
              : (_isListening ? _stopListening : _startListening),
          backgroundColor: _isListening
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
                  _isListening ? Icons.stop : Icons.mic,
                  size: 36,
                  color: Colors.white,
                ),
        );
      },
    );
  }
}

/// Main body content - shows GenUI response or instructions
class _MainBody extends StatelessWidget {
  final String? recognizedText;

  const _MainBody({this.recognizedText});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Show listening indicator when recognizing speech
    if (recognizedText != null) {
      return _buildListeningState(context, recognizedText!);
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

  Widget _buildListeningState(BuildContext context, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mic,
                size: 40,
                color: Colors.red.shade600,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Listening...',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Text(
                text.isEmpty ? 'Speak now...' : text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: text.isEmpty ? Colors.grey.shade400 : Colors.black87,
                  fontStyle: text.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
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
              'Tap The Orb to Begin',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Press the microphone button to speak\nor type a command in the text field below.',
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
                  Text(
                    'Try: "Go to Nanjing South Station"',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade700,
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
            'Thinking...',
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
                            response.category,
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
                          tooltip: 'Dismiss',
                        ),
                      ],
                    ),
                    if (response.slots.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        response.slots.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join(' • '),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appState.errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => appState.reset(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
