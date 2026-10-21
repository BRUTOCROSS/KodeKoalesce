package com.kodekoalesce.agora;

import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.Firestore;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import com.google.firebase.auth.FirebaseToken;
import java.util.concurrent.ExecutionException;

public class FirebaseRoomAccessService {
    private final FirebaseAuth firebaseAuth;
    private final Firestore firestore;

    FirebaseRoomAccessService(FirebaseAuth firebaseAuth, Firestore firestore) {
        this.firebaseAuth = firebaseAuth;
        this.firestore = firestore;
    }

    public String verifyFirebaseUser(String authorizationHeader) throws FirebaseAuthException {
        if (authorizationHeader == null || !authorizationHeader.startsWith("Bearer ")) {
            throw new IllegalArgumentException("Missing Firebase bearer token");
        }
        String idToken = authorizationHeader.substring("Bearer ".length()).trim();
        if (idToken.isEmpty()) {
            throw new IllegalArgumentException("Missing Firebase bearer token");
        }
        FirebaseToken decodedToken = firebaseAuth.verifyIdToken(idToken);
        return decodedToken.getUid();
    }

    public boolean isOpenRoomParticipant(String roomId, String firebaseUid)
            throws InterruptedException, ExecutionException {
        DocumentSnapshot room = firestore.collection("rooms")
                .document(roomId)
                .get()
                .get();
        if (!room.exists() || !"open".equals(room.getString("status"))) {
            return false;
        }

        return firestore.collection("rooms")
                .document(roomId)
                .collection("participants")
                .document(firebaseUid)
                .get()
                .get()
                .exists();
    }
}
