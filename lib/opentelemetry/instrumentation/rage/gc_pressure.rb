# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module Rage
      # Collects garbage collection metrics using GC.stat.
      #
      # These metrics are collected whenever OpenTelemetry requests them.
      # The SDK handles collection at its configured export interval, so
      # no separate background thread is needed.
      module GCPressure
        # Each metric defines its name, type, unit, description and how to read its value.
        # standard:disable Style/StringLiterals
        METRICS = {
          'ruby.gc.major_count' => {
            kind: :counter,
            unit: '{run}',
            description: 'Cumulative number of major GC runs',
            callback: -> { GC.stat(:major_gc_count) }
          },
          'ruby.gc.minor_count' => {
            kind: :counter,
            unit: '{run}',
            description: 'Cumulative number of minor GC runs',
            callback: -> { GC.stat(:minor_gc_count) }
          },
          'ruby.gc.time' => {
            kind: :gauge,
            unit: 's',
            description: 'Cumulative time spent in garbage collection',
            callback: -> { (GC.stat(:time) || 0) / 1000.0 }
          },
          'ruby.heap.live_slots' => {
            kind: :gauge,
            unit: '{slot}',
            description: 'Number of live heap slots',
            callback: -> { GC.stat(:heap_live_slots) }
          },
          'ruby.heap.free_slots' => {
            kind: :gauge,
            unit: '{slot}',
            description: 'Number of free heap slots',
            callback: -> { GC.stat(:heap_free_slots) }
          },
          'ruby.malloc_increase_bytes' => {
            kind: :gauge,
            unit: 'By',
            description: 'Net bytes allocated by malloc since the last GC',
            callback: -> { GC.stat(:malloc_increase_bytes) }
          }
        }.freeze
        private_constant :METRICS

        # Keeps track of the provider used to register the metrics.
        # This prevents registering the same metrics more than once.
        @registered_provider = nil

        class << self
          # Registers the GC metrics with the global OpenTelemetry meter provider.
          #
          # Returns false if the metrics are already registered with this provider.
          #
          # @return [Boolean] whether the metrics were registered
          # rubocop:disable Metrics/MethodLength -- Keep the setup method together.
          def setup
            provider = OpenTelemetry.meter_provider
            return false if provider.equal?(@registered_provider)

            meter = provider.meter('OpenTelemetry::Instrumentation::Rage', version: VERSION)

            METRICS.each do |name, metric|
              if metric[:kind] == :counter
                meter.create_observable_counter(
                  name,
                  callback: metric[:callback],
                  unit: metric[:unit],
                  description: metric[:description]
                )
              else
                meter.create_observable_gauge(
                  name,
                  callback: metric[:callback],
                  unit: metric[:unit],
                  description: metric[:description]
                )
              end
            end

            @registered_provider = provider
            true
          end
        end
        # standard:enable Style/StringLiterals
      end
    end
  end
end
