# frozen_string_literal: true

require "tmpdir"

RSpec.describe RuboCop::RSpec::Structure::GitDiffScope do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(File.realpath(dir)) { example.run }
    end
  end

  before do
    described_class.reset!
    run_git("init -q -b main")
    run_git("config user.email test@example.com")
    run_git("config user.name Test")
    File.write("a.rb", "line1\nline2\n")
    run_git("add a.rb")
    run_git("commit -q -m initial")
  end

  def run_git(args)
    system("git #{args}", out: File::NULL, err: File::NULL, exception: true)
  end

  context "when nothing changed" do
    it "reports no changed lines" do
      scope = described_class.for(diff_base: "HEAD")

      expect(scope.changed?(File.expand_path("a.rb"), 1)).to be(false)
    end
  end

  context "when there is an uncommitted edit" do
    it "reports the new line numbers touched" do
      File.write("a.rb", "line1\nCHANGED\n")

      scope = described_class.for(diff_base: "HEAD")

      expect(scope.changed?(File.expand_path("a.rb"), 2)).to be(true)
      expect(scope.changed?(File.expand_path("a.rb"), 1)).to be(false)
    end
  end

  context "when the file is new and not yet added" do
    it "treats every line as changed" do
      File.write("new_spec.rb", "line1\nline2\nline3\n")

      scope = described_class.for(diff_base: "HEAD")

      expect(scope.changed?(File.expand_path("new_spec.rb"), 1)).to be(true)
      expect(scope.changed?(File.expand_path("new_spec.rb"), 3)).to be(true)
    end
  end

  context "when the diff contains multibyte characters" do
    it "handles it" do
      File.write("a.rb", "line1\n日本語\n")

      scope = described_class.for(diff_base: "HEAD")

      expect(scope.changed?(File.expand_path("a.rb"), 2)).to be(true)
    end
  end

  context "when the diff contains a byte sequence that is not valid UTF-8" do
    it "handles it" do
      File.binwrite("a.rb", "line1\n\x82\xA0\n".b)

      scope = described_class.for(diff_base: "HEAD")

      expect(scope.changed?(File.expand_path("a.rb"), 2)).to be(true)
    end
  end

  context "when called twice with the same diff_base" do
    it "returns the same instance" do
      first = described_class.for(diff_base: "HEAD")

      expect(described_class.for(diff_base: "HEAD")).to be(first)
    end
  end

  context "when resolving \"auto\"" do
    around do |example|
      original_ci = ENV.fetch("CI", nil)
      example.run
    ensure
      original_ci ? (ENV["CI"] = original_ci) : ENV.delete("CI")
    end

    context "when CI is not set" do
      it "behaves like HEAD" do
        ENV.delete("CI")
        File.write("a.rb", "line1\nCHANGED\n")

        scope = described_class.for(diff_base: "auto")

        expect(scope.changed?(File.expand_path("a.rb"), 2)).to be(true)
      end
    end

    context "when CI is set but no base branch or remote can be resolved" do
      it "falls back to HEAD" do
        ENV["CI"] = "true"
        File.write("a.rb", "line1\nCHANGED\n")

        scope = described_class.for(diff_base: "auto")

        expect(scope.changed?(File.expand_path("a.rb"), 2)).to be(true)
      end
    end
  end
end
