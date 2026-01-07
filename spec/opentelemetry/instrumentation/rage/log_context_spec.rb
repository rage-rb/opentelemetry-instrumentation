# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require_relative "../../../../lib/opentelemetry/instrumentation/rage"
require_relative "../../../../lib/opentelemetry/instrumentation/rage/log_context"

RSpec.describe OpenTelemetry::Instrumentation::Rage::LogContext do
  subject { OpenTelemetry::Instrumentation::Rage::LogContext.call }

  let(:instrumentation) { OpenTelemetry::Instrumentation::Rage::Instrumentation.instance }

  describe "with no active span" do
    it "returns nil" do
      expect(subject).to be_nil
    end
  end

  describe "with active span" do
    before { instrumentation.install({}) }
    after { instrumentation.instance_variable_set(:@installed, false) }

    it "returns a hash with trace_id and span_id" do
      instrumentation.tracer.in_span("test span") do |span|
        expect(subject[:trace_id]).to eq(span.context.hex_trace_id)
        expect(subject[:span_id]).to eq(span.context.hex_span_id)
      end
    end
  end

  describe "with an exception" do
    before do
      allow(OpenTelemetry::Trace).to receive(:current_span).and_raise("Test Error")
    end

    it "handles raised exceptions" do
      expect(OpenTelemetry).to receive(:handle_error).with(exception: instance_of(RuntimeError))
      expect(subject).to be_nil
    end
  end
end
