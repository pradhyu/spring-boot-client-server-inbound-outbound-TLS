package com.example.tls_client;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

@RestController
public class ClientProxyController {

    @Autowired
    private WebClient webClient;

    @GetMapping("/call-server")
    public Mono<String> callServer() {
        // Calling server on port 8443
        return webClient.get()
                .uri("https://localhost:8443/hello")
                .retrieve()
                .bodyToMono(String.class)
                .map(response -> "Client received: " + response);
    }
}
