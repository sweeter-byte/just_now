# Just Now

An Intent-Driven Generative UI (GenUI) System for Android that dynamically generates user interfaces based on user intent rather than pre-built layouts.

## Overview

Just Now demonstrates a revolutionary approach to mobile interface design where **"Form Follows Intent"**. The application features a desktop-resident floating interface called "The Orb" that listens to user intent and renders contextually-appropriate UI components in real-time.

This is a proof-of-concept (PoC) Walking Skeleton implementation showcasing the Server-Driven UI (SDUI) architecture pattern.

## Architecture

```
┌─────────────────────┐     HTTP/JSON      ┌─────────────────────┐
│   Flutter Client    │ ◄───────────────► │   FastAPI Backend   │
│   (Android App)     │                    │   (Python Server)   │
└─────────────────────┘                    └─────────────────────┘
         │                                          │
         ▼                                          ▼
┌─────────────────────┐                    ┌─────────────────────┐
│  GenUI Renderer     │                    │  Mock Scenarios     │
│  (Widget Registry)  │                    │  (JSON Data)        │
└─────────────────────┘                    └─────────────────────┘
```

## Tech Stack

| Layer | Technology | Version |
|-------|------------|---------|
| Frontend | Flutter | 3.0+ |
| State Management | Provider | ^6.1.1 |
| Backend | FastAPI | >=0.109.0 |
| Server | Uvicorn | >=0.27.0 |
| Validation | Pydantic V2 | >=2.5.0 |

## Project Structure

```
just_now/
├── frontend/                    # Flutter Android client
│   ├── lib/
│   │   ├── main.dart           # Entry point + HomeScreen
│   │   ├── core/               # State management & renderer
│   │   ├── models/             # Data models
│   │   ├── services/           # API communication
│   │   └── widgets/            # UI components
│   └── pubspec.yaml
├── backend/                     # FastAPI Python backend
│   ├── main.py                 # API endpoints
│   ├── schemas.py              # Pydantic models
│   ├── requirements.txt
│   └── data/
│       └── mock_scenarios.json # Demo data
├── doc/                         # Documentation
│   ├── SRS_JustNow.md          # Software Requirements
│   ├── HLD_JustNow.md          # High-Level Design
│   └── LLD_JustNow.md          # Low-Level Design
└── figures/                     # Architecture diagrams
```

## Features

### The Orb (Floating Action Button)
- Main interaction trigger for intent processing
- Visual feedback with loading states
- Central entry point for all user interactions

### GenUI Components
- **InfoCard**: Markdown-rendered content with styles (standard, highlight, warning)
- **ActionList**: Interactive list supporting deep links and API calls
- **MapView**: Location display with markers (PoC placeholder)

### State Management
- `Idle` → Waiting for user input
- `Thinking` → Processing API request
- `Rendering` → Displaying GenUI response
- `Error` → Showing error message (auto-reset)

## Getting Started

### Prerequisites
- Flutter SDK 3.0+
- Python 3.x
- Android emulator or device

### Backend Setup

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Frontend Setup

```bash
cd frontend
flutter pub get
flutter run
```

### Configuration

Update the backend URL in `frontend/lib/services/intent_service.dart` if needed:
```dart
static const String _baseUrl = 'http://10.0.2.2:8000'; // Android emulator
```

## API Reference

### Process Intent
```
POST /api/v1/intent/process
Content-Type: application/json

{
  "text": "I need a taxi"
}
```

### Health Check
```
GET /health
```

## Demo Scenarios

| Scenario | Trigger | Components |
|----------|---------|------------|
| Taxi | "taxi" keyword | MapView + ActionList |
| Code Demo | "code" keyword | InfoCard with Markdown |

Use the `X-Mock-Scenario` header to force a specific scenario during testing.

## Documentation

Detailed documentation is available in the `/doc` directory:
- [Software Requirements Specification](doc/SRS_JustNow.md)
- [High-Level Design](doc/HLD_JustNow.md)
- [Low-Level Design](doc/LLD_JustNow.md)

## License

This project is a proof-of-concept demonstration.
