# Agora token service (Spring Boot)

This Spring Boot service issues short-lived RTC tokens for the app's Firestore room IDs. The Agora App Certificate stays in the ignored local `.env` file during development and must be stored in Secret Manager when hosted. It is never included in Flutter.

## Requirements

- JDK 17 or newer
- Maven 3.6.3 or newer

## Configure and run

1. Keep the real Agora App ID and Primary Certificate in this folder's `.env` file. Do not commit or share that file.
2. From this folder, run:

   ```sh
   mvn spring-boot:run
   ```

The server listens on `127.0.0.1:3000`. It provides `GET /ping` and `GET /rtc?channel=<room-id>&uid=<numeric-user-id>`; the RTC response contains `appId`, `token`, `uid`, and `expiresIn`.

For a USB-connected Android phone, open another terminal and run:

```sh
adb reverse tcp:3000 tcp:3000
```

The Flutter app already requests `http://127.0.0.1:3000`, so no URL change is needed. Keep the Spring server running while testing.

## Temporary same-Wi-Fi testing on a second phone

The default loopback binding is safer and only works with USB port forwarding. For a trusted local Wi-Fi test without USB debugging, restart the service with `SERVER_ADDRESS=0.0.0.0 mvn spring-boot:run`, then build the debug APK with `flutter build apk --debug --dart-define=AGORA_TOKEN_SERVER_URL=http://<laptop-lan-ip>:3000`. Replace `<laptop-lan-ip>` with the computer's private Wi-Fi IP address and install/share that APK with the second phone. Keep both phones and the computer on the same Wi-Fi. Stop the server after the test; this development token endpoint does not authenticate Firebase users or check room membership and must not be left exposed on an untrusted network.

## Deploying to Google Cloud Run

The service supports Cloud Run source deployment from this directory. Public deployments must set `FIREBASE_AUTH_REQUIRED=true`; in that mode, `/rtc` verifies the Firebase ID token, confirms the user is an active participant in an open Firestore room, and checks that the requested Agora UID belongs to that Firebase user. The Flutter app sends its current Firebase ID token automatically.

1. Make sure your Google Cloud project is linked to a billing account. Cloud Run has a monthly free usage tier, but this is not a guaranteed $0 bill: usage outside the free tier, network traffic, builds, or artifact storage may incur charges. Configure a budget alert before deployment.
2. Enable Cloud Run, Cloud Build, Artifact Registry, Secret Manager, and Cloud Firestore APIs in the Google Cloud project linked to Firebase.
3. Create a Secret Manager secret named `AGORA_APP_CERTIFICATE` containing the Agora Primary Certificate. Do not put the certificate in this repository or in the Flutter app.
4. Give the Cloud Run service identity access to that secret (`Secret Manager Secret Accessor`) and Firestore (`Cloud Datastore User`).
5. From this directory, deploy with the Firebase project ID and secret configured. Allow unauthenticated Cloud Run ingress because mobile clients authenticate with Firebase ID tokens at the application layer:

   ```sh
   gcloud run deploy kodekoalesce-agora-token \
     --source . \
     --region asia-south1 \
     --allow-unauthenticated \
     --max-instances=1 \
     --memory 512Mi \
     --set-env-vars=SERVER_ADDRESS=0.0.0.0,FIREBASE_AUTH_REQUIRED=true,FIREBASE_PROJECT_ID=kodekoalesce,AGORA_APP_ID=ac8e433e1703464e8787e5d99311201b \
     --set-secrets=AGORA_APP_CERTIFICATE=AGORA_APP_CERTIFICATE:latest
   ```

6. Copy the HTTPS service URL printed by `gcloud` and build the Flutter app with it:

   ```sh
   flutter build apk --debug --dart-define=AGORA_TOKEN_SERVER_URL=https://YOUR-CLOUD-RUN-URL
   ```

Set `YOUR-CLOUD-RUN-URL` to the exact service URL. No USB reverse or same-Wi-Fi connection is needed after the app is installed.

For local development, `FIREBASE_AUTH_REQUIRED` defaults to `false` so USB testing keeps working without Google credentials. Never deploy with this setting disabled.
