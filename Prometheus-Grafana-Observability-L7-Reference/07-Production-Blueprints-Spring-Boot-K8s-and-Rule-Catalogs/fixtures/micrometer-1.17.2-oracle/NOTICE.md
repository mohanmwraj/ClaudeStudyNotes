# NOTICE — Micrometer 1.17.2 oracle output

`oracle.json` was produced by running `MicrometerOracle.java` and `LeOracle.java` (included here) on
JDK 25.0.4.1. They ran against the real Micrometer 1.17.2 `PrometheusMeterRegistry` (with
prometheus-metrics 1.7.0), using this folder's `CheckoutObservabilityConfig` and `CheckoutMetrics`
classes. Those classes were compiled with `javac --release 21 -Xlint:all -Werror` against the Spring Boot
4.1.2 BOM versions. All jars came from Maven Central, with SHA-1 checks.

`boot_micrometer_lab.py` compares its Python port of `PercentileHistogramBuckets` and of the Prometheus
naming convention against this file. Micrometer is Apache-2.0 licensed.
