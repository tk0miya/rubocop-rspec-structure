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

          # Cache-aware batch lookup: items already on disk are served
          # without touching the client at all, and only the misses go
          # out, together, as a single call to `client.nouls`. Each item
          # is still cached under its own (state, instructions, criteria,
          # model) key — the batching is purely a transport-level detail
          # the cache itself doesn't need to know about.
          # @rbs items: Array[Hash[Symbol, untyped]]
          def nouls(items) #: Hash[String, Float]
            hits, misses = split_hits_and_misses(items)
            return hits if misses.empty?

            fetched = client.nouls(misses)
            store_fetched(misses, fetched)

            hits.merge(fetched)
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

          # Looks up each item in the on-disk store. A hit resolves
          # straight to its cached probability; a miss carries its
          # (not-yet-looked-up) cache key forward, since `store_fetched`
          # will need it once the client answers. The two aren't the same
          # shape — a hit is already a final `{id => probability}` value,
          # a miss is still the original item plus that key — so this
          # isn't a same-type partition, just a single pass over `items`
          # that buckets each one into whichever of the two it resolves
          # to.
          # @rbs items: Array[Hash[Symbol, untyped]]
          def split_hits_and_misses(items) #: [Hash[String, Float], Array[Hash[Symbol, untyped]]]
            hits = {} #: Hash[String, Float]
            misses = [] #: Array[Hash[Symbol, untyped]]

            items.each do |item|
              key = cache_key(state: item[:state], instructions: item[:instructions], criteria: item[:criteria])
              if store.key?(key)
                hits[item[:id]] = store.fetch(key)
              else
                misses << item.merge(cache_key: key)
              end
            end

            [hits, misses]
          end

          # @rbs misses: Array[Hash[Symbol, untyped]]
          # @rbs fetched: Hash[String, Float]
          def store_fetched(misses, fetched) #: void
            misses.each { store[_1[:cache_key]] = fetched.fetch(_1[:id]) }
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
