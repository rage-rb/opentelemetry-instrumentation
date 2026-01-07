# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require_relative "../../../../../lib/opentelemetry/instrumentation/rage"
require_relative "../../../../../lib/opentelemetry/instrumentation/rage/handlers/cable"

RSpec.describe OpenTelemetry::Instrumentation::Rage::Handlers::Cable do
  subject { OpenTelemetry::Instrumentation::Rage::Handlers::Cable }

  let(:instrumentation) { OpenTelemetry::Instrumentation::Rage::Instrumentation.instance }

  describe ".save_context" do
    let(:env) { {"REQUEST_METHOD" => "POST", "PATH_INFO" => "/cable"} }

    describe "with no active span" do
      it "does not change env" do
        subject.save_context(env:) {}
        expect(env.size).to eq(2)
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

      it "updates span name" do
        instrumentation.tracer.in_span("test span") do |span|
          context = OpenTelemetry::Instrumentation::Rack.context_with_span(span)

          OpenTelemetry::Context.with_current(context) do
            subject.save_context(env:) {}
          end

          expect(span.name).to eq("POST /cable")
        end
      end

      it "updates env" do
        instrumentation.tracer.in_span("test span") do |span|
          context = OpenTelemetry::Instrumentation::Rack.context_with_span(span)

          OpenTelemetry::Context.with_current(context) do
            subject.save_context(env:) {}
          end

          expect(env["otel.rage.handshake_context"]).to eq(context)
          expect(env["otel.rage.handshake_link"].first).to be_a(OpenTelemetry::Trace::Link)
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

  describe ".create_connection_span" do
    let(:link) { OpenTelemetry::Trace::Link.new(OpenTelemetry::Trace::SpanContext.new) }
    let(:env) { {"otel.rage.handshake_link" => [link]} }
    let(:action) { :my_action }
    let(:connection_class) { Class.new }
    let(:connection) { connection_class.new }
    let(:result) { double(error?: false) }

    let(:finished_spans) { EXPORTER.finished_spans }
    let(:connection_span) { finished_spans.first }

    before do
      instrumentation.install({})
      EXPORTER.reset
      stub_const("MyConnection", connection_class)
    end

    after { instrumentation.instance_variable_set(:@installed, false) }

    it "creates a span" do
      subject.create_connection_span(env:, action:, connection:) { result }

      expect(finished_spans.size).to eq(1)

      expect(connection_span.name).to eq("MyConnection my_action")
      expect(connection_span.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)

      expect(connection_span.attributes["messaging.system"]).to eq("rage.cable")
      expect(connection_span.attributes["messaging.destination.name"]).to eq("MyConnection")
      expect(connection_span.attributes["code.function.name"]).to eq("MyConnection#my_action")

      expect(connection_span.links.first).to eq(link)
    end

    describe "with baggage" do
      let(:context) { OpenTelemetry::Baggage.set_value("testing_baggage", "it_worked") }
      let(:env) { {"otel.rage.handshake_context" => context} }

      it "propagates baggage" do
        subject.create_connection_span(env:, action:, connection:) do
          expect(OpenTelemetry::Baggage.value("testing_baggage")).to eq("it_worked")
          result
        end
      end
    end

    describe "with error" do
      let(:result) { double(error?: true, exception: RuntimeError.new) }

      it "handles returned exceptions" do
        subject.create_connection_span(env:, action:, connection:) { result }

        expect(connection_span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
        expect(connection_span.events.first.name).to eq "exception"
        expect(connection_span.events.first.attributes["exception.type"]).to eq "RuntimeError"
      end
    end

    describe "with connect action" do
      let(:action) { :connect }

      it "sets span kind to server" do
        subject.create_connection_span(env:, action:, connection:) { result }
        expect(connection_span.kind).to eq(:server)
      end
    end

    describe "with disconnect action" do
      let(:action) { :disconnect }

      it "sets span kind to internal" do
        subject.create_connection_span(env:, action:, connection:) { result }
        expect(connection_span.kind).to eq(:internal)
      end
    end
  end

  describe ".create_channel_span" do
    let(:link) { OpenTelemetry::Trace::Link.new(OpenTelemetry::Trace::SpanContext.new) }
    let(:env) { {"otel.rage.handshake_link" => [link]} }
    let(:action) { :my_action }
    let(:channel_class) { Class.new }
    let(:channel) { channel_class.new }

    let(:result) { double(error?: false) }

    let(:finished_spans) { EXPORTER.finished_spans }
    let(:channel_span) { finished_spans.first }

    before do
      instrumentation.install({})
      EXPORTER.reset
      stub_const("MyChannel", channel_class)
    end

    after { instrumentation.instance_variable_set(:@installed, false) }

    it "creates a span" do
      subject.create_channel_span(env:, action:, channel:) { result }

      expect(finished_spans.size).to eq(1)

      expect(channel_span.name).to eq("MyChannel receive")
      expect(channel_span.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
      expect(channel_span.kind).to eq(:server)

      expect(channel_span.attributes["messaging.system"]).to eq("rage.cable")
      expect(channel_span.attributes["messaging.destination.name"]).to eq("MyChannel")
      expect(channel_span.attributes["messaging.operation.type"]).to eq("receive")
      expect(channel_span.attributes["code.function.name"]).to eq("MyChannel#my_action")

      expect(channel_span.links.first).to eq(link)
    end

    describe "with baggage" do
      let(:context) { OpenTelemetry::Baggage.set_value("testing_baggage", "it_worked") }
      let(:env) { {"otel.rage.handshake_context" => context} }

      it "propagates baggage" do
        subject.create_channel_span(env:, action:, channel:) do
          expect(OpenTelemetry::Baggage.value("testing_baggage")).to eq("it_worked")
          result
        end
      end
    end

    describe "with error" do
      let(:result) { double(error?: true, exception: RuntimeError.new) }

      it "handles returned exceptions" do
        subject.create_channel_span(env:, action:, channel:) { result }

        expect(channel_span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
        expect(channel_span.events.first.name).to eq "exception"
        expect(channel_span.events.first.attributes["exception.type"]).to eq "RuntimeError"
      end
    end

    describe "with subscribed action" do
      let(:action) { :subscribed }

      it "sets span kind to server" do
        subject.create_channel_span(env:, action:, channel:) { result }

        expect(channel_span.attributes["messaging.operation.type"]).to eq("receive")
        expect(channel_span.name).to eq("MyChannel subscribe")
        expect(channel_span.kind).to eq(:server)
      end
    end

    describe "with unsubscribed action" do
      let(:action) { :unsubscribed }

      it "sets span kind to server" do
        subject.create_channel_span(env:, action:, channel:) { result }

        expect(channel_span.attributes["messaging.operation.type"]).to be_nil
        expect(channel_span.name).to eq("MyChannel unsubscribe")
        expect(channel_span.kind).to eq(:internal)
      end
    end
  end

  describe ".create_broadcast_span" do
    let(:result) { double(error?: false) }

    let(:finished_spans) { EXPORTER.finished_spans }
    let(:broadcast_span) { finished_spans.first }

    before do
      instrumentation.install({})
      EXPORTER.reset
    end

    after { instrumentation.instance_variable_set(:@installed, false) }

    it "creates a span" do
      subject.create_broadcast_span(stream: "test-stream") { result }

      expect(finished_spans.size).to eq(1)

      expect(broadcast_span.name).to eq("Rage::Cable broadcast")
      expect(broadcast_span.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
      expect(broadcast_span.kind).to eq(:producer)

      expect(broadcast_span.attributes["messaging.system"]).to eq("rage.cable")
      expect(broadcast_span.attributes["messaging.operation.type"]).to eq("publish")
      expect(broadcast_span.attributes["messaging.destination.name"]).to eq("test-stream")
    end

    describe "with error" do
      let(:result) { double(error?: true, exception: RuntimeError.new) }

      it "handles returned exceptions" do
        subject.create_broadcast_span(stream: "test-stream") { result }

        expect(broadcast_span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
        expect(broadcast_span.events.first.name).to eq "exception"
        expect(broadcast_span.events.first.attributes["exception.type"]).to eq "RuntimeError"
      end
    end
  end
end
