# OpenTelemetry Rage Instrumentation

The OpenTelemetry Rage instrumentation provides automatic observability for [Rage](https://github.com/rage-rb/rage), a fiber-based framework with Rails-compatible syntax.

This instrumentation enables comprehensive tracing and logging for Rage applications:

* Creates spans for HTTP requests, WebSocket messages, SSE streams, event subscribers, and deferred tasks
* Propagates OpenTelemetry context across fibers created via `Fiber.schedule` and deferred tasks
* Enriches logs with trace and span IDs for correlated observability
* Publishes GC pressure gauges by periodically sampling `GC.stat`

## How do I get started?

Add the required gems to your Gemfile:

```console
bundle add opentelemetry-sdk opentelemetry-instrumentation-rage
```

## Usage

To use the instrumentation, call `use` with the name of the instrumentation:

```ruby
OpenTelemetry::SDK.configure do |c|
  c.use 'OpenTelemetry::Instrumentation::Rage'
end
```

Alternatively, you can also call `use_all` to install all the available instrumentation.

```ruby
OpenTelemetry::SDK.configure do |c|
  c.use_all
end
```

## Metrics

The instrumentation publishes GC pressure gauges backed by periodic `GC.stat` sampling: `ruby.gc.major_count`, `ruby.gc.minor_count`, `ruby.gc.time`, `ruby.heap.live_slots`, `ruby.heap.free_slots`, and `ruby.malloc_increase_bytes`.

The gauges are observable — `GC.stat` is sampled each time a meter provider collects metrics, so nothing is recorded unless metrics are configured. To collect them, add `opentelemetry-metrics-sdk` to your Gemfile and register a metric reader:

```ruby
OpenTelemetry::SDK.configure do |c|
  c.add_metric_reader OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
    exporter: OpenTelemetry::SDK::Metrics::Export::ConsoleMetricPullExporter.new
  )
  c.use "OpenTelemetry::Instrumentation::Rage"
end
```

## Examples

Example usage can be seen in the [`./example/trace_demonstration.ru` file](https://github.com/rage-rb/opentelemetry-instrumentation/blob/main/example/trace_demonstration.ru)

## License

The `opentelemetry-instrumentation-rage` gem is distributed under the Apache 2.0 license. See [LICENSE][license-github] for more information.

[bundler-home]: https://bundler.io
[repo-github]: https://github.com/open-telemetry/opentelemetry-ruby
[license-github]: https://github.com/open-telemetry/opentelemetry-ruby-contrib/blob/main/LICENSE
[ruby-sig]: https://github.com/open-telemetry/community#ruby-sig
[community-meetings]: https://github.com/open-telemetry/community#community-meetings
[slack-channel]: https://cloud-native.slack.com/archives/C01NWKKMKMY
[discussions-url]: https://github.com/open-telemetry/opentelemetry-ruby/discussions
