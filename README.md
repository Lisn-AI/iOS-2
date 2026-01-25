# Lisnai

An iOS 26 app that records your day and creates a searchable, AI-powered memory of your life.

## Features

- 🎙️ **Background Audio Recording**: Record throughout your day with screen off
- 📍 **Geofence Triggers**: Get reminded to start recording when you leave home
- 🧠 **On-Device Transcription**: Uses iOS 26 SpeechAnalyzer for $0-cost transcription
- 🤖 **AI Summarization**: Daily summaries using Apple Intelligence Foundation Models
- 🔒 **Privacy First**: All data stored locally on-device by default
- ☁️ **Optional Cloud Backup**: Upgrade to sync across devices

## Requirements

- iOS 26.0+
- Xcode 17.0+
- Swift 6.0+
- iPhone 11 or newer (iPhone 15 Pro+ for Apple Intelligence features)

## Setup

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`.

### 1. Install XcodeGen (if not already installed)

```bash
brew install xcodegen
```

### 2. Generate the Xcode Project

```bash
xcodegen generate
```

This will create `Lisnai.xcodeproj` from the `project.yml` configuration.

### 3. Open in Xcode

```bash
open Lisnai.xcodeproj
```

### 4. Add Your Development Team

1. Select the project in Xcode
2. Go to Signing & Capabilities
3. Select your Team from the dropdown

Or edit `project.yml` and add your Team ID:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: "YOUR_TEAM_ID_HERE"
```

Then regenerate: `xcodegen generate`

## Project Structure

```
Lisnai/
├── Services/           # Core business logic
│   ├── RecordingManager.swift
│   ├── LocationManager.swift
│   └── TranscriptionService.swift (TODO)
├── Views/             # SwiftUI views
│   └── ContentView.swift
├── ViewModels/        # View models (TODO)
├── Models/            # Data models (TODO)
└── Assets.xcassets/   # App assets
```

## TODO

- [ ] Implement iOS 26 SpeechAnalyzer transcription
- [ ] Add Apple Intelligence summarization
- [ ] Build search functionality
- [ ] Add cloud backup with iCloud
- [ ] Implement speaker diarization (premium feature)
- [ ] Add daily recap notifications
- [ ] Build web interface for cloud tier

## Privacy & Permissions

The app requires the following permissions:

- **Microphone**: To record audio throughout the day
- **Location (Always)**: To trigger recording reminders via geofencing
- **Speech Recognition**: To transcribe recordings on-device
- **Notifications**: To remind you to start/stop recording

All permissions are clearly explained to users with usage descriptions in Info.plist.

## License

TBD
