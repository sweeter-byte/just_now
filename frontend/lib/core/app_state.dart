/// Just Now - Application State (Provider)
/// Manages UI states: Idle -> Thinking -> Rendering per LLD.

import 'package:flutter/foundation.dart';
import '../models/genui_models.dart';
import '../services/intent_service.dart';

/// UI state enum per LLD specification
enum AppUIState {
  idle,      // Waiting for user input
  thinking,  // Processing request
  rendering, // Displaying GenUI response
  error,     // Error state
}

class AppState extends ChangeNotifier {
  AppUIState _uiState = AppUIState.idle;
  GenUIResponse? _currentResponse;
  String? _errorMessage;

  // Getters
  AppUIState get uiState => _uiState;
  GenUIResponse? get currentResponse => _currentResponse;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _uiState == AppUIState.thinking;
  bool get hasResponse => _currentResponse != null;

  /// Process an intent with the given input text.
  Future<void> processIntent(String textInput, {String? mockScenario}) async {
    // Transition to thinking state
    _uiState = AppUIState.thinking;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await IntentService.processIntent(
        textInput: textInput,
        mockScenario: mockScenario,
      );

      // Transition to rendering state
      _currentResponse = response;
      _uiState = AppUIState.rendering;
      notifyListeners();
    } on IntentServiceException catch (e) {
      _uiState = AppUIState.error;
      _errorMessage = e.userTip ?? e.message;
      notifyListeners();
    } catch (e) {
      _uiState = AppUIState.error;
      _errorMessage = 'Unexpected error: $e';
      notifyListeners();
    }
  }

  /// Reset to idle state and clear response.
  void reset() {
    _uiState = AppUIState.idle;
    _currentResponse = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Dismiss the current response (close overlay).
  void dismiss() {
    _uiState = AppUIState.idle;
    // Keep currentResponse in memory for quick re-display if needed
    notifyListeners();
  }

  /// Set response directly (used for voice input processing).
  void setResponse(GenUIResponse response) {
    _currentResponse = response;
    _uiState = AppUIState.rendering;
    _errorMessage = null;
    notifyListeners();
  }

  /// Set error state directly (used for voice input processing).
  void setError(String message) {
    _uiState = AppUIState.error;
    _errorMessage = message;
    notifyListeners();
  }
}
