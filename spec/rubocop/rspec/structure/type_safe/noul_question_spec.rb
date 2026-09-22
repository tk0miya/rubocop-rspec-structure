# frozen_string_literal: true

RSpec.describe RuboCop::RSpec::Structure::TypeSafe::NoulQuestion do
  subject(:question) { described_class.new(id: "a", state: "state", instructions: "instructions", criteria: nil) }

  describe "#cache_key" do
    context "when called more than once" do
      it "returns the same, memoized value instead of recomputing it" do
        allow(Digest::SHA256).to receive(:hexdigest).and_call_original

        first = question.cache_key
        second = question.cache_key

        expect(first).to eq(second)
        expect(Digest::SHA256).to have_received(:hexdigest).once
      end
    end

    context "with a different id but the same state/instructions/criteria" do
      it "returns the same value" do
        other = described_class.new(id: "b", state: "state", instructions: "instructions", criteria: nil)

        expect(other.cache_key).to eq(question.cache_key)
      end
    end

    context "with a different state" do
      it "returns a different value" do
        other = described_class.new(id: "a", state: "other state", instructions: "instructions", criteria: nil)

        expect(other.cache_key).not_to eq(question.cache_key)
      end
    end

    context "with different instructions" do
      it "returns a different value" do
        other = described_class.new(id: "a", state: "state", instructions: "other instructions", criteria: nil)

        expect(other.cache_key).not_to eq(question.cache_key)
      end
    end

    context "with different criteria" do
      it "returns a different value" do
        other = described_class.new(
          id: "a", state: "state", instructions: "instructions", criteria: { "true" => "x" }
        )

        expect(other.cache_key).not_to eq(question.cache_key)
      end
    end
  end
end
