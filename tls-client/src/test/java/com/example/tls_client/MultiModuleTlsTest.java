package com.example.tls_client;

import com.example.tls_server.TlsServerApplication;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Import;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.test.StepVerifier;

@SpringBootTest(
    classes = {TlsServerApplication.class, TlsClientApplication.class},
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT
)
class MultiModuleTlsTest {

    @LocalServerPort
    private int port;

    @Autowired
    private WebClient webClient;

    @Test
    void testTlsConnectivity() {
        String url = "https://localhost:" + port + "/hello";
        
        webClient.get()
                .uri(url)
                .retrieve()
                .bodyToMono(String.class)
                .as(StepVerifier::create)
                .expectNext("Hello from TLS secured server!")
                .verifyComplete();
    }
}
