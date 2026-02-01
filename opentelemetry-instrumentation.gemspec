# frozen_string_literal: true

require_relative "lib/opentelemetry/instrumentation/rage/version"

Gem::Specification.new do |spec|
  spec.name = "opentelemetry-instrumentation-rage"
  spec.version = OpenTelemetry::Instrumentation::Rage::VERSION
  spec.authors = ["Roman Samoilov"]
  spec.email = ["developers@rage-rb.dev"]

  spec.summary = "OpenTelemetry instrumentation for the Rage framework"
  spec.homepage = "https://rage-rb.dev"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rage-rb/opentelemetry-instrumentation"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "opentelemetry-instrumentation-rack", "~> 0.29"
  spec.add_dependency "opentelemetry-semantic_conventions", ">= 1.36.0"
end
