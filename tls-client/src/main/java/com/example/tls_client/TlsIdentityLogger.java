package com.example.tls_client;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;

@Component
public class TlsIdentityLogger implements CommandLineRunner {

    @Value("${server.ssl.certificate}")
    private Resource certificate;

    @Value("${server.ssl.certificate-private-key}")
    private Resource privateKey;

    @Override
    public void run(String... args) throws Exception {
        System.out.println(">>> [DEBUG] CLIENT IDENTITY (Inbound):");
        System.out.println("    CERT (Public):  " + certificate.getURI().toString());
        System.out.println("    KEY  (Private): " + privateKey.getURI().toString());
    }
}
