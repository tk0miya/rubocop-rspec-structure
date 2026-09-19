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
end
