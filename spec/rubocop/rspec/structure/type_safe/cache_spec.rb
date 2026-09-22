# frozen_string_literal: true

require "tmpdir"

RSpec.describe RuboCop::RSpec::Structure::TypeSafe::Cache do
  let(:inner_client) { FakeTypeSafeClient.new(probability: 0.8) }
  let(:cache_path) { File.join(tmpdir, "jev_cache.json") }
  let(:tmpdir) { Dir.mktmpdir }
  let(:cache) { described_class.new(client: inner_client, model: "jev-latest", path: cache_path) }
  let(:item) { noul_question(id: "a", state: "when the user is an admin", instructions: "instructions", criteria: nil) }

  after { FileUtils.remove_entry(tmpdir) }

  def noul_question(**attrs)
    RuboCop::RSpec::Structure::TypeSafe::NoulQuestion.new(**attrs)
  end

  describe "#nouls" do
    context "when there is a cache miss" do
      it "delegates to the client" do
        probabilities = cache.nouls([item])

        expect(probabilities).to eq({ "a" => 0.8 })
        expect(inner_client.calls.size).to eq(1)
      end
    end

    context "when the cache already has an entry" do
      it "returns the cached result without calling the client again" do
        cache.nouls([item])
        probabilities = cache.nouls([item])

        expect(probabilities).to eq({ "a" => 0.8 })
        expect(inner_client.calls.size).to eq(1)
      end
    end

    context "when a new instance loads the same cache file" do
      it "reuses the persisted cache without calling the client again" do
        cache.nouls([item])

        reloaded = described_class.new(client: inner_client, model: "jev-latest", path: cache_path)
        reloaded.nouls([item])

        expect(inner_client.calls.size).to eq(1)
      end
    end

    context "when every item is a cache miss" do
      it "delegates all of them to the client" do
        probabilities = cache.nouls(
          [
            noul_question(id: "a", state: "state a", instructions: "instructions", criteria: nil),
            noul_question(id: "b", state: "state b", instructions: "instructions", criteria: nil)
          ]
        )

        expect(probabilities).to eq({ "a" => 0.8, "b" => 0.8 })
        expect(inner_client.calls.size).to eq(2)
      end
    end

    context "when the client can prove how many times it was called" do
      it "passes every miss to a single call to the client's #nouls" do
        spy_client = instance_double(RuboCop::RSpec::Structure::TypeSafe::Client)
        allow(spy_client).to receive(:nouls) { |items| items.to_h { [_1.id, 0.8] } }
        cache_with_spy = described_class.new(client: spy_client, model: "jev-latest", path: cache_path)

        cache_with_spy.nouls(
          [
            noul_question(id: "a", state: "state a", instructions: "instructions", criteria: nil),
            noul_question(id: "b", state: "state b", instructions: "instructions", criteria: nil)
          ]
        )

        expect(spy_client).to have_received(:nouls).once
      end
    end

    context "when some items are already cached" do
      it "only sends the misses to the client" do
        cache.nouls([noul_question(id: "a", state: "state a", instructions: "instructions", criteria: nil)])

        probabilities = cache.nouls(
          [
            noul_question(id: "a", state: "state a", instructions: "instructions", criteria: nil),
            noul_question(id: "b", state: "state b", instructions: "instructions", criteria: nil)
          ]
        )

        expect(probabilities).to eq({ "a" => 0.8, "b" => 0.8 })
        expect(inner_client.calls.size).to eq(2)
      end
    end

    context "when every item is already cached" do
      it "returns the cached results without calling the client" do
        cache.nouls([noul_question(id: "a", state: "state a", instructions: "instructions", criteria: nil)])
        cache.nouls([noul_question(id: "b", state: "state b", instructions: "instructions", criteria: nil)])
        inner_client.calls.clear

        probabilities = cache.nouls(
          [
            noul_question(id: "a", state: "state a", instructions: "instructions", criteria: nil),
            noul_question(id: "b", state: "state b", instructions: "instructions", criteria: nil)
          ]
        )

        expect(probabilities).to eq({ "a" => 0.8, "b" => 0.8 })
        expect(inner_client.calls).to be_empty
      end
    end
  end

  context "when a different model is used" do
    it "treats it as a different cache entry" do
      cache.nouls([item])

      other = described_class.new(client: inner_client, model: "jev-2", path: cache_path)
      other.nouls([item])

      expect(inner_client.calls.size).to eq(2)
    end
  end

  context "when no path is given" do
    around do |example|
      original_xdg_cache_home = ENV.fetch("XDG_CACHE_HOME", nil)
      original_home = ENV.fetch("HOME", nil) # rubocop:disable Style/EnvHome -- restoring the raw env var, not resolving home
      example.run
    ensure
      original_xdg_cache_home ? (ENV["XDG_CACHE_HOME"] = original_xdg_cache_home) : ENV.delete("XDG_CACHE_HOME")
      original_home ? (ENV["HOME"] = original_home) : ENV.delete("HOME")
    end

    # Observes where the resolved default actually gets written, through
    # the public `#nouls` API, rather than reaching into the private
    # `default_path` method or `@path` directly.
    def expect_default_path(path)
      allow(File).to receive(:exist?).and_return(false)
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)

      described_class.new(client: inner_client, model: "jev-latest")
                     .nouls([item])

      expect(File).to have_received(:write).with(path, anything)
    end

    context "when XDG_CACHE_HOME is set" do
      it "builds the cache under XDG_CACHE_HOME" do
        ENV["XDG_CACHE_HOME"] = "/xdg-cache"

        expect_default_path("/xdg-cache/rubocop-rspec-structure/jev_cache.json")
      end
    end

    context "when only HOME is set" do
      it "builds the cache under HOME/.cache" do
        ENV.delete("XDG_CACHE_HOME")
        ENV["HOME"] = "/home/example"

        expect_default_path("/home/example/.cache/rubocop-rspec-structure/jev_cache.json")
      end
    end

    context "when XDG_CACHE_HOME is set but empty" do
      it "builds the cache under HOME/.cache" do
        ENV["XDG_CACHE_HOME"] = ""
        ENV["HOME"] = "/home/example"

        expect_default_path("/home/example/.cache/rubocop-rspec-structure/jev_cache.json")
      end
    end

    context "when HOME is set but empty and XDG_CACHE_HOME is not set" do
      it "falls back to a project-relative path" do
        ENV.delete("XDG_CACHE_HOME")
        ENV["HOME"] = ""

        expect_default_path("tmp/rubocop-rspec-structure/jev_cache.json")
      end
    end

    context "when HOME is not set but Dir.home resolves it another way (e.g. /etc/passwd)" do
      it "builds the cache under it" do
        ENV.delete("XDG_CACHE_HOME")
        ENV.delete("HOME")
        allow(Dir).to receive(:home).and_return("/home/passwd-resolved")

        expect_default_path("/home/passwd-resolved/.cache/rubocop-rspec-structure/jev_cache.json")
      end
    end

    context "when Dir.home cannot be resolved at all" do
      it "falls back to a project-relative path" do
        ENV.delete("XDG_CACHE_HOME")
        ENV.delete("HOME")
        allow(Dir).to receive(:home).and_raise(ArgumentError)

        expect_default_path("tmp/rubocop-rspec-structure/jev_cache.json")
      end
    end
  end
end
