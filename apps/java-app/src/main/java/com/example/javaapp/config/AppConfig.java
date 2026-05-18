package com.example.javaapp.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

@Configuration
public class AppConfig {

    @Value("${app.http.connect-timeout:5000}")
    private int connectTimeout;

    @Value("${app.http.read-timeout:5000}")
    private int readTimeout;

    @Value("${app.http.long-run-read-timeout:60000}")
    private int longRunReadTimeout;

    @Bean
    public RestTemplate restTemplate() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(connectTimeout);
        factory.setReadTimeout(readTimeout);
        return new RestTemplate(factory);
    }

    @Bean(name = "longRunRestTemplate")
    public RestTemplate longRunRestTemplate() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(connectTimeout);
        factory.setReadTimeout(longRunReadTimeout);
        return new RestTemplate(factory);
    }
}
