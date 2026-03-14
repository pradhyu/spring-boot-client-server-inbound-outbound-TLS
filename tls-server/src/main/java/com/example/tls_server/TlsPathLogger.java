package com.example.tls_server;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;

@Component
public class TlsPathLogger implements CommandLineRunner {

    @Value("${server.ssl.certificate}")
    private Resource certificate;

    @Value("${server.ssl.certificate-private-key}")
    private Resource privateKey;

    @Override
    public void run(String... args) throws Exception {
        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        X509Certificate cert = (X509Certificate) cf.generateCertificate(certificate.getInputStream());

        System.err.println(">>> [DEBUG] SERVER IDENTITY CERT:");
        System.err.println("    PATH:    " + certificate.getURI().toString());
        System.err.println("    KEY:     " + privateKey.getURI().toString());
        System.err.println("    SUBJECT: " + cert.getSubjectX500Principal());
        System.err.println("    ISSUER:  " + cert.getIssuerX500Principal());
    }
}
