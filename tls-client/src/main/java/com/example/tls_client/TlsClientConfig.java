package com.example.tls_client;

import io.netty.handler.ssl.SslContext;
import io.netty.handler.ssl.SslContextBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.http.client.HttpClient;

import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.Collection;

@Configuration
public class TlsClientConfig {

        @Value("classpath:servers-trust.crt")
        private Resource trustCertificate;

        @Bean
        public WebClient webClient() throws Exception {
                CertificateFactory cf = CertificateFactory.getInstance("X.509");

                // Load and log ALL certificates from the combined PEM bundle
                Collection<? extends java.security.cert.Certificate> certs = cf
                                .generateCertificates(trustCertificate.getInputStream());

                System.err.println(">>> [DEBUG] CLIENT PROXY LOADING TRUST CERTS (Combined Bundle):");
                System.err.println("    PATH:   " + trustCertificate.getURI().toString());
                System.err.println("    COUNT:  " + certs.size() + " certificate(s)");
                int i = 1;
                for (java.security.cert.Certificate c : certs) {
                        X509Certificate x509 = (X509Certificate) c;
                        System.err.println("    [" + i + "] SUBJECT: " + x509.getSubjectX500Principal());
                        System.err.println("    [" + i + "] ISSUER:  " + x509.getIssuerX500Principal());
                        i++;
                }

                SslContext sslContext = SslContextBuilder.forClient()
                                .keyManager(
                                                TlsClientConfig.class.getResourceAsStream("/client.crt"),
                                                TlsClientConfig.class.getResourceAsStream("/client.key"))
                                .trustManager(trustCertificate.getInputStream())
                                .build();

                HttpClient httpClient = HttpClient.create()
                                .secure(sslContextSpec -> sslContextSpec.sslContext(sslContext));

                return WebClient.builder()
                                .clientConnector(new ReactorClientHttpConnector(httpClient))
                                .build();
        }
}
