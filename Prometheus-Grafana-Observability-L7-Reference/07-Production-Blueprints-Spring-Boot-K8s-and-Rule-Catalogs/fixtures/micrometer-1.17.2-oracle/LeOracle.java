package com.acme.checkout.observability;

import io.micrometer.core.instrument.Timer;
import io.micrometer.prometheusmetrics.PrometheusConfig;
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry;
import java.time.Duration;

public class LeOracle {
    public static void main(String[] args) {
        PrometheusMeterRegistry reg = new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);
        reg.config().meterFilter(new CheckoutObservabilityConfig().checkoutLatencyHistograms());
        new CheckoutMetrics(reg).timePsp("stripe", () -> 1);
        Timer.builder("http.server.requests").publishPercentileHistogram().register(reg).record(Duration.ofMillis(20));
        for (String p : new String[] {"http_server_requests_seconds_bucket", "checkout_psp_latency_seconds_bucket"}) {
            StringBuilder sb = new StringBuilder(p + ":");
            reg.scrape().lines().filter(l -> l.startsWith(p + "{")).forEach(l -> {
                int i = l.indexOf("le=\"") + 4;
                sb.append(' ').append(l, i, l.indexOf('"', i));
            });
            System.out.println(sb);
        }
    }
}
