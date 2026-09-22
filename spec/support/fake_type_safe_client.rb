# frozen_string_literal: true

# Test double for `RuboCop::RSpec::Structure::TypeSafe::Client`. Specs use
# this instead of the real client so they never touch the network.
class FakeTypeSafeClient
  attr_reader :calls

  # `probability` may be a plain Float (every question gets the same
  # answer) or a callable accepting the same keywords as one item's
  # state/instructions/criteria, for specs that need a batch's items to
  # resolve differently from each other.
  def initialize(probability: 0.0, error: nil)
    @probability = probability
    @error = error
    @calls = []
  end

  def nouls(items)
    items.to_h do |item|
      state, instructions, criteria = item.values_at(:state, :instructions, :criteria)
      @calls << { state:, instructions:, criteria: }
      raise @error if @error

      [item[:id], resolve_probability(state:, instructions:, criteria:)]
    end
  end

  def called?
    !@calls.empty?
  end

  private

  def resolve_probability(**)
    @probability.respond_to?(:call) ? @probability.call(**) : @probability
  end
end
