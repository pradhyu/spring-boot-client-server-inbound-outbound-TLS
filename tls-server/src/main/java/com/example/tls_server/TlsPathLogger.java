package com.example.tls_server;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;

@Component
public class TlsPathLogger implements CommandLineRunner {

    @Value("${server.ssl.certificate}")
    private Resource certificate;

    @Value("${server.ssl.certificate-private-key}")
    private Resource privateKey;

    @Override
    public void run(String... args) throws Exception {
        System.err.println(">>> [DEBUG] SERVER TLS CERT PATH: " + certificate.getURI().toString());
        System.err.println(">>> [DEBUG] SERVER TLS KEY PATH:  " + privateKey.getURI().toString());
    }
}
