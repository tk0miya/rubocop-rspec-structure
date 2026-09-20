# frozen_string_literal: true

require "tmpdir"

RSpec.describe RuboCop::RSpec::Structure::TypeSafe::Cache do
  let(:inner_client) { FakeTypeSafeClient.new(probability: 0.8) }
  let(:cache_path) { File.join(tmpdir, "jev_cache.json") }
  let(:tmpdir) { Dir.mktmpdir }
  let(:cache) { described_class.new(client: inner_client, model: "jev-latest", path: cache_path) }

  after { FileUtils.remove_entry(tmpdir) }

  context "when there is a cache miss" do
    it "delegates to the client" do
      probability = cache.noul(state: "when the user is an admin", instructions: "instructions")

      expect(probability).to eq(0.8)
      expect(inner_client.calls.size).to eq(1)
    end
  end

  context "when the cache already has an entry" do
    it "returns the cached result without calling the client again" do
      cache.noul(state: "when the user is an admin", instructions: "instructions")
      probability = cache.noul(state: "when the user is an admin", instructions: "instructions")

      expect(probability).to eq(0.8)
      expect(inner_client.calls.size).to eq(1)
    end
  end

  context "when a new instance loads the same cache file" do
    it "reuses the persisted cache without calling the client again" do
      cache.noul(state: "when the user is an admin", instructions: "instructions")

      reloaded = described_class.new(client: inner_client, model: "jev-latest", path: cache_path)
      reloaded.noul(state: "when the user is an admin", instructions: "instructions")

      expect(inner_client.calls.size).to eq(1)
    end
  end

  context "when a different model is used" do
    it "treats it as a different cache entry" do
      cache.noul(state: "when the user is an admin", instructions: "instructions")

      other = described_class.new(client: inner_client, model: "jev-2", path: cache_path)
      other.noul(state: "when the user is an admin", instructions: "instructions")

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
    # the public `#noul` API, rather than reaching into the private
    # `default_path` method or `@path` directly.
    def expect_default_path(path)
      allow(File).to receive(:exist?).and_return(false)
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)

      described_class.new(client: inner_client, model: "jev-latest")
                     .noul(state: "when the user is an admin", instructions: "instructions")

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
