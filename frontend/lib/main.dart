/// Just Now - Main Application Entry Point
/// Intent-Driven GenUI for Android (Walking Skeleton Demo)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
            onSelected: (scenario) {
              _processWithScenario(context, scenario);
            },
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
      body: const _MainBody(),
      // The Orb - Floating Action Button
      floatingActionButton: const _TheOrb(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _processWithScenario(BuildContext context, String scenario) {
    final appState = context.read<AppState>();
    appState.processIntent(
      'Demo request for $scenario',
      mockScenario: scenario,
    );
  }
}

/// The Orb - Main interaction trigger (FAB)
class _TheOrb extends StatelessWidget {
  const _TheOrb();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isLoading = appState.isLoading;

    return FloatingActionButton.large(
      onPressed: isLoading ? null : () => _onOrbPressed(context),
      backgroundColor: isLoading ? Colors.grey : Colors.blue.shade600,
      child: isLoading
          ? const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            )
          : const Icon(
              Icons.mic,
              size: 36,
              color: Colors.white,
            ),
    );
  }

  void _onOrbPressed(BuildContext context) {
    // For demo: Send hardcoded request to trigger taxi scenario
    final appState = context.read<AppState>();
    appState.processIntent('帮我打车去南京南站');
  }
}

/// Main body content - shows GenUI response or instructions
class _MainBody extends StatelessWidget {
  const _MainBody();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

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
              'Press the microphone button below to send a request\nor use the flask icon for demo scenarios.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 100), // Space for FAB
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
          padding: const EdgeInsets.only(bottom: 100), // Space for FAB
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
