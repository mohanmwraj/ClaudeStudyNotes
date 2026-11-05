package com.acme.checkout.observability;

import io.micrometer.core.instrument.Timer;
import io.micrometer.core.instrument.distribution.DistributionStatisticConfig;
import io.micrometer.core.instrument.distribution.PercentileHistogramBuckets;
import io.micrometer.prometheusmetrics.PrometheusConfig;
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry;
import java.time.Duration;

public class MicrometerOracle {
    public static void main(String[] args) {
        System.out.println("all_buckets=" + PercentileHistogramBuckets.buckets(
            DistributionStatisticConfig.builder().minimumExpectedValue(1.0).maximumExpectedValue(Double.POSITIVE_INFINITY).build()).size());
        System.out.println("timer_default_buckets=" + PercentileHistogramBuckets.buckets(
            DistributionStatisticConfig.builder().minimumExpectedValue(1e6).maximumExpectedValue(3e10).build()).size());
        System.out.println("checkout_buckets=" + PercentileHistogramBuckets.buckets(
            DistributionStatisticConfig.builder().minimumExpectedValue(5e6).maximumExpectedValue(1e10).build()).size());
        PrometheusMeterRegistry reg = new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);
        reg.config().meterFilter(new CheckoutObservabilityConfig().checkoutLatencyHistograms());
        CheckoutMetrics m = new CheckoutMetrics(reg);
        m.orderCompleted(CheckoutMetrics.PaymentMethod.CARD, CheckoutMetrics.Outcome.SUCCESS, 3);
        m.timePsp("stripe", () -> 1);
        m.timePsp("paypal-typo", () -> 1);
        Timer.builder("http.server.requests").publishPercentileHistogram().tag("uri", "/x").register(reg).record(Duration.ofMillis(20));
        String scrape = reg.scrape();
        System.out.println("http_buckets=" + scrape.lines().filter(l -> l.startsWith("http_server_requests_seconds_bucket")).count());
        System.out.println("psp_buckets_per_series=" + scrape.lines().filter(l -> l.startsWith("checkout_psp_latency_seconds_bucket{") && l.contains("psp=\"stripe\"")).count());
        scrape.lines().filter(l -> !l.startsWith("#") && !l.contains("_bucket{")).sorted().forEach(System.out::println);
    }
}
