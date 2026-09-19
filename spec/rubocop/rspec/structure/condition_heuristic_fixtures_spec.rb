# frozen_string_literal: true

require "yaml"

# These locals are read-only closures used to generate the example list
# below, not mutable state shared across examples, so leaking them in is
# intentional.
# rubocop:disable-next RSpec/LeakyLocalVariable
RSpec.describe RuboCop::RSpec::Structure::ConditionHeuristic do
  root = File.expand_path("../../../..", __dir__)

  default_keywords = YAML.load_file(File.join(root, "config", "default.yml"))
                         .fetch("RSpecStructure/ConditionInExample")
                         .fetch("ConditionKeywords")

  subject(:heuristic) { described_class.new(keywords: default_keywords) }

  fixtures = YAML.load_file(File.join(root, "spec", "fixtures", "example_descriptions.yml"))

  fixtures.fetch("bad").each do |description|
    context "with #{description.inspect}" do
      it "is flagged as containing a condition" do
        expect(heuristic).to be_condition(description)
      end
    end
  end

  fixtures.fetch("good").each do |description|
    context "with #{description.inspect}" do
      it "is not flagged" do
        expect(heuristic).not_to be_condition(description)
      end
    end
  end
end
