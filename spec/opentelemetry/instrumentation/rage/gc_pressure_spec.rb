# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require_relative "../../../../lib/opentelemetry/instrumentation/rage"
require_relative "../../../../lib/opentelemetry/instrumentation/rage/gc_pressure"
require "opentelemetry/sdk/metrics"
require "opentelemetry/sdk/metrics/export/in_memory_metric_pull_exporter"

RSpec.describe OpenTelemetry::Instrumentation::Rage::GCPressure do
  let(:gc_pressure_metric_names) do
    [
      "ruby.gc.major_count",
      "ruby.gc.minor_count",
      "ruby.gc.time",
      "ruby.heap.live_slots",
      "ruby.heap.free_slots",
      "ruby.malloc_increase_bytes"
    ]
  end

  let(:meter_provider) { OpenTelemetry::SDK::Metrics::MeterProvider.new }
  let(:exporter) { OpenTelemetry::SDK::Metrics::Export::InMemoryMetricPullExporter.new }

  before do
    @original_meter_provider = OpenTelemetry.meter_provider
    meter_provider.add_metric_reader(exporter)
    OpenTelemetry.meter_provider = meter_provider
  end

  after do
    OpenTelemetry.meter_provider = @original_meter_provider
  end

  describe ".setup" do
    it "registers the GC pressure gauges" do
      described_class.setup
      exporter.pull

      expect(exporter.metric_snapshots.map(&:name)).to contain_exactly(*gc_pressure_metric_names)

      kinds = exporter.metric_snapshots.to_h { |snapshot| [snapshot.name, snapshot.instrument_kind] }

      # GC counts are monotonic counters; the rest are gauges
      expect(kinds.fetch("ruby.gc.major_count")).to eq(:observable_counter)
      expect(kinds.fetch("ruby.gc.minor_count")).to eq(:observable_counter)
      expect(kinds.fetch("ruby.gc.time")).to eq(:observable_gauge)
      expect(kinds.fetch("ruby.heap.live_slots")).to eq(:observable_gauge)
      expect(kinds.fetch("ruby.heap.free_slots")).to eq(:observable_gauge)
      expect(kinds.fetch("ruby.malloc_increase_bytes")).to eq(:observable_gauge)
    end

    it "samples GC.stat values on collection" do
      described_class.setup

      major_count_before = GC.stat(:major_gc_count)
      GC.start(full_mark: true)
      exporter.pull

      values = exporter.metric_snapshots.to_h { |snapshot| [snapshot.name, snapshot] }
        .transform_values { |snapshot| snapshot.data_points.first.value }

      # a forced full mark ran between the baseline and the sample, and the
      # counter only grows afterwards
      expect(values.fetch("ruby.gc.major_count")).to be_between(major_count_before + 1, GC.stat(:major_gc_count)).inclusive
      expect(values.fetch("ruby.gc.minor_count")).to be_a(Integer)
      expect(values.fetch("ruby.gc.time")).to be_a(Float).and be >= 0
      expect(values.fetch("ruby.heap.live_slots")).to be > 0
      expect(values.fetch("ruby.heap.free_slots")).to be >= 0
      expect(values.fetch("ruby.malloc_increase_bytes")).to be_a(Integer)
    end

    it "registers gauges only once for the same meter provider" do
      expect(described_class.setup).to eq(true)
      expect(described_class.setup).to eq(false)

      exporter.pull

      expect(exporter.metric_snapshots.size).to eq(gc_pressure_metric_names.size)
    end
  end
end
