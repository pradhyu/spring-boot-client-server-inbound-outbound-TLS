package com.example.tls_client;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

@RestController
public class ClientProxyController {

    private static final Logger log = LoggerFactory.getLogger(ClientProxyController.class);

    @Autowired
    private WebClient webClient;

    @GetMapping("/call-server")
    public Mono<String> callServer() {
        log.info(">>> [HOP 1] Received request on Client (8444). Initiating [HOP 2] Outbound TLS call to Server (8443)...");
        
        return webClient.get()
                .uri("https://localhost:8443/hello")
                .retrieve()
                .bodyToMono(String.class)
                .doOnNext(res -> log.info("<<< [HOP 2 SUCCESS] Received response from Server: '{}'", res))
                .map(response -> "Client received: " + response)
                .doOnError(err -> log.error("!!! [HOP 2 FAILURE] Outbound TLS call failed: {}", err.getMessage()));
    }
}
