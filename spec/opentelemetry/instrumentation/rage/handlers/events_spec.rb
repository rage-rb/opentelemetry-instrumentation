# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require_relative "../../../../../lib/opentelemetry/instrumentation/rage"
require_relative "../../../../../lib/opentelemetry/instrumentation/rage/handlers/events"

RSpec.describe OpenTelemetry::Instrumentation::Rage::Handlers::Events do
  subject { OpenTelemetry::Instrumentation::Rage::Handlers::Events }

  let(:instrumentation) { OpenTelemetry::Instrumentation::Rage::Instrumentation.instance }

  let(:finished_spans) { EXPORTER.finished_spans }
  let(:event_span) { finished_spans.first }

  before do
    instrumentation.install({})
    EXPORTER.reset
  end

  after { instrumentation.instance_variable_set(:@installed, false) }

  describe ".create_publisher_span" do
    let(:event_class) { Class.new }
    let(:event) { event_class.new }

    before do
      stub_const("MyEvent", event_class)
    end

    describe "with active span" do
      it "creates a span" do
        instrumentation.tracer.in_span("test span") do
          subject.create_publisher_span(event:) {}
        end

        expect(finished_spans.size).to eq(2)

        expect(event_span.name).to eq("MyEvent publish")
        expect(event_span.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
        expect(event_span.kind).to eq(:producer)

        expect(event_span.attributes["messaging.system"]).to eq("rage.events")
        expect(event_span.attributes["messaging.operation.type"]).to eq("send")
        expect(event_span.attributes["messaging.destination.name"]).to eq("MyEvent")
      end

      it "yields control" do
        yielded = false

        subject.create_publisher_span(event:) do
          yielded = true
        end

        expect(yielded).to eq(true)
      end
    end

    describe "without active span" do
      it "does not create a span" do
        subject.create_publisher_span(event:) {}
        expect(finished_spans.size).to eq(0)
      end

      it "yields control" do
        yielded = false

        subject.create_publisher_span(event:) do
          yielded = true
        end

        expect(yielded).to eq(true)
      end
    end
  end

  describe ".create_subscriber_span" do
    let(:subscriber_class) do
      Class.new do
        def self.deferred?
        end
      end
    end
    let(:subscriber) { subscriber_class.new }

    let(:event_class) { Class.new }
    let(:event) { event_class.new }

    let(:result) { double(error?: false) }

    before do
      stub_const("MySubscriber", subscriber_class)
      stub_const("MyEvent", event_class)
    end

    describe "with a synchronous subscriber" do
      before do
        allow(subscriber_class).to receive(:deferred?).and_return(false)
      end

      it "creates a span" do
        subject.create_subscriber_span(subscriber:, event:) { result }

        expect(finished_spans.size).to eq(1)

        expect(event_span.name).to eq("MySubscriber process")
        expect(event_span.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
        expect(event_span.kind).to eq(:consumer)

        expect(event_span.attributes["messaging.system"]).to eq("rage.events")
        expect(event_span.attributes["messaging.operation.type"]).to eq("process")
        expect(event_span.attributes["messaging.destination.name"]).to eq("MyEvent")
      end

      describe "with error" do
        let(:result) { double(error?: true, exception: RuntimeError.new) }

        it "handles returned exceptions" do
          subject.create_subscriber_span(subscriber:, event:) { result }

          expect(event_span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
          expect(event_span.events.first.name).to eq "exception"
          expect(event_span.events.first.attributes["exception.type"]).to eq "RuntimeError"
        end
      end
    end

    describe "with an asynchronous subscriber" do
      before do
        allow(subscriber_class).to receive(:deferred?).and_return(true)
      end

      it "does not create a span" do
        subject.create_subscriber_span(subscriber:, event:) {}
        expect(finished_spans.size).to eq(0)
      end

      it "yields control" do
        yielded = false

        subject.create_subscriber_span(subscriber:, event:) do
          yielded = true
        end

        expect(yielded).to eq(true)
      end
    end
  end
end
