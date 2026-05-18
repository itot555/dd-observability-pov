package com.example.javaapp.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

@RestController
public class DemoController {

    private static final Logger logger = LoggerFactory.getLogger(DemoController.class);

    private final RestTemplate restTemplate;
    private final RestTemplate longRunRestTemplate;

    @Value("${app.python-api-url}")
    private String pythonApiUrl;

    public DemoController(RestTemplate restTemplate,
                          @Qualifier("longRunRestTemplate") RestTemplate longRunRestTemplate) {
        this.restTemplate = restTemplate;
        this.longRunRestTemplate = longRunRestTemplate;
    }

    @GetMapping("/hello")
    public ResponseEntity<String> hello() {
        logger.info("GET /hello - forwarding to Python API: {}/api/data", pythonApiUrl);
        try {
            String response = restTemplate.getForObject(pythonApiUrl + "/api/data", String.class);
            logger.info("GET /hello - received response from Python API");
            return ResponseEntity.ok(response);
        } catch (RestClientException e) {
            logger.error("GET /hello - failed to reach Python API: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body("{\"error\":\"upstream_error\",\"message\":\"Python API unavailable\"}");
        }
    }

    @GetMapping("/error")
    public ResponseEntity<String> error() {
        logger.info("GET /error - forwarding to Python API: {}/api/error", pythonApiUrl);
        try {
            String response = restTemplate.getForObject(pythonApiUrl + "/api/error", String.class);
            logger.info("GET /error - received response from Python API");
            return ResponseEntity.ok(response);
        } catch (HttpServerErrorException e) {
            logger.error("GET /error - Python API returned error: {} {}", e.getStatusCode(), e.getResponseBodyAsString());
            return ResponseEntity.status(e.getStatusCode()).body(e.getResponseBodyAsString());
        } catch (RestClientException e) {
            logger.error("GET /error - failed to reach Python API: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body("{\"error\":\"upstream_error\",\"message\":\"Python API unavailable\"}");
        }
    }

    @GetMapping("/timeout")
    public ResponseEntity<String> timeout() {
        logger.info("GET /timeout - forwarding to Python API: {}/api/timeout", pythonApiUrl);
        try {
            String response = restTemplate.getForObject(pythonApiUrl + "/api/timeout", String.class);
            logger.info("GET /timeout - received response from Python API");
            return ResponseEntity.ok(response);
        } catch (RestClientException e) {
            logger.error("GET /timeout - upstream timeout calling Python API: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.GATEWAY_TIMEOUT)
                .body("{\"error\":\"upstream_timeout\",\"message\":\"Python API did not respond in time\"}");
        }
    }

    @GetMapping("/db/normal")
    public ResponseEntity<String> dbNormal() {
        logger.info("GET /db/normal - forwarding to Python API: {}/api/db/normal", pythonApiUrl);
        try {
            String response = restTemplate.getForObject(pythonApiUrl + "/api/db/normal", String.class);
            logger.info("GET /db/normal - received response from Python API");
            return ResponseEntity.ok(response);
        } catch (RestClientException e) {
            logger.error("GET /db/normal - failed to reach Python API: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body("{\"error\":\"upstream_error\",\"message\":\"Python API unavailable\"}");
        }
    }

    @GetMapping("/db/n1")
    public ResponseEntity<String> dbN1() {
        logger.info("GET /db/n1 - forwarding to Python API: {}/api/db/n1", pythonApiUrl);
        try {
            String response = restTemplate.getForObject(pythonApiUrl + "/api/db/n1", String.class);
            logger.info("GET /db/n1 - received response from Python API");
            return ResponseEntity.ok(response);
        } catch (RestClientException e) {
            logger.error("GET /db/n1 - failed to reach Python API: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body("{\"error\":\"upstream_error\",\"message\":\"Python API unavailable\"}");
        }
    }

    @GetMapping("/db/long-run")
    public ResponseEntity<String> dbLongRun() {
        logger.info("GET /db/long-run - forwarding to Python API: {}/api/db/long-run (60s timeout)", pythonApiUrl);
        try {
            String response = longRunRestTemplate.getForObject(pythonApiUrl + "/api/db/long-run", String.class);
            logger.info("GET /db/long-run - received response from Python API");
            return ResponseEntity.ok(response);
        } catch (RestClientException e) {
            logger.error("GET /db/long-run - upstream error calling Python API: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.GATEWAY_TIMEOUT)
                .body("{\"error\":\"upstream_timeout\",\"message\":\"Python API did not respond in time\"}");
        }
    }
}
