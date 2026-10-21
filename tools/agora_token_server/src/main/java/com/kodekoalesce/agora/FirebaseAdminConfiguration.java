package com.kodekoalesce.agora;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.firestore.Firestore;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.cloud.FirestoreClient;
import java.io.IOException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@ConditionalOnProperty(prefix = "firebase.auth", name = "required", havingValue = "true")
public class FirebaseAdminConfiguration {
    @Bean
    FirebaseApp firebaseAdminApp(@Value("${firebase.project-id:}") String projectId)
            throws IOException {
        FirebaseOptions.Builder options = FirebaseOptions.builder()
                .setCredentials(GoogleCredentials.getApplicationDefault());
        if (!projectId.isBlank()) {
            options.setProjectId(projectId);
        }
        return FirebaseApp.initializeApp(options.build());
    }

    @Bean
    FirebaseAuth firebaseAuth(FirebaseApp firebaseAdminApp) {
        return FirebaseAuth.getInstance(firebaseAdminApp);
    }

    @Bean
    Firestore firestore(FirebaseApp firebaseAdminApp) {
        return FirestoreClient.getFirestore(firebaseAdminApp);
    }

    @Bean
    FirebaseRoomAccessService firebaseRoomAccessService(
            FirebaseAuth firebaseAuth,
            Firestore firestore) {
        return new FirebaseRoomAccessService(firebaseAuth, firestore);
    }
}
