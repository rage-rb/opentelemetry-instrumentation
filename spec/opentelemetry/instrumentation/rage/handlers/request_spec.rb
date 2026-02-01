# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require_relative "../../../../../lib/opentelemetry/instrumentation/rage"
require_relative "../../../../../lib/opentelemetry/instrumentation/rage/handlers/request"

RSpec.describe OpenTelemetry::Instrumentation::Rage::Handlers::Request do
  subject { OpenTelemetry::Instrumentation::Rage::Handlers::Request }

  let(:instrumentation) { OpenTelemetry::Instrumentation::Rage::Instrumentation.instance }

  before do
    instrumentation.install({})
    EXPORTER.reset
  end

  after { instrumentation.instance_variable_set(:@installed, false) }

  describe ".enrich_request_span" do
    let(:controller_class) do
      Class.new do
        def action_name
        end
      end
    end
    let(:controller) { controller_class.new }
    let(:request) { double(method: "PUT", route_uri_pattern: "/api/test/:id") }
    let(:result) { double(error?: false) }

    before do
      stub_const("MyController", controller_class)
      allow(controller).to receive(:action_name).and_return("my_action")
    end

    it "updates span name and attributes" do
      instrumentation.tracer.in_span("test span") do |span|
        context = OpenTelemetry::Instrumentation::Rack.context_with_span(span)

        OpenTelemetry::Context.with_current(context) do
          subject.enrich_request_span(controller:, request:) { result }
        end

        expect(span.name).to eq("PUT /api/test/:id")
        expect(span.attributes["http.route"]).to eq("/api/test/:id")
        expect(span.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
      end
    end

    describe "with error" do
      let(:result) { double(error?: true, exception: RuntimeError.new) }

      it "handles returned exceptions" do
        instrumentation.tracer.in_span("test span") do |span|
          context = OpenTelemetry::Instrumentation::Rack.context_with_span(span)

          OpenTelemetry::Context.with_current(context) do
            subject.enrich_request_span(controller:, request:) { result }
          end

          expect(span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
          expect(span.events.first.name).to eq "exception"
          expect(span.events.first.attributes["exception.type"]).to eq "RuntimeError"
        end
      end
    end

    describe "with inactive span" do
      it "yields control" do
        span = OpenTelemetry::Trace.non_recording_span(OpenTelemetry::Trace::SpanContext.new)
        context = OpenTelemetry::Instrumentation::Rack.context_with_span(span)
        yielded = false

        OpenTelemetry::Context.with_current(context) do
          subject.enrich_request_span(controller:, request:) do
            yielded = true
          end
        end

        expect(yielded).to eq(true)
      end
    end
  end
end
