# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require_relative "../../../../lib/opentelemetry/instrumentation/rage"

RSpec.describe OpenTelemetry::Instrumentation::Rage do
  let(:instrumentation) { OpenTelemetry::Instrumentation::Rage::Instrumentation.instance }

  it "has #name" do
    expect(instrumentation.name).to eq("OpenTelemetry::Instrumentation::Rage")
  end

  it "has #version" do
    expect(instrumentation.version).not_to be_nil
    expect(instrumentation.version).not_to be_empty
  end

  describe "#install" do
    after do
      instrumentation.instance_variable_set(:@installed, false)
    end

    it "accepts argument" do
      expect(instrumentation.install({})).to eq(true)
    end

    it "installs Rack middleware" do
      expect(Rage.config.middleware).to receive(:insert_after) do |position, (middleware, _, _)|
        expect(position).to eq(0)
        expect(middleware.name).to match(/^OpenTelemetry::Instrumentation::Rack::Middlewares/)
      end

      instrumentation.install({})
    end

    it "installs observability components" do
      expect(Rage.config.telemetry).to receive(:use).with(OpenTelemetry::Instrumentation::Rage::Handlers::Request)
      expect(Rage.config.telemetry).to receive(:use).with(OpenTelemetry::Instrumentation::Rage::Handlers::Cable)
      expect(Rage.config.telemetry).to receive(:use).with(OpenTelemetry::Instrumentation::Rage::Handlers::Deferred)
      expect(Rage.config.telemetry).to receive(:use).with(OpenTelemetry::Instrumentation::Rage::Handlers::Events)
      expect(Rage.config.telemetry).to receive(:use).with(instance_of(OpenTelemetry::Instrumentation::Rage::Handlers::Fiber))

      expect(Rage.config.log_context).to receive(:<<).with(OpenTelemetry::Instrumentation::Rage::LogContext)

      instrumentation.install({})
    end
  end

  describe "#compatible" do
    describe "with a compatible version" do
      before do
        stub_const("::Rage::VERSION", "1.22.1")
      end

      it "returns true" do
        expect(instrumentation).to be_compatible
      end

      it "logs a warning" do
        expect(OpenTelemetry.logger).not_to receive(:warn)
        instrumentation.compatible?
      end
    end

    describe "with an incompatible version" do
      before do
        stub_const("::Rage::VERSION", "1.11.0")
      end

      it "returns false" do
        expect(instrumentation).not_to be_compatible
      end

      it "logs a warning" do
        expect(OpenTelemetry.logger).to receive(:warn).with(/1.11.0 is not supported/)
        instrumentation.compatible?
      end
    end
  end
end
