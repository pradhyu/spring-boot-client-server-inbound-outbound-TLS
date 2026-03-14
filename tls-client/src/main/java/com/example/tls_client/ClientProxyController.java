package com.example.tls_client;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

@RestController
public class ClientProxyController {

    private static final Logger log = LoggerFactory.getLogger(ClientProxyController.class);

    @Autowired
    private WebClient webClient;

    @Value("${server-a.url}")
    private String serverAUrl;

    @Value("${server-b.url}")
    private String serverBUrl;

    @GetMapping("/call-server")
    public Mono<String> callServer() {
        String inboundUrl = "https://localhost:8444/call-server";

        log.info(">>> [HOP 1] Received request on Client ({}). Calling Server-A ({}) and Server-B ({}) in parallel...",
                inboundUrl, serverAUrl, serverBUrl);

        Mono<String> callA = webClient.get()
                .uri(serverAUrl)
                .retrieve()
                .bodyToMono(String.class)
                .doOnNext(res -> log.info("<<< [HOP 2a SUCCESS] Server-A response: '{}'", res))
                .doOnError(err -> log.error("!!! [HOP 2a FAILURE] Server-A call to {} failed: {}", serverAUrl,
                        err.getMessage()));

        Mono<String> callB = webClient.get()
                .uri(serverBUrl)
                .retrieve()
                .bodyToMono(String.class)
                .doOnNext(res -> log.info("<<< [HOP 2b SUCCESS] Server-B response: '{}'", res))
                .doOnError(err -> log.error("!!! [HOP 2b FAILURE] Server-B call to {} failed: {}", serverBUrl,
                        err.getMessage()));

        return Mono.zip(callA, callB)
                .map(tuple -> "Server-A says: " + tuple.getT1() + " | Server-B says: " + tuple.getT2())
                .doOnNext(combined -> log.info("<<< [COMBINED RESPONSE] {}", combined));
    }
}
