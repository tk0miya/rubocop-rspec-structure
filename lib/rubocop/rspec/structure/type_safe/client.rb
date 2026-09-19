# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RuboCop
  module RSpec
    module Structure
      module TypeSafe
        # Thin HTTP client for TypeSafe AI's System One API
        # (https://docs.typesafe.ai). Sends a single Noul (yes/no) question
        # and returns the probability that the answer is yes.
        #
        # Deliberately built on Net::HTTP rather than a third-party HTTP gem:
        # this gem is loaded into every consumer's Gemfile, and pulling in
        # e.g. Faraday risks colliding with a version the consumer already
        # pins. A single JSON endpoint does not need more than the stdlib.
        class Client
          ENDPOINT = URI("https://api.typesafe.ai/v1/systemone")
          QUESTION_KEY = "result"

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

          # @rbs state: String
          # @rbs instructions: String
          # @rbs criteria: Hash[String, String]?
          def noul(state:, instructions:, criteria: nil) #: Float
            response = post(request_body(state:, instructions:, criteria:))
            extract_probability(response)
          end

          private

          attr_reader :api_key #: String
          attr_reader :model #: String
          attr_reader :timeout #: Integer

          # @rbs state: String
          # @rbs instructions: String
          # @rbs criteria: Hash[String, String]?
          def request_body(state:, instructions:, criteria:) #: Hash[Symbol, untyped]
            {
              state:,
              model:,
              questions: {
                QUESTION_KEY => {
                  type: "noul",
                  instructions:,
                  criteria:
                }.compact
              }
            }
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
          def extract_probability(response) #: Float
            probability = response.dig("nouls", QUESTION_KEY, "noul")
            unless probability.is_a?(Integer) || probability.is_a?(Float)
              raise RequestError, "TypeSafe API response missing nouls.#{QUESTION_KEY}.noul"
            end

            probability.to_f
          end
        end
      end
    end
  end
end
