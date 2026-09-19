# frozen_string_literal: true

# Test double for `RuboCop::RSpec::Structure::TypeSafe::Client`. Specs use
# this instead of the real client so they never touch the network.
class FakeTypeSafeClient
  attr_reader :calls

  def initialize(probability: 0.0, error: nil)
    @probability = probability
    @error = error
    @calls = []
  end

  def noul(state:, instructions:, criteria: nil)
    @calls << { state:, instructions:, criteria: }
    raise @error if @error

    @probability
  end

  def called?
    !@calls.empty?
  end
end
