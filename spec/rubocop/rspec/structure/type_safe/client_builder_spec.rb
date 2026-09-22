# frozen_string_literal: true

require "tmpdir"

RSpec.describe RuboCop::RSpec::Structure::TypeSafe::ClientBuilder do
  subject(:builder) { described_class.new(cop_config) }

  let(:cop_config) { {} }

  after { ENV.delete("TYPESAFE_API_KEY") }

  describe "#build" do
    context "without a TYPESAFE_API_KEY" do
      it "returns a NullClient" do
        expect(builder.build).to be_a(RuboCop::RSpec::Structure::TypeSafe::NullClient)
      end
    end

    context "with a TYPESAFE_API_KEY set to an empty string" do
      it "returns a NullClient" do
        ENV["TYPESAFE_API_KEY"] = ""

        expect(builder.build).to be_a(RuboCop::RSpec::Structure::TypeSafe::NullClient)
      end
    end

    context "with a TYPESAFE_API_KEY configured" do
      before { ENV["TYPESAFE_API_KEY"] = "dummy" }

      context "with CacheEnabled (the default)" do
        let(:cache_path) { File.join(tmpdir, "jev_cache.json") }
        let(:tmpdir) { Dir.mktmpdir }
        let(:cop_config) { { "CachePath" => cache_path } }

        after { FileUtils.remove_entry(tmpdir) }

        it "returns a Cache wrapping a Client" do
          expect(builder.build).to be_a(RuboCop::RSpec::Structure::TypeSafe::Cache)
        end
      end

      context "with CacheEnabled: false" do
        let(:cop_config) { { "CacheEnabled" => false } }

        it "returns a plain Client" do
          expect(builder.build).to be_a(RuboCop::RSpec::Structure::TypeSafe::Client)
        end
      end

      context "when RUBOCOP_RSPEC_STRUCTURE_CACHE_PATH is set" do
        let(:cache_path) { File.join(tmpdir, "jev_cache.json") }
        let(:tmpdir) { Dir.mktmpdir }
        let(:cop_config) { { "CachePath" => "/from-config/jev_cache.json" } }

        after do
          ENV.delete("RUBOCOP_RSPEC_STRUCTURE_CACHE_PATH")
          FileUtils.remove_entry(tmpdir)
        end

        it "overrides the configured CachePath" do
          ENV["RUBOCOP_RSPEC_STRUCTURE_CACHE_PATH"] = cache_path
          allow(RuboCop::RSpec::Structure::TypeSafe::Client)
            .to receive(:new).and_return(FakeTypeSafeClient.new(probability: 0.5))
          item = RuboCop::RSpec::Structure::TypeSafe::NoulQuestion.new(
            id: "a", state: "s", instructions: "i", criteria: nil
          )

          builder.build.nouls([item])

          expect(File.exist?(cache_path)).to be(true)
        end
      end

      context "with Model and JevTimeoutSeconds configured" do
        let(:cop_config) { { "CacheEnabled" => false, "Model" => "jev-2", "JevTimeoutSeconds" => 30 } }

        it "passes them through to the Client" do
          client = instance_double(RuboCop::RSpec::Structure::TypeSafe::Client)
          allow(RuboCop::RSpec::Structure::TypeSafe::Client).to receive(:new).and_return(client)

          builder.build

          expect(RuboCop::RSpec::Structure::TypeSafe::Client)
            .to have_received(:new).with(api_key: "dummy", model: "jev-2", timeout: 30)
        end
      end
    end
  end
end
