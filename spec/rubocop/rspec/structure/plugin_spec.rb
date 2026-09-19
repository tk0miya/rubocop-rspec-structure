# frozen_string_literal: true

RSpec.describe RuboCop::RSpec::Structure::Plugin do
  subject(:plugin) { described_class.new }

  describe "#about" do
    it "identifies the gem" do
      about = plugin.about

      expect(about.name).to eq("rubocop-rspec-structure")
      expect(about.homepage).to eq("https://github.com/tk0miya/rubocop-rspec-structure")
    end
  end

  describe "#supported?" do
    context "with the rubocop engine" do
      it "is supported" do
        context = LintRoller::Context.new(engine: :rubocop)

        expect(plugin.supported?(context)).to be(true)
      end
    end

    context "with other engines" do
      it "is not supported" do
        context = LintRoller::Context.new(engine: :standard)

        expect(plugin.supported?(context)).to be(false)
      end
    end
  end

  describe "#rules" do
    it "points at config/default.yml, which exists" do
      rules = plugin.rules(nil)

      expect(rules.type).to eq(:path)
      expect(File.exist?(rules.value)).to be(true)
      expect(File.basename(rules.value)).to eq("default.yml")
    end
  end
end
