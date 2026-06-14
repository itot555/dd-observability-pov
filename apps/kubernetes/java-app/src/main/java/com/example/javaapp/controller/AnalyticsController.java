package com.example.javaapp.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

@RestController
public class AnalyticsController {

    private static final Logger logger = LoggerFactory.getLogger(AnalyticsController.class);

    private final RestTemplate restTemplate;

    @Value("${app.python-api-url}")
    private String pythonApiUrl;

    public AnalyticsController(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    @GetMapping("/analytics")
    public ResponseEntity<String> analytics() {
        logger.info("GET /analytics - forwarding to Python API: {}/api/analytics", pythonApiUrl);
        try {
            String response = restTemplate.getForObject(pythonApiUrl + "/api/analytics", String.class);
            logger.info("GET /analytics - received response from Python API");
            return ResponseEntity.ok(response);
        } catch (HttpServerErrorException e) {
            logger.warn("GET /analytics - Python API returned {}, retrying after 500ms", e.getStatusCode());
            try {
                Thread.sleep(500);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
            }
            try {
                String response = restTemplate.getForObject(pythonApiUrl + "/api/analytics", String.class);
                logger.info("GET /analytics - retry succeeded");
                return ResponseEntity.ok(response);
            } catch (HttpServerErrorException e2) {
                logger.error("GET /analytics - retry also failed: {} {}", e2.getStatusCode(), e2.getResponseBodyAsString());
                return ResponseEntity.status(e2.getStatusCode()).body(e2.getResponseBodyAsString());
            } catch (RestClientException e2) {
                logger.error("GET /analytics - retry failed to reach Python API: {}", e2.getMessage());
                return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body("{\"error\":\"upstream_error\",\"message\":\"Python API unavailable\"}");
            }
        } catch (RestClientException e) {
            logger.error("GET /analytics - failed to reach Python API: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body("{\"error\":\"upstream_error\",\"message\":\"Python API unavailable\"}");
        }
    }

    @GetMapping("/analytics/summary")
    public ResponseEntity<String> analyticsSummary() {
        logger.info("GET /analytics/summary - forwarding to Python API: {}/api/analytics/summary", pythonApiUrl);
        try {
            String response = restTemplate.getForObject(pythonApiUrl + "/api/analytics/summary", String.class);
            logger.info("GET /analytics/summary - received response from Python API");
            return ResponseEntity.ok(response);
        } catch (HttpServerErrorException e) {
            logger.error("GET /analytics/summary - Python API returned error: {} {}", e.getStatusCode(), e.getResponseBodyAsString());
            return ResponseEntity.status(e.getStatusCode()).body(e.getResponseBodyAsString());
        } catch (RestClientException e) {
            logger.error("GET /analytics/summary - failed to reach Python API: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body("{\"error\":\"upstream_error\",\"message\":\"Python API unavailable\"}");
        }
    }
}
