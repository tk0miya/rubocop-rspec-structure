# frozen_string_literal: true

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
          # @rbs client: _Client
          # @rbs model: String
          # @rbs path: String?
          def initialize(client:, model:, path: nil) #: void
            @client = client
            @model = model
            @path = path || default_path
            @store = load_store
          end

          # Cache-aware batch lookup: items already on disk are served
          # without touching the client at all, and only the misses go
          # out, together, as a single call to `client.nouls`. Each item
          # is still cached under its own (state, instructions, criteria,
          # model) key — the batching is purely a transport-level detail
          # the cache itself doesn't need to know about.
          # @rbs items: Array[NoulQuestion]
          def nouls(items) #: Hash[String, Float]
            hits, misses = split_hits_and_misses(items)
            return hits if misses.empty?

            fetched = client.nouls(misses)
            store_fetched(misses, fetched)

            hits.merge(fetched)
          end

          private

          attr_reader :client #: _Client
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

          # Folds `model` into an item's own (model-independent) cache key:
          # the same question asked of two different Jev models is two
          # different cache entries.
          # @rbs item: NoulQuestion
          def cache_key(item) #: String
            "#{model}:#{item.cache_key}"
          end

          # Looks up each item in the on-disk store. A hit resolves
          # straight to its cached probability; a miss is simply the item
          # itself — `store_fetched` recomputes its cache key once the
          # client answers, which costs far less than the API call a miss
          # is about to make anyway.
          # @rbs items: Array[NoulQuestion]
          def split_hits_and_misses(items) #: [Hash[String, Float], Array[NoulQuestion]]
            hits = {} #: Hash[String, Float]
            misses = [] #: Array[NoulQuestion]

            items.each do |item|
              key = cache_key(item)
              if store.key?(key)
                hits[item.id] = store.fetch(key)
              else
                misses << item
              end
            end

            [hits, misses]
          end

          # @rbs misses: Array[NoulQuestion]
          # @rbs fetched: Hash[String, Float]
          def store_fetched(misses, fetched) #: void
            misses.each { store[cache_key(_1)] = fetched.fetch(_1.id) }
            save_store
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
