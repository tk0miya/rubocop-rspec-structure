# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RuboCop
  module RSpec
    module Structure
      module TypeSafe
        # Thin HTTP client for TypeSafe AI's System One API
        # (https://docs.typesafe.ai). Sends one or more Noul (yes/no)
        # questions and returns the probability that each answer is yes.
        #
        # Deliberately built on Net::HTTP rather than a third-party HTTP gem:
        # this gem is loaded into every consumer's Gemfile, and pulling in
        # e.g. Faraday risks colliding with a version the consumer already
        # pins. A single JSON endpoint does not need more than the stdlib.
        class Client
          ENDPOINT = URI("https://api.typesafe.ai/v1/systemone")

          class TimeoutError < Error
          end

          class RequestError < Error
          end

          # @rbs api_key: String
          # @rbs model: String
          # @rbs timeout: Integer
          def initialize(api_key:, model:, timeout:) #: void
            @api_key = api_key
            @model = model
            @timeout = timeout
          end

          # Batches several independent Noul questions into a single HTTP
          # call. Each item carries its own `state`, but Jev's wire format
          # has only one `state` per request, shared by every question in
          # it — so each item's `state` is folded into that item's own
          # `instructions` instead, and the request-level `state` is left
          # empty. This relies on questions running in isolation from
          # each other against the shared state, as mizchi/jev-
          # playground's batching reports describe — that claim is not
          # independently verified against the live API by this gem, so
          # treat it as the working assumption behind this method, not a
          # guarantee.
          # @rbs items: Array[NoulQuestion]
          def nouls(items) #: Hash[String, Float]
            return {} if items.empty?

            response = post(batch_request_body(items))
            items.to_h { [_1.id, extract_probability(response, _1.id)] }
          end

          private

          attr_reader :api_key #: String
          attr_reader :model #: String
          attr_reader :timeout #: Integer

          # @rbs items: Array[NoulQuestion]
          def batch_request_body(items) #: Hash[Symbol, untyped]
            {
              state: "",
              model:,
              questions: items.to_h { [_1.id, batched_question(_1)] }
            }
          end

          # @rbs item: NoulQuestion
          def batched_question(item) #: Hash[Symbol, untyped]
            {
              type: "noul",
              instructions: "#{item.instructions}\n\n---\nState:\n#{item.state}",
              criteria: item.criteria
            }.compact
          end

          # @rbs body: Hash[Symbol, untyped]
          def post(body) #: Hash[String, untyped]
            request = Net::HTTP::Post.new(ENDPOINT)
            request["Authorization"] = "Bearer #{api_key}"
            request["Content-Type"] = "application/json"
            request.body = JSON.generate(body)

            http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
            http.use_ssl = true
            http.open_timeout = timeout
            http.read_timeout = timeout

            response = perform(http, request)
            parse_response(response)
          end

          # @rbs http: Net::HTTP
          # @rbs request: Net::HTTP::Post
          def perform(http, request) #: Net::HTTPResponse
            http.request(request)
          rescue Timeout::Error => e
            raise TimeoutError, e.message
          rescue StandardError => e
            raise RequestError, e.message
          end

          # @rbs response: Net::HTTPResponse
          def parse_response(response) #: Hash[String, untyped]
            unless response.is_a?(Net::HTTPSuccess)
              raise RequestError, "TypeSafe API returned #{response.code}: #{response.body}"
            end

            JSON.parse(response.body)
          rescue JSON::ParserError => e
            raise RequestError, "Failed to parse TypeSafe API response: #{e.message}"
          end

          # @rbs response: Hash[String, untyped]
          # @rbs key: String
          def extract_probability(response, key) #: Float
            probability = response.dig("nouls", key, "noul")
            unless probability.is_a?(Integer) || probability.is_a?(Float)
              raise RequestError, "TypeSafe API response missing nouls.#{key}.noul"
            end

            probability.to_f
          end
        end
      end
    end
  end
end
