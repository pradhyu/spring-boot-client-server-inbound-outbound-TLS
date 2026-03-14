package com.example.tls_user;

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

@Configuration
public class TlsUserConfig {

    @Value("classpath:client-trust.crt")
    private Resource trustCertificate;

    @Bean
    public WebClient webClient() throws Exception {
        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        X509Certificate cert = (X509Certificate) cf.generateCertificate(trustCertificate.getInputStream());
        
        System.err.println(">>> [DEBUG] USER APP LOADING TRUST CERT:");
        System.err.println("    PATH:   " + trustCertificate.getURI().toString());
        System.err.println("    SUBJECT: " + cert.getSubjectX500Principal());
        System.err.println("    ISSUER:  " + cert.getIssuerX500Principal());
        
        SslContext sslContext = SslContextBuilder.forClient()
                .trustManager(trustCertificate.getInputStream())
                .build();

        HttpClient httpClient = HttpClient.create()
                .secure(sslContextSpec -> sslContextSpec.sslContext(sslContext));

        return WebClient.builder()
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .build();
    }
}
