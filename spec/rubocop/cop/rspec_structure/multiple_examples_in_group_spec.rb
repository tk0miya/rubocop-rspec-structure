# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpecStructure::MultipleExamplesInGroup, :config do
  let(:cop_config) { {} }

  context "when a group has one example directly nested" do
    it "does not flag it" do
      expect_no_offenses(<<~RUBY)
        context "when the user is an admin" do
          it "allows deletion" do
          end
        end
      RUBY
    end
  end

  context "when a group has no examples directly nested" do
    it "does not flag it" do
      expect_no_offenses(<<~RUBY)
        context "when the user is an admin" do
          let(:user) { create(:user, :admin) }
        end
      RUBY
    end
  end

  context "when a group has an empty body" do
    it "does not flag it" do
      expect_no_offenses(<<~RUBY)
        context "when the user is an admin" do
        end
      RUBY
    end
  end

  context "when a group has one example alongside other statements" do
    it "does not flag it" do
      expect_no_offenses(<<~RUBY)
        context "when the user is an admin" do
          let(:user) { create(:user, :admin) }

          it "allows deletion" do
          end
        end
      RUBY
    end
  end

  context "when a context has more than one example directly nested" do
    it "flags it" do
      expect_offense(<<~RUBY)
        context "when the user is an admin" do
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This block has 2 examples directly nested. Merge them into a single example, or add a nested context for each example to distinguish their conditions.
          it "allows deletion" do
          end

          it "allows editing" do
          end
        end
      RUBY
    end
  end

  context "when a describe has more than one example directly nested" do
    it "flags it too" do
      expect_offense(<<~RUBY)
        describe User do
        ^^^^^^^^^^^^^ This block has 2 examples directly nested. Merge them into a single example, or add a nested context for each example to distinguish their conditions.
          it "allows deletion" do
          end

          it "allows editing" do
          end
        end
      RUBY
    end
  end

  context "when the extra examples live in a nested group instead" do
    it "flags only the nested group, not the outer one" do
      expect_offense(<<~RUBY)
        context "when the user is an admin" do
          it "allows deletion" do
          end

          context "and the record is archived" do
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This block has 2 examples directly nested. Merge them into a single example, or add a nested context for each example to distinguish their conditions.
            it "still allows deletion" do
            end

            it "logs the action" do
            end
          end
        end
      RUBY
    end
  end

  context "when nested groups each have a single example" do
    it "does not flag any of them" do
      expect_no_offenses(<<~RUBY)
        context "when the user is an admin" do
          context "and the record is archived" do
            it "still allows deletion" do
            end
          end

          context "and the record is active" do
            it "allows deletion" do
            end
          end
        end
      RUBY
    end
  end

  context "when a shared group has one example directly nested" do
    it "does not flag it" do
      expect_no_offenses(<<~RUBY)
        shared_examples "an admin" do
          it "allows deletion" do
          end
        end
      RUBY
    end
  end

  context "when a shared group has more than one example directly nested" do
    context "with shared_examples" do
      it "flags it" do
        expect_offense(<<~RUBY)
          shared_examples "an admin" do
          ^^^^^^^^^^^^^^^^^^^^^^^^^^ This block has 2 examples directly nested. Merge them into a single example, or add a nested context for each example to distinguish their conditions.
            it "allows deletion" do
            end

            it "allows editing" do
            end
          end
        RUBY
      end
    end

    context "with shared_examples_for" do
      it "flags it" do
        expect_offense(<<~RUBY)
          shared_examples_for "an admin" do
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This block has 2 examples directly nested. Merge them into a single example, or add a nested context for each example to distinguish their conditions.
            it "allows deletion" do
            end

            it "allows editing" do
            end
          end
        RUBY
      end
    end

    context "with shared_context" do
      it "flags it" do
        expect_offense(<<~RUBY)
          shared_context "an admin" do
          ^^^^^^^^^^^^^^^^^^^^^^^^^ This block has 2 examples directly nested. Merge them into a single example, or add a nested context for each example to distinguish their conditions.
            it "allows deletion" do
            end

            it "allows editing" do
            end
          end
        RUBY
      end
    end
  end

  context "when a context nested inside a shared group has more than one example" do
    it "flags the nested context" do
      expect_offense(<<~RUBY)
        shared_examples "an admin" do
          context "when active" do
          ^^^^^^^^^^^^^^^^^^^^^ This block has 2 examples directly nested. Merge them into a single example, or add a nested context for each example to distinguish their conditions.
            it "allows deletion" do
            end

            it "allows editing" do
            end
          end
        end
      RUBY
    end
  end

  context "when the block uses a focused or skipped group alias" do
    context "with fcontext" do
      it "flags it" do
        expect_offense(<<~RUBY)
          fcontext "when the user is an admin" do
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This block has 2 examples directly nested. Merge them into a single example, or add a nested context for each example to distinguish their conditions.
            it "allows deletion" do
            end

            it "allows editing" do
            end
          end
        RUBY
      end
    end

    context "with xcontext" do
      it "flags it" do
        expect_offense(<<~RUBY)
          xcontext "when the user is an admin" do
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This block has 2 examples directly nested. Merge them into a single example, or add a nested context for each example to distinguish their conditions.
            it "allows deletion" do
            end

            it "allows editing" do
            end
          end
        RUBY
      end
    end

    context "with fdescribe" do
      it "flags it" do
        expect_offense(<<~RUBY)
          fdescribe User do
          ^^^^^^^^^^^^^^ This block has 2 examples directly nested. Merge them into a single example, or add a nested context for each example to distinguish their conditions.
            it "allows deletion" do
            end

            it "allows editing" do
            end
          end
        RUBY
      end
    end
  end
end
