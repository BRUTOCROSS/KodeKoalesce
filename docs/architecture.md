# KodeKoalesce architecture

This document describes the current project structure and its main user flows. It distinguishes Firebase-backed app features from the locally tested live-audio path.

## System design

```mermaid
flowchart LR
    person[App user]
    app[Flutter Android app]
    auth[Firebase Authentication]
    db[(Cloud Firestore)]
    token[Spring Boot Agora token service\nlocal development only]
    agora[Agora RTC]

    person --> app
    app -->|sign in / auth state| auth
    app -->|profiles, posts, follows, projects| db
    app -.->|request short-lived RTC token| token
    token -.->|validate access and issue token| agora
    app -.->|connect audio with token| agora
```

Solid connections are the ordinary Firebase app path. Dashed connections show the live-audio path, which currently requires the developer's local token service and is not available as a public hosted feature.

## Use cases

```mermaid
flowchart LR
    developer((Developer))
    auth([Create account or sign in])
    feed([Browse and publish posts])
    interact([Comment, react, save posts])
    discover([Search people and view profiles])
    follow([Follow or unfollow people])
    projects([Create and explore projects])
    contribute([Request or review contributions])
    settings([Manage account and privacy settings])
    rooms([Join a live audio room\nlocal service required])

    developer --> auth
    developer --> feed
    developer --> interact
    developer --> discover
    developer --> follow
    developer --> projects
    developer --> contribute
    developer --> settings
    developer -.-> rooms
```

## Sign-in and app navigation flow

```mermaid
flowchart TD
    start([Open app]) --> init[Initialize Firebase]
    init --> state{Authenticated?}
    state -- No --> sign[Sign in or create account]
    sign --> auth[Firebase Authentication]
    auth --> profile[Load or initialize user profile]
    state -- Yes --> shell[Open app shell]
    profile --> shell
    shell --> feed[Feed]
    shell --> projects[Projects]
    shell --> rooms[Rooms]
    shell --> profileTab[Profile]
    feed --> firestore[(Cloud Firestore)]
    projects --> firestore
    profileTab --> firestore
```

## Live-room join flow

```mermaid
sequenceDiagram
    actor User
    participant App as Flutter app
    participant Firestore
    participant Token as Spring Boot token service
    participant RTC as Agora RTC

    User->>App: Start or join room
    App->>Firestore: Read room and membership data
    Firestore-->>App: Room details
    App->>Token: Request token for room and user
    Note over Token: Local development service; not publicly hosted
    Token->>Firestore: Validate Firebase identity and room access (when configured)
    Token-->>App: Short-lived Agora token
    App->>RTC: Join audio channel
    RTC-->>App: Participant and audio events
```

## Main code areas

| Path | Responsibility |
| --- | --- |
| `lib/app/` | Authentication gate, navigation shell, and app-level UI |
| `lib/core/` | Shared theme and reusable widgets |
| `lib/features/feed/` | Feed, comments, and saved posts |
| `lib/features/profile/` | Profiles, discovery, follows, and external links |
| `lib/features/projects/` | Project pages, contribution requests, and notifications |
| `lib/features/rooms/` | Room listing and Agora voice-room UI |
| `lib/screens/` | Settings and remaining screens |
| `tools/agora_token_server/` | Spring Boot service that issues Agora RTC tokens |
| `firestore.rules` | Firestore authorization rules |

## Data and security notes

- Firebase Authentication identifies the signed-in app user.
- Cloud Firestore stores app data and enforces access through `firestore.rules`.
- The Agora App Certificate is a server secret. It belongs only in a protected server environment or local ignored `.env` file; never in Flutter code or Git.
- The local token service is for development. A public audio deployment needs production authentication, room-membership checks, protected secrets, and an appropriate hosting budget.
- Use test accounts and sample content in shared demos. Firebase quotas and rules apply to every build configured for that Firebase project.
