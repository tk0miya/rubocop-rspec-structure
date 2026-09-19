# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpecStructure::AsymmetricContexts, :config do
  # CacheEnabled: false keeps every Jev-path example here from wrapping the
  # stubbed client in the real, disk-backed Cache — otherwise separate
  # examples judging the same description text would collide on the same
  # cache file and see each other's cached probability.
  let(:cop_config) { { "CacheEnabled" => false } }
  let(:other_cops) { { "RSpec" => { "Language" => RSPEC_LANGUAGE_CONFIG } } }
  let(:always_in_scope) { instance_double(RuboCop::RSpec::Structure::GitDiffScope, changed_file?: true) }

  before do
    allow(RuboCop::RSpec::Structure::GitDiffScope).to receive(:for).and_return(always_in_scope)
  end

  after do
    ENV.delete("TYPESAFE_API_KEY")
  end

  def stub_type_safe_client(client)
    allow(RuboCop::RSpec::Structure::TypeSafe::Client).to receive(:new).and_return(client)
  end

  context "when a group has no context directly nested" do
    it "does not flag anything" do
      expect_no_offenses(<<~RUBY)
        describe "#dashboard" do
          it "renders" do
          end
        end
      RUBY
    end
  end

  context "when a group has exactly one context directly nested" do
    context "with a stubbed TypeSafe client and no TYPESAFE_API_KEY" do
      it "flags it mechanically, without ever calling the client" do
        client = FakeTypeSafeClient.new(probability: 0.9)
        stub_type_safe_client(client)

        expect_offense(<<~RUBY)
          describe "#dashboard" do
            context "when the user is not logged in" do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This is the only context directly nested here. If it expresses a real condition, add a sibling context for the complementary case; if there is no real condition, remove the context wrapper and flatten these examples into the parent group.
              it "redirects to the login page" do
              end
            end
          end
        RUBY

        expect(client).not_to be_called
      end
    end

    context "with the git diff reporting the group as unchanged" do
      it "still flags it (CheckScope is ignored by this mechanical check)" do
        allow(RuboCop::RSpec::Structure::GitDiffScope)
          .to receive(:for)
          .and_return(instance_double(RuboCop::RSpec::Structure::GitDiffScope, changed_file?: false))

        expect_offense(<<~RUBY)
          describe "#dashboard" do
            context "when the user is not logged in" do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This is the only context directly nested here. If it expresses a real condition, add a sibling context for the complementary case; if there is no real condition, remove the context wrapper and flatten these examples into the parent group.
              it "redirects to the login page" do
              end
            end
          end
        RUBY
      end
    end

    context "with a shared_context sibling alongside it" do
      it "does not count the shared_context, so the lone context is still flagged" do
        expect_offense(<<~RUBY)
          describe "#dashboard" do
            context "when the user is not logged in" do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This is the only context directly nested here. If it expresses a real condition, add a sibling context for the complementary case; if there is no real condition, remove the context wrapper and flatten these examples into the parent group.
            end

            shared_context "some shared setup" do
            end
          end
        RUBY
      end
    end

    context "with only a shared_context directly nested" do
      it "does not flag it (a shared_context is not itself a compared sibling)" do
        expect_no_offenses(<<~RUBY)
          describe "#dashboard" do
            shared_context "when the user is not logged in" do
            end
          end
        RUBY
      end
    end

    context "with other, non-context statements alongside it" do
      it "is still flagged, since only context siblings count toward this check" do
        expect_offense(<<~RUBY)
          describe "#dashboard" do
            let(:user) { create(:user) }

            context "when the user is not logged in" do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This is the only context directly nested here. If it expresses a real condition, add a sibling context for the complementary case; if there is no real condition, remove the context wrapper and flatten these examples into the parent group.
            end
          end
        RUBY
      end
    end
  end

  context "when a group has two or more contexts directly nested" do
    context "without a TYPESAFE_API_KEY" do
      it "does not call the TypeSafe client and reports no offense" do
        client = FakeTypeSafeClient.new(probability: 0.9)
        stub_type_safe_client(client)

        expect_no_offenses(<<~RUBY)
          describe "#dashboard" do
            context "when the user is not logged in" do
            end

            context "when the request body is malformed" do
            end
          end
        RUBY

        expect(client).not_to be_called
      end
    end

    context "with a TYPESAFE_API_KEY configured" do
      before { ENV["TYPESAFE_API_KEY"] = "dummy" }

      context "when Jev's probability is at or above the threshold for every sibling" do
        it "flags each of them independently" do
          stub_type_safe_client(FakeTypeSafeClient.new(probability: 0.9))

          expect_offense(<<~RUBY)
            describe "#dashboard" do
              context "when the user is not logged in" do
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
              end

              context "when the request body is malformed" do
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
              end
            end
          RUBY
        end
      end

      context "when Jev's probability is below the threshold" do
        it "does not flag anything" do
          stub_type_safe_client(FakeTypeSafeClient.new(probability: 0.2))

          expect_no_offenses(<<~RUBY)
            describe "#dashboard" do
              context "when the user is not logged in" do
              end

              context "when the user is logged in" do
              end
            end
          RUBY
        end
      end

      context "when only one of several siblings crosses the threshold" do
        it "flags only that sibling" do
          client = instance_double(RuboCop::RSpec::Structure::TypeSafe::Client)
          allow(RuboCop::RSpec::Structure::TypeSafe::Client).to receive(:new).and_return(client)
          allow(client).to receive(:noul) do |state:, **|
            # Only the first line names the target being judged; "payment succeeds"
            # would also appear on a later line when it's listed as someone else's
            # sibling, so checking the whole state would wrongly match both targets.
            state.lines.first.include?("payment succeeds") ? 0.9 : 0.1
          end

          expect_offense(<<~RUBY)
            describe "#checkout" do
              context "when the payment succeeds" do
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
              end

              context "when the shipping address is invalid" do
              end
            end
          RUBY
        end
      end

      context "when the API call fails" do
        let(:error) { RuboCop::RSpec::Structure::TypeSafe::Client::RequestError.new("boom") }

        context "when OnJevError is skip (default)" do
          it "reports no offense" do
            stub_type_safe_client(FakeTypeSafeClient.new(error:))

            expect_no_offenses(<<~RUBY)
              describe "#dashboard" do
                context "when the user is not logged in" do
                end

                context "when the request body is malformed" do
                end
              end
            RUBY
          end
        end

        context "when OnJevError is raise" do
          let(:cop_config) { { "CacheEnabled" => false, "OnJevError" => "raise" } }

          it "re-raises the error" do
            stub_type_safe_client(FakeTypeSafeClient.new(error:))

            expect { expect_no_offenses(<<~RUBY) }.to raise_error(error.class)
              describe "#dashboard" do
                context "when the user is not logged in" do
                end

                context "when the request body is malformed" do
                end
              end
            RUBY
          end
        end
      end
    end

    context "with CheckScope: diff (default)" do
      before { ENV["TYPESAFE_API_KEY"] = "dummy" }

      context "when the file is unchanged" do
        it "skips every sibling" do
          allow(RuboCop::RSpec::Structure::GitDiffScope)
            .to receive(:for)
            .and_return(instance_double(RuboCop::RSpec::Structure::GitDiffScope, changed_file?: false))
          client = FakeTypeSafeClient.new(probability: 0.9)
          stub_type_safe_client(client)

          expect_no_offenses(<<~RUBY)
            describe "#dashboard" do
              context "when the user is not logged in" do
              end

              context "when the request body is malformed" do
              end
            end
          RUBY

          expect(client).not_to be_called
        end
      end

      context "when the file changed" do
        # Checked at file granularity, not line granularity: even a
        # sibling whose own line is untouched is judged once anything in
        # the file changed. `changed_file?` takes only a path, not a
        # line — the assertion below locks that contract in.
        it "judges every sibling, even ones whose own lines are untouched" do
          diff_scope = instance_double(RuboCop::RSpec::Structure::GitDiffScope, changed_file?: true)
          allow(RuboCop::RSpec::Structure::GitDiffScope).to receive(:for).and_return(diff_scope)
          stub_type_safe_client(FakeTypeSafeClient.new(probability: 0.9))

          expect_offense(<<~RUBY)
            describe "#dashboard" do
              context "when the user is not logged in" do
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
              end

              context "when the request body is malformed" do
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
              end
            end
          RUBY

          expect(diff_scope).to have_received(:changed_file?).with(anything)
        end
      end
    end

    context "with CheckScope: full" do
      let(:cop_config) { { "CacheEnabled" => false, "CheckScope" => "full" } }

      before { ENV["TYPESAFE_API_KEY"] = "dummy" }

      it "never consults the git diff" do
        expect(RuboCop::RSpec::Structure::GitDiffScope).not_to receive(:for) # rubocop:disable RSpec/MessageSpies
        stub_type_safe_client(FakeTypeSafeClient.new(probability: 0.9))

        expect_offense(<<~RUBY)
          describe "#dashboard" do
            context "when the user is not logged in" do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
            end

            context "when the request body is malformed" do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
            end
          end
        RUBY
      end
    end

    context "when a sibling's description is interpolated (dstr)" do
      before { ENV["TYPESAFE_API_KEY"] = "dummy" }

      it "excludes it from the comparison sent to Jev" do
        client = FakeTypeSafeClient.new(probability: 0.9)
        stub_type_safe_client(client)

        expect_offense(<<~'RUBY')
          describe "#dashboard" do
            context "when the user is not logged in" do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
            end

            context "when #{condition}" do
            end
          end
        RUBY

        expect(client.calls.first[:state]).to include("(none)")
      end
    end

    context "when the block uses a focused or skipped context alias" do
      it "counts fcontext and xcontext toward the sibling set" do
        expect_offense(<<~RUBY)
          describe "#dashboard" do
            fcontext "when the user is not logged in" do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This is the only context directly nested here. If it expresses a real condition, add a sibling context for the complementary case; if there is no real condition, remove the context wrapper and flatten these examples into the parent group.
            end
          end
        RUBY
      end
    end
  end

  context "when a nested group has its own, independent set of contexts" do
    it "judges each level's direct siblings on their own, not the grandchildren" do
      ENV["TYPESAFE_API_KEY"] = "dummy"
      stub_type_safe_client(FakeTypeSafeClient.new(probability: 0.9))

      expect_offense(<<~RUBY)
        describe "#dashboard" do
          context "when the user is not logged in" do
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
            context "and the request comes from a bot" do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
            end

            context "and the request comes from a browser" do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
            end
          end

          context "when the request is throttled" do
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This context describes a condition with no sibling context for its natural counterpart (estimated probability: 0.90). Add a `context` for the complementary case, or move existing coverage of it into this tree.
          end
        end
      RUBY
    end
  end

  context "when a shared group has exactly one context directly nested" do
    it "flags it the same way as any other group" do
      expect_offense(<<~RUBY)
        shared_examples "a login-aware feature" do
          context "when the user is not logged in" do
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This is the only context directly nested here. If it expresses a real condition, add a sibling context for the complementary case; if there is no real condition, remove the context wrapper and flatten these examples into the parent group.
          end
        end
      RUBY
    end
  end

  context "when a shared_context has exactly one context directly nested" do
    it "still checks its own direct context children" do
      expect_offense(<<~RUBY)
        shared_context "a login-aware feature" do
          context "when the user is not logged in" do
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ This is the only context directly nested here. If it expresses a real condition, add a sibling context for the complementary case; if there is no real condition, remove the context wrapper and flatten these examples into the parent group.
          end
        end
      RUBY
    end
  end
end
