# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require_relative "../../../../../lib/opentelemetry/instrumentation/rage"
require_relative "../../../../../lib/opentelemetry/instrumentation/rage/handlers/fiber"

RSpec.describe OpenTelemetry::Instrumentation::Rage::Handlers::Fiber do
  subject { OpenTelemetry::Instrumentation::Rage::Handlers::Fiber }

  let(:instrumentation) { OpenTelemetry::Instrumentation::Rage::Instrumentation.instance }

  before do
    instrumentation.install({})
    EXPORTER.reset
  end

  after { instrumentation.instance_variable_set(:@installed, false) }

  describe "Patch" do
    let(:klass) do
      Class.new do
        def self.schedule(&)
          yield
        end
      end
    end

    before do
      klass.singleton_class.prepend(subject::Patch)
      Fiber[:__rage_otel_context] = nil
    end

    describe "without active span" do
      it "saves context to fiber storage" do
        expect(Fiber[:__rage_otel_context]).to be_nil
        klass.schedule {}
        expect(Fiber[:__rage_otel_context]).to be_a(OpenTelemetry::Context)
      end
    end

    describe "with active span" do
      it "saves context to fiber storage" do
        expect(Fiber[:__rage_otel_context]).to be_nil
        instrumentation.tracer.in_span("test span") do
          klass.schedule {}
        end
        expect(Fiber[:__rage_otel_context]).to be_a(OpenTelemetry::Context)
      end
    end

    it "calls super" do
      allow(klass).to receive(:schedule).and_return(:test_schedule_result)
      expect(klass.schedule {}).to eq(:test_schedule_result)
    end
  end

  describe "#initialize" do
    it "patches Fiber" do
      expect(Fiber.singleton_class).to receive(:prepend).with(subject::Patch)
      subject.new
    end
  end

  describe "#propagate_otel_context" do
    before do
      allow(Fiber.singleton_class).to receive(:prepend).with(subject::Patch)
    end

    it "propagates context" do
      instrumentation.tracer.in_span("test span") do
        Fiber[:__rage_otel_context] = OpenTelemetry::Context.current
      end

      subject.new.propagate_otel_context do
        expect(OpenTelemetry::Trace.current_span.name).to eq("test span")
      end
    end

    describe "with baggage" do
      it "propagates baggage" do
        Fiber[:__rage_otel_context] = OpenTelemetry::Baggage.set_value("testing_baggage", "it_worked")

        subject.new.propagate_otel_context do
          expect(OpenTelemetry::Baggage.value("testing_baggage")).to eq("it_worked")
        end
      end
    end
  end
end
