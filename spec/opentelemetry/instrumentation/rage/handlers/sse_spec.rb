# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require_relative "../../../../../lib/opentelemetry/instrumentation/rage"

SSE_AVAILABLE = ::Rage::Telemetry.available_spans.any? { |span_name| span_name.start_with?("sse.") }

if SSE_AVAILABLE
  require_relative "../../../../../lib/opentelemetry/instrumentation/rage/handlers/sse"
end

RSpec.describe "OpenTelemetry::Instrumentation::Rage::Handlers::SSE" do
  subject { OpenTelemetry::Instrumentation::Rage::Handlers::SSE }

  let(:instrumentation) { OpenTelemetry::Instrumentation::Rage::Instrumentation.instance }

  before(:all) do
    skip "SSE telemetry not available in Rage v#{Rage::VERSION}" unless SSE_AVAILABLE
  end

  describe ".save_context" do
    let(:env) { {} }

    describe "with no active span" do
      it "does not change env" do
        subject.save_context(env:) {}
        expect(env).to be_empty
      end

      it "yields control" do
        yielded = false

        subject.save_context(env:) do
          yielded = true
        end

        expect(yielded).to eq(true)
      end
    end

    describe "with active span" do
      before { instrumentation.install({}) }
      after { instrumentation.instance_variable_set(:@installed, false) }

      it "updates env" do
        instrumentation.tracer.in_span("test span") do |span|
          context = OpenTelemetry::Instrumentation::Rack.context_with_span(span)

          OpenTelemetry::Context.with_current(context) do
            subject.save_context(env:) {}
          end

          expect(env["otel.rage.request_context"]).to eq(context)
        end
      end

      it "yields control" do
        instrumentation.tracer.in_span("test span") do |span|
          context = OpenTelemetry::Instrumentation::Rack.context_with_span(span)
          yielded = false

          OpenTelemetry::Context.with_current(context) do
            subject.save_context(env:) do
              yielded = true
            end
          end

          expect(yielded).to eq(true)
        end
      end
    end
  end

  describe ".create_stream_span" do
    let(:result) { double(error?: false) }
    let(:span) { instrumentation.tracer.start_span("GET /stream") }
    let(:context) { OpenTelemetry::Trace.context_with_span(span) }
    let(:env) { {"otel.rage.request_context" => context} }
    let(:type) { :stream }

    let(:finished_spans) { EXPORTER.finished_spans }
    let(:stream_span) { finished_spans.last }

    before do
      instrumentation.install({})
      EXPORTER.reset
      span.finish
    end

    after { instrumentation.instance_variable_set(:@installed, false) }

    it "creates a span" do
      subject.create_stream_span(env:, type:) { result }

      expect(finished_spans.size).to eq(2)

      expect(stream_span.name).to eq("SSE stream")
      expect(stream_span.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
      expect(stream_span.kind).to eq(:server)

      expect(stream_span.parent_span_id).to eq(span.context.span_id)
    end

    describe "with baggage" do
      let(:context) { OpenTelemetry::Baggage.set_value("testing_baggage", "it_worked") }

      it "propagates baggage" do
        subject.create_stream_span(env:, type:) do
          expect(OpenTelemetry::Baggage.value("testing_baggage")).to eq("it_worked")
          result
        end
      end
    end

    describe "with error" do
      let(:result) { double(error?: true, exception: RuntimeError.new) }

      it "handles returned exceptions" do
        subject.create_stream_span(env:, type:) { result }

        expect(stream_span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
        expect(stream_span.events.first.name).to eq "exception"
        expect(stream_span.events.first.attributes["exception.type"]).to eq "RuntimeError"
      end
    end

    describe "with one-off update" do
      let(:type) { :single }

      it "doesn't create a span" do
        subject.create_stream_span(env:, type:) { result }

        expect(finished_spans.size).to eq(1)
        expect(finished_spans.last.name).not_to eq("SSE stream")
      end
    end
  end
end
