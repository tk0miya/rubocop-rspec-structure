# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpecStructure::ConditionInExample, :config do
  let(:keywords) { %w[when の場合 場合 のとき if] }
  # CacheEnabled: false keeps every Jev-path example here from wrapping the
  # stubbed client in the real, disk-backed Cache — otherwise separate
  # examples judging the same description text would collide on the same
  # cache file and see each other's cached probability.
  let(:cop_config) { { "ConditionKeywords" => keywords, "CacheEnabled" => false } }
  let(:other_cops) { { "RSpec" => { "Language" => RSPEC_LANGUAGE_CONFIG } } }
  let(:always_in_scope) { instance_double(RuboCop::RSpec::Structure::GitDiffScope, changed?: true) }

  before do
    allow(RuboCop::RSpec::Structure::GitDiffScope).to receive(:for).and_return(always_in_scope)
  end

  after do
    ENV.delete("TYPESAFE_API_KEY")
  end

  def stub_type_safe_client(client)
    allow(RuboCop::RSpec::Structure::TypeSafe::Client).to receive(:new).and_return(client)
  end

  def expect_cache_path(path)
    stub_type_safe_client(FakeTypeSafeClient.new(probability: 0.9))
    allow(RuboCop::RSpec::Structure::TypeSafe::Cache)
      .to receive(:new).and_return(FakeTypeSafeClient.new(probability: 0.9))

    expect_offense(<<~RUBY)
      it "admin users can delete records" do
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move the condition described here into a surrounding `context` block (estimated probability: 0.90).
      end
    RUBY

    expect(RuboCop::RSpec::Structure::TypeSafe::Cache)
      .to have_received(:new)
      .with(client: anything, model: "jev-latest", path:)
  end

  context "with the keyword heuristic" do
    context "when the description contains an English condition keyword" do
      it "flags the description" do
        expect_offense(<<~RUBY)
          it "when the user is an admin, allows deletion" do
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move the condition described here into a surrounding `context` block.
          end
        RUBY
      end
    end

    context "when the description contains a Japanese condition keyword" do
      it "flags the description" do
        expect_offense(<<~RUBY)
          it "管理者権限を持っている場合は削除できる" do
             ^^^^^^^^^^^^^^^^^^^^^ Move the condition described here into a surrounding `context` block.
          end
        RUBY
      end
    end

    context "when the description has no condition" do
      it "does not flag the description" do
        expect_no_offenses(<<~RUBY)
          it "allows deletion" do
          end
        RUBY
      end
    end

    context "when the heuristic already found a match" do
      it "does not call the TypeSafe client" do
        ENV["TYPESAFE_API_KEY"] = "dummy"
        client = FakeTypeSafeClient.new(probability: 0.9)
        stub_type_safe_client(client)

        expect_offense(<<~RUBY)
          it "when the user is an admin, allows deletion" do
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move the condition described here into a surrounding `context` block.
          end
        RUBY

        expect(client).not_to be_called
      end
    end
  end

  context "with a description the cop cannot judge as plain text" do
    context "when the example has no description at all" do
      it "does not flag it" do
        expect_no_offenses(<<~RUBY)
          it do
          end
        RUBY
      end
    end

    context "when the description is interpolated (dstr)" do
      it "does not flag it" do
        expect_no_offenses(<<~'RUBY')
          it "when #{condition}, allows deletion" do
          end
        RUBY
      end
    end

    context "when the description is not a string" do
      it "does not flag it" do
        expect_no_offenses(<<~RUBY)
          it :when_admin do
          end
        RUBY
      end
    end

    context "when the description is an empty string" do
      it "does not flag it" do
        expect_no_offenses(<<~RUBY)
          it "" do
          end
        RUBY
      end
    end
  end

  context "without a TYPESAFE_API_KEY" do
    it "does not call the TypeSafe client and reports no offense" do
      client = FakeTypeSafeClient.new(probability: 0.9)
      stub_type_safe_client(client)

      expect_no_offenses(<<~RUBY)
        it "admin users can delete records" do
        end
      RUBY

      expect(client).not_to be_called
    end
  end

  context "with a TYPESAFE_API_KEY configured" do
    before { ENV["TYPESAFE_API_KEY"] = "dummy" }

    context "when resolving the cache path" do
      # The default-path resolution algorithm itself (XDG_CACHE_HOME, HOME,
      # Dir.home fallbacks, ...) is `Cache`'s own responsibility and is
      # covered by its spec; this cop only needs to prove it wires
      # `CachePath` (or its absence) through correctly.
      context "when CachePath is configured" do
        let(:cop_config) { { "ConditionKeywords" => keywords, "CachePath" => "tmp/custom_cache.json" } }

        it "passes it through to the cache" do
          expect_cache_path("tmp/custom_cache.json")
        end
      end

      # Not configured and explicitly nil both resolve the same way here
      # (`cop_config[key] || default` with `default` itself now `nil`),
      # so one case covers both — see `ConfigOverride#env_or_config`.
      context "when CachePath is not configured (or explicitly nil)" do
        let(:cop_config) { { "ConditionKeywords" => keywords } }

        it "passes nil, letting the cache resolve its own default" do
          expect_cache_path(nil)
        end
      end
    end

    context "when Jev's probability is at or above the threshold" do
      it "flags the description" do
        stub_type_safe_client(FakeTypeSafeClient.new(probability: 0.9))

        expect_offense(<<~RUBY)
          it "admin users can delete records" do
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move the condition described here into a surrounding `context` block (estimated probability: 0.90).
          end
        RUBY
      end
    end

    context "when Jev's probability is below the threshold" do
      it "does not flag the description" do
        stub_type_safe_client(FakeTypeSafeClient.new(probability: 0.2))

        expect_no_offenses(<<~RUBY)
          it "admin users can delete records" do
          end
        RUBY
      end
    end

    context "when a file has several descriptions that need Jev's judgment" do
      it "batches them into a single call to the client's #nouls" do
        client = instance_double(RuboCop::RSpec::Structure::TypeSafe::Client)
        allow(RuboCop::RSpec::Structure::TypeSafe::Client).to receive(:new).and_return(client)
        allow(client).to receive(:nouls) { |items| items.to_h { [_1[:id], 0.9] } }

        expect_offense(<<~RUBY)
          it "admin users can delete records" do
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move the condition described here into a surrounding `context` block (estimated probability: 0.90).
          end

          it "viewer users cannot delete records" do
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move the condition described here into a surrounding `context` block (estimated probability: 0.90).
          end
        RUBY

        expect(client).to have_received(:nouls).once
      end
    end

    context "when the API call fails" do
      let(:error) { RuboCop::RSpec::Structure::TypeSafe::Client::RequestError.new("boom") }

      context "when OnJevError is skip (default)" do
        it "reports no offense" do
          stub_type_safe_client(FakeTypeSafeClient.new(error:))

          expect_no_offenses(<<~RUBY)
            it "admin users can delete records" do
            end
          RUBY
        end
      end

      context "when OnJevError is raise" do
        let(:cop_config) { { "ConditionKeywords" => keywords, "CacheEnabled" => false, "OnJevError" => "raise" } }

        it "re-raises the error" do
          stub_type_safe_client(FakeTypeSafeClient.new(error:))

          expect { expect_no_offenses(<<~RUBY) }.to raise_error(error.class)
            it "admin users can delete records" do
            end
          RUBY
        end
      end
    end
  end

  context "with CheckScope: diff (default)" do
    it "skips examples outside the git diff" do
      allow(RuboCop::RSpec::Structure::GitDiffScope)
        .to receive(:for)
        .and_return(instance_double(RuboCop::RSpec::Structure::GitDiffScope, changed?: false))

      expect_no_offenses(<<~RUBY)
        it "when the user is an admin, allows deletion" do
        end
      RUBY
    end
  end

  context "with CheckScope: full" do
    let(:cop_config) { { "ConditionKeywords" => keywords, "CheckScope" => "full" } }

    it "never consults the git diff" do
      expect(RuboCop::RSpec::Structure::GitDiffScope).not_to receive(:for) # rubocop:disable RSpec/MessageSpies

      expect_offense(<<~RUBY)
        it "when the user is an admin, allows deletion" do
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move the condition described here into a surrounding `context` block.
        end
      RUBY
    end
  end
end
