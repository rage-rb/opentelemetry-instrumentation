# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require_relative "../../../../../lib/opentelemetry/instrumentation/rage"
require_relative "../../../../../lib/opentelemetry/instrumentation/rage/handlers/deferred"

RSpec.describe OpenTelemetry::Instrumentation::Rage::Handlers::Deferred do
  subject { OpenTelemetry::Instrumentation::Rage::Handlers::Deferred }

  let(:instrumentation) { OpenTelemetry::Instrumentation::Rage::Instrumentation.instance }

  let(:task_class) { Class.new }
  let(:task_context) { {} }

  let(:result) { double(error?: false) }

  let(:finished_spans) { EXPORTER.finished_spans }
  let(:task_span) { finished_spans.first }

  before do
    instrumentation.install({})
    EXPORTER.reset
    stub_const("MyTask", task_class)
  end

  after { instrumentation.instance_variable_set(:@installed, false) }

  describe ".create_enqueue_span" do
    it "creates a span" do
      subject.create_enqueue_span(task_class:, task_context:) { result }

      expect(finished_spans.size).to eq(1)

      expect(task_span.name).to eq("MyTask enqueue")
      expect(task_span.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
      expect(task_span.kind).to eq(:producer)

      expect(task_span.attributes).to be_empty
    end

    it "stores the context" do
      subject.create_enqueue_span(task_class:, task_context:) { result }
      expect(task_context.key?("traceparent")).to eq(true)
    end

    describe "with error" do
      let(:result) { double(error?: true, exception: RuntimeError.new) }

      it "handles returned exceptions" do
        subject.create_enqueue_span(task_class:, task_context:) { result }

        expect(task_span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
        expect(task_span.events.first.name).to eq "exception"
        expect(task_span.events.first.attributes["exception.type"]).to eq "RuntimeError"
      end
    end
  end

  describe ".create_perform_span" do
    let(:task) { double(meta: task_metadata) }
    let(:task_metadata) { double(attempts: 1, retrying?: false) }

    it "creates a span" do
      subject.create_perform_span(task_class:, task:, task_context:) { result }

      expect(finished_spans.size).to eq(1)

      expect(task_span.name).to eq("MyTask perform")
      expect(task_span.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
      expect(task_span.kind).to eq(:consumer)

      expect(task_span.links.nil?).to eq(true)
      expect(task_span.attributes).to be_empty
    end

    describe "with root span" do
      let(:task_span) { finished_spans.last }

      before do
        instrumentation.tracer.in_span("test span") do |_span|
          OpenTelemetry.propagation.inject(task_context)
        end
      end

      it "links to root span" do
        subject.create_perform_span(task_class:, task:, task_context:) { result }

        expect(task_span.links.nil?).to eq(false)
        expect(task_span.links.first).to be_a(OpenTelemetry::Trace::Link)
      end
    end

    describe "with baggage" do
      before do
        context = OpenTelemetry::Baggage.set_value("testing_baggage", "it_worked")

        OpenTelemetry::Context.with_current(context) do
          OpenTelemetry.propagation.inject(task_context)
        end
      end

      it "propagates baggage" do
        subject.create_perform_span(task_class:, task:, task_context:) do
          expect(OpenTelemetry::Baggage.value("testing_baggage")).to eq("it_worked")
          result
        end
      end
    end

    describe "with error" do
      let(:result) { double(error?: true, exception: RuntimeError.new) }

      it "handles returned exceptions" do
        subject.create_perform_span(task_class:, task:, task_context:) { result }

        expect(task_span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
        expect(task_span.events.first.name).to eq "exception"
        expect(task_span.events.first.attributes["exception.type"]).to eq "RuntimeError"
      end
    end
  end
end
