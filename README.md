# KodeKoalesce

KodeKoalesce is a Flutter community app for developers to share updates, discover people, and collaborate on projects.

## What it does

- **Feed:** browse and publish community posts, react, comment, and save posts.
- **People and profiles:** search for developers, view profiles, follow people, and open profile links.
- **Projects:** create project pages, discuss contributions, and review project updates.
- **Rooms:** join live audio conversations through Agora. The token service is currently for local development only, so live audio is not available in the public demo build.
- **Account:** sign in with Firebase Authentication and manage basic privacy settings.

## Screenshots and demo

Screenshots and an installable Android demo will be added to the first GitHub Release.

## Built with

- Flutter and Dart
- Firebase Authentication
- Cloud Firestore
- Spring Boot and Agora RTC for locally tested live audio

See [the architecture and diagrams](docs/architecture.md) for the system overview, use cases, and key flows.

## Run locally

### Requirements

- Flutter SDK compatible with the version in `pubspec.yaml`
- Android Studio or Android SDK for Android builds
- A configured Firebase project with Authentication and Cloud Firestore enabled

### Setup

1. Clone this repository and open its folder.
2. Configure Firebase for your own project. For Android, place your Firebase-generated `google-services.json` at `android/app/google-services.json`. Do not use a production project containing private or real user data for experiments.
3. In the project folder, run:

   ```sh
   flutter pub get
   flutter run
   ```

4. Publish the Firestore rules from `firestore.rules` using the Firebase Console or Firebase CLI before testing database features.

Firebase usage is subject to the project's plan quotas and security rules. Never commit private certificates, service-account credentials, signing keys, or local `.env` files.

## Build an Android APK

For a local development build:

```sh
flutter build apk --debug
```

The output is `build/app/outputs/flutter-apk/app-debug.apk`. A debug APK is intended for testing, not a production store release. A publicly distributed build should use a separately configured release signing key, which must stay private and out of Git.

## Live audio status

The Spring Boot Agora token service is included for local development and is not deployed. It uses an Agora App Certificate, which must remain server-side. Do not put the certificate in the Flutter app or commit the local `.env` file. See [the token service notes](tools/agora_token_server/README.md) for USB-connected local testing. Public live audio needs a secured hosted token service and may incur provider or cloud costs, so it is outside this no-cost demo.

## Privacy and demo data

Use test accounts and non-sensitive sample content. The app communicates with the Firebase project configured at build time. Anyone with a demo build may be able to create data in that project's collections if its rules allow it. Review and configure Firebase Authentication, Firestore rules, and project quotas before sharing a build broadly.

## Project structure

```text
lib/                         Flutter application
  app/                       App shell and authentication gate
  core/                      Shared theme and widgets
  features/                  Feed, profiles, projects, and rooms
  models/                    Shared data models
  screens/                   Account settings and app screens
tools/agora_token_server/    Local Spring Boot token service
firestore.rules              Firestore security rules
docs/architecture.md         System overview and Mermaid diagrams
```

## License

No open-source license has been selected yet. Until one is added, the source is available for review but is not licensed for reuse.
