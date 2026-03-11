# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module Rage
      module Handlers
        # The class wraps the processing of SSE streams in spans.
        class SSE < ::Rage::Telemetry::Handler
          REQUEST_CONTEXT = "otel.rage.request_context"
          private_constant :REQUEST_CONTEXT

          handle "controller.action.process", with: :save_context
          handle "sse.stream.process", with: :create_stream_span

          # @param env [Hash] the Rack env
          def self.save_context(env:)
            span = OpenTelemetry::Instrumentation::Rack.current_span
            return yield unless span.recording?

            env[REQUEST_CONTEXT] = OpenTelemetry::Context.current
            yield
          end

          # @param env [Hash] the Rack env
          def self.create_stream_span(env:)
            request_context = env[REQUEST_CONTEXT]

            OpenTelemetry::Context.with_current(request_context) do
              Rage::Instrumentation.instance.tracer.in_span("SSE stream", kind: :server) do |span|
                result = yield

                if result.error?
                  span.record_exception(result.exception)
                  span.status = OpenTelemetry::Trace::Status.error
                end
              end
            end
          end
        end
      end
    end
  end
end
