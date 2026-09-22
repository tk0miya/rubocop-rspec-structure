# frozen_string_literal: true

RSpec.describe RuboCop::RSpec::Structure::TypeSafe::NullClient do
  subject(:client) { described_class.new }

  describe "#nouls" do
    it "returns an empty hash regardless of the items given" do
      item = { id: "a", state: "when the user is an admin", instructions: "instructions", criteria: nil }

      expect(client.nouls([item])).to eq({})
    end
  end
end
