# Lisnai iOS Setup Guide

## Prerequisites

1. **Xcode 17+** installed
2. **Homebrew** installed
3. **XcodeGen** installed:
   ```bash
   brew install xcodegen
   ```

## Firebase Setup

### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project"
3. Enter project name: `Lisnai`
4. Enable/disable Google Analytics (optional)
5. Click "Create project"

### 2. Add iOS App to Firebase

1. In Firebase Console, click "Add app" → iOS
2. Enter bundle ID: `com.lisnai.Lisnai`
3. Enter app nickname: `Lisnai iOS`
4. Download `GoogleService-Info.plist`
5. Place it in `/Lisnai/` folder (same level as `LisnaiApp.swift`)

### 3. Enable Authentication

1. In Firebase Console → Authentication → Sign-in method
2. Enable **Google** sign-in:
   - Click "Google"
   - Toggle "Enable"
   - Add your support email
   - Click "Save"
3. Enable **Apple** sign-in (optional for now):
   - Click "Apple"
   - Toggle "Enable"
   - Click "Save"

## Google Cloud Console Setup

### 1. Configure OAuth Consent Screen

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your Firebase project
3. Go to **APIs & Services** → **OAuth consent screen**
4. Choose "External" user type
5. Fill in:
   - App name: `Lisnai`
   - User support email: your email
   - Developer contact: your email
6. Add scopes: `email`, `profile`, `openid`
7. Save and continue

### 2. Get OAuth Client ID

1. Go to **APIs & Services** → **Credentials**
2. Find the "iOS client" (auto-created by Firebase)
3. Note the **Client ID** - you'll need this

### 3. Update project.yml

Open `project.yml` and replace the URL scheme placeholder:

```yaml
CFBundleURLTypes:
  - CFBundleURLSchemes:
      - "com.googleusercontent.apps.YOUR_ACTUAL_CLIENT_ID"
```

Replace `YOUR_ACTUAL_CLIENT_ID` with the iOS client ID from Google Cloud Console.
It should look like: `com.googleusercontent.apps.123456789-abcdefghijk.apps.googleusercontent.com`

**Tip:** You can find this as `REVERSED_CLIENT_ID` in your `GoogleService-Info.plist` file.

## Generate Xcode Project

Run the following command in the `/Ios` directory:

```bash
cd /Users/rahul/Developer/lisn/Ios
xcodegen generate
```

This will create `Lisnai.xcodeproj` from `project.yml`.

## Open and Build

```bash
open Lisnai.xcodeproj
```

1. Select your Development Team in Signing & Capabilities
2. Build and run (Cmd + R)

## Project Structure

```
Ios/
├── project.yml              # XcodeGen project spec
├── Lisnai/
│   ├── LisnaiApp.swift      # App entry point
│   ├── GoogleService-Info.plist  # Firebase config (you add this)
│   ├── Models/              # SwiftData models
│   ├── Services/            # Business logic
│   ├── Views/               # SwiftUI views
│   │   ├── Auth/            # Login/signup
│   │   ├── Chat/            # AI chat
│   │   └── ...
│   └── ...
├── RecordingActivityExtension/  # Live Activity widget
└── SETUP.md                 # This file
```

## Regenerating Project

After modifying `project.yml`, regenerate the Xcode project:

```bash
xcodegen generate
```

**Tip:** Add `.xcodeproj` to `.gitignore` and only commit `project.yml`. This prevents merge conflicts.

## Troubleshooting

### "No such module 'FirebaseCore'"

1. Make sure you ran `xcodegen generate`
2. Open Xcode and let it fetch Swift packages
3. Build once to index packages

### Google Sign In not working

1. Check `GoogleService-Info.plist` is in the project
2. Verify URL scheme matches `REVERSED_CLIENT_ID`
3. Ensure OAuth consent screen is configured in Google Cloud Console

### "Target is not foreground" for Live Activity

Live Activities can only be started when app is in foreground. The recording flow handles this automatically.
