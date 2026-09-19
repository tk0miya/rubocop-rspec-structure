# frozen_string_literal: true

module RuboCop
  module RSpec
    module Structure
      module TypeSafe
        # Base class for anything that keeps a Noul judgment from being
        # obtained: a missing API key, a network failure, or a malformed
        # response. Callers can rescue this single class regardless of which
        # client implementation raised it.
        class Error < StandardError; end
      end
    end
  end
end
