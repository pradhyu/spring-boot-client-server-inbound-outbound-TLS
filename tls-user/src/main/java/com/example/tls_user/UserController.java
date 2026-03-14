package com.example.tls_user;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

@RestController
public class UserController {

    private static final Logger log = LoggerFactory.getLogger(UserController.class);

    @Autowired
    private WebClient webClient;

    @GetMapping("/test-full-chain")
    public Mono<String> testChain() {
        String targetUrl = "https://localhost:8444/call-server";
        log.info(">>> [USER APP] Initiating request to Client API ({})", targetUrl);

        return webClient.get()
                .uri(targetUrl)
                .retrieve()
                .bodyToMono(String.class)
                .doOnNext(res -> log.info("<<< [USER APP SUCCESS] Received response via Client API: '{}'", res))
                .map(res -> "UserApp received: " + res)
                .doOnError(err -> log.error("!!! [USER APP FAILURE] Call to {} failed: {}", targetUrl, err.getMessage()));
    }
}
