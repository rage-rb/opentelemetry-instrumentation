# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module Rage
      # Collects server capacity metrics from Iodine::Perf: the kernel
      # accept-queue depth and event loop utilization.
      #
      # These metrics are collected whenever OpenTelemetry requests them.
      # The SDK handles collection at its configured export interval, so
      # no separate background thread is needed.
      #
      # Requires iodine >= 7.0 (Iodine::Perf). When iodine doesn't provide
      # the Perf module, setup is a no-op.
      module Capacity
        # The most recent ELU sample, so utilization is measured over the
        # window between two collections instead of since server start.
        @last_sample = nil

        # Keeps track of the provider used to register the metrics.
        # This prevents registering the same metrics more than once.
        @registered_provider = nil

        class << self
          # Registers the capacity metrics with the global OpenTelemetry
          # meter provider and enables event loop utilization tracking.
          #
          # Returns false if the metrics are already registered with this
          # provider, or if iodine doesn't support the Perf module.
          #
          # @return [Boolean] whether the metrics were registered
          # standard:disable Style/StringLiterals
          def setup
            require "iodine"
            return false unless defined?(Iodine::Perf)

            Iodine::Perf.elu_enable_idle_time!
            register_elu_sample_window

            provider = OpenTelemetry.meter_provider
            return false if provider.equal?(@registered_provider)

            meter = provider.meter('OpenTelemetry::Instrumentation::Rage', version: VERSION)

            meter.create_observable_gauge(
              'iodine.connections.queued',
              callback: -> { Iodine::Perf.queued_connections },
              unit: '{connection}',
              description: 'Connections waiting in the kernel accept queue for iodine listening sockets'
            )

            meter.create_observable_gauge(
              'ruby.event_loop.utilization',
              callback: -> { event_loop_utilization },
              unit: '1',
              description: 'Fraction of time the event loop spent busy since the previous collection (0 = idle, 1 = saturated)'
            )

            @registered_provider = provider
            true
          end
          # standard:enable Style/StringLiterals

          private

          # The first utilization reading shouldn't cover the boot interval
          # before the server runs, so open the sample window when the reactor
          # starts. Forked workers restart the iodine counters, so the
          # per-worker window resets as soon as the child starts.
          def register_elu_sample_window
            Iodine.on_state(:pre_start) { @last_sample = Iodine::Perf.elu_snapshot }
            Iodine.on_state(:enter_child) { @last_sample = nil }
          end

          # Returns how busy the event loop was since the previous call:
          # `0.0` means fully idle, `1.0` means fully busy.
          #
          # Returns nil when no full window was measured yet - the first
          # collection after enabling (or after a window reset) only opens
          # the next window.
          #
          # @return [Float, nil]
          def event_loop_utilization
            sample = Iodine::Perf.elu_snapshot
            return nil if sample.nil?

            last_sample, @last_sample = @last_sample, sample
            return nil if last_sample.nil?

            elapsed = sample[1] - last_sample[1]
            return nil if elapsed <= 0

            busy = elapsed - (sample[0] - last_sample[0])
            busy.fdiv(elapsed)
          end
        end
      end
    end
  end
end
