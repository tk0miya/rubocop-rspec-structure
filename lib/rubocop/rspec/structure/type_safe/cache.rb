# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module RuboCop
  module RSpec
    module Structure
      module TypeSafe
        # Memoizes Noul judgments on disk, keyed by the content of the
        # request (state + instructions + criteria + model). Repeated
        # rubocop runs over unchanged descriptions never pay for a second
        # API call, and the same input always yields the same offense.
        class Cache
          # @rbs client: untyped
          # @rbs model: String
          # @rbs path: String?
          def initialize(client:, model:, path: nil) #: void
            @client = client
            @model = model
            @path = path || default_path
            @store = load_store
          end

          # @rbs state: String
          # @rbs instructions: String
          # @rbs criteria: Hash[String, String]?
          def noul(state:, instructions:, criteria: nil) #: Float
            key = cache_key(state:, instructions:, criteria:)

            return store.fetch(key) if store.key?(key)

            probability = client.noul(state:, instructions:, criteria:)
            store[key] = probability
            save_store
            probability
          end

          private

          attr_reader :client #: untyped
          attr_reader :model #: String
          attr_reader :path #: String
          attr_reader :store #: Hash[String, Float]

          def load_store #: Hash[String, Float]
            return {} unless File.exist?(path)

            JSON.parse(File.read(path))
          rescue JSON::ParserError
            {}
          end

          def save_store #: void
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, JSON.generate(store))
          end

          # @rbs state: String
          # @rbs instructions: String
          # @rbs criteria: Hash[String, String]?
          def cache_key(state:, instructions:, criteria:) #: String
            Digest::SHA256.hexdigest(JSON.generate({ state:, instructions:, criteria:, model: }))
          end

          # A Jev judgment is a pure function of (state, instructions,
          # criteria, model), so it is equally valid for every project on
          # this machine, not just the current one. Following the XDG Base
          # Directory Specification (rather than a path under this project)
          # lets that cache be shared across all of them.
          def default_path #: String
            File.join(cache_home, "rubocop-rspec-structure", "jev_cache.json")
          end

          # Falls back to a project-relative path when the home directory can't be
          # resolved at all, e.g. a minimal container running as an arbitrary UID
          # with no matching passwd entry.
          def cache_home #: String
            xdg_cache_home = ENV.fetch("XDG_CACHE_HOME", nil)
            return xdg_cache_home unless xdg_cache_home.nil? || xdg_cache_home.empty?

            home = user_home
            return File.join(home, ".cache") unless home.nil? || home.empty?

            "tmp"
          end

          # Dir.home consults $HOME first, then falls back to the OS user database
          # (e.g. /etc/passwd), which is more robust than reading ENV["HOME"] alone.
          # It raises ArgumentError when neither resolves.
          def user_home #: String?
            Dir.home
          rescue ArgumentError
            nil
          end
        end
      end
    end
  end
end
