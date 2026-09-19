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
          # @rbs path: String
          def initialize(client:, model:, path:) #: void
            @client = client
            @model = model
            @path = path
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
        end
      end
    end
  end
end
