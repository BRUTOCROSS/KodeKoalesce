package com.kodekoalesce.agora;

import io.agora.media.RtcTokenBuilder2;
import io.agora.media.RtcTokenBuilder2.Role;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AgoraTokenController {
    private static final int TOKEN_LIFETIME_SECONDS = 60 * 60;
    private static final int MAX_AGORA_UID = 2_147_483_647;

    private final String appId;
    private final String appCertificate;
    private final boolean firebaseAuthRequired;
    private final FirebaseRoomAccessService firebaseRoomAccess;

    public AgoraTokenController(
            @Value("${agora.app-id:}") String appId,
            @Value("${agora.app-certificate:}") String appCertificate,
            @Value("${firebase.auth.required:false}") boolean firebaseAuthRequired,
            org.springframework.beans.factory.ObjectProvider<FirebaseRoomAccessService>
                    firebaseRoomAccessProvider) {
        this.appId = appId;
        this.appCertificate = appCertificate;
        this.firebaseAuthRequired = firebaseAuthRequired;
        this.firebaseRoomAccess = firebaseRoomAccessProvider.getIfAvailable();
    }

    @GetMapping("/ping")
    public Map<String, String> ping() {
        return Map.of("message", "pong");
    }

    @GetMapping("/rtc")
    public ResponseEntity<?> createRtcToken(
            @RequestParam String channel,
            @RequestParam int uid,
            @RequestHeader(value = HttpHeaders.AUTHORIZATION, required = false)
                    String authorizationHeader) {
        if (channel.length() > 64 || !channel.matches("[A-Za-z0-9_-]{1,64}")) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid channel name"));
        }
        if (uid < 1 || uid > MAX_AGORA_UID) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid numeric user ID"));
        }
        if (firebaseAuthRequired) {
            if (firebaseRoomAccess == null) {
                return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                        .body(Map.of("error", "Firebase authorization is not configured"));
            }
            final String firebaseUid;
            try {
                firebaseUid = firebaseRoomAccess.verifyFirebaseUser(authorizationHeader);
            } catch (IllegalArgumentException exception) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(Map.of("error", "A valid Firebase sign-in is required"));
            } catch (com.google.firebase.auth.FirebaseAuthException exception) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(Map.of("error", "A valid Firebase sign-in is required"));
            }
            if (uidFromFirebaseId(firebaseUid) != uid) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "The requested Agora user ID is invalid"));
            }
            try {
                if (!firebaseRoomAccess.isOpenRoomParticipant(channel, firebaseUid)) {
                    return ResponseEntity.status(HttpStatus.FORBIDDEN)
                            .body(Map.of("error", "Join an open room before requesting a token"));
                }
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                        .body(Map.of("error", "Could not verify room membership"));
            } catch (ExecutionException exception) {
                return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                        .body(Map.of("error", "Could not verify room membership"));
            }
        }
        if (appId.isBlank() || appCertificate.isBlank()) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(Map.of("error", "Agora token service is not configured"));
        }

        try {
            var tokenBuilder = new RtcTokenBuilder2();
            String token = tokenBuilder.buildTokenWithUid(
                    appId,
                    appCertificate,
                    channel,
                    uid,
                    Role.ROLE_PUBLISHER,
                    TOKEN_LIFETIME_SECONDS,
                    TOKEN_LIFETIME_SECONDS);
            if (token == null || token.isBlank()) {
                throw new IllegalStateException("Agora returned an empty token");
            }

            return ResponseEntity.ok(new TokenResponse(
                    appId, token, uid, TOKEN_LIFETIME_SECONDS));
        } catch (RuntimeException exception) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Could not create room token"));
        }
    }

    private record TokenResponse(String appId, String token, int uid, int expiresIn) {}

    private int uidFromFirebaseId(String value) {
        int hash = 0x811c9dc5;
        for (int index = 0; index < value.length(); index++) {
            hash ^= value.charAt(index);
            hash *= 0x01000193;
        }
        int uid = hash & 0x7fffffff;
        return uid == 0 ? 1 : uid;
    }
}
