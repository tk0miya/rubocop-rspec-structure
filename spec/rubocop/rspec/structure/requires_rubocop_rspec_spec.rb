# frozen_string_literal: true

RSpec.describe RuboCop::RSpec::Structure::RequiresRuboCopRspec do
  let(:cop_class) do
    klass = Class.new(RuboCop::Cop::Base) do
      include RuboCop::RSpec::Structure::RequiresRuboCopRspec
    end
    stub_const("TestCopForRequiresRuboCopRspec", klass)
  end
  let(:cop) { cop_class.new(config) }

  # `Language.config` is process-global state that other spec files also set
  # (without resetting it) as a side effect of running their own cop, so
  # starting from a known value here is what makes the "sets it" assertion
  # below prove the assignment happened, rather than passing by coincidence
  # depending on suite run order.
  before { RuboCop::RSpec::Language.config = nil }

  context "when the merged config has RSpec/Language" do
    let(:config) { RuboCop::Config.new({ "RSpec" => { "Language" => RSPEC_LANGUAGE_CONFIG } }, File::NULL) }

    it "sets Language.config from it, and does not raise" do
      expect { cop.on_new_investigation }.not_to raise_error

      expect(RuboCop::RSpec::Language.config).to eq(RSPEC_LANGUAGE_CONFIG)
    end
  end

  context "when the merged config has no RSpec/Language" do
    let(:config) { RuboCop::Config.new({}, File::NULL) }

    it "raises a clear, actionable error" do
      expect { cop.on_new_investigation }.to raise_error(
        RuboCop::RSpec::Structure::Error,
        'TestCopForRequiresRuboCopRspec requires "rubocop-rspec" to also be listed under ' \
        "`plugins:` in .rubocop.yml."
      )
    end
  end
end
