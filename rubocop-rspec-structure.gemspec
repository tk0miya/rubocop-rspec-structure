# frozen_string_literal: true

require_relative "lib/rubocop/rspec/structure/version"

Gem::Specification.new do |spec|
  spec.name = "rubocop-rspec-structure"
  spec.version = RuboCop::RSpec::Structure::VERSION
  spec.authors = ["Takeshi KOMIYA"]
  spec.email = ["i.tkomiya@gmail.com"]

  spec.summary = "RuboCop extension for checking the structure of RSpec examples."
  spec.description = "A RuboCop plugin that flags RSpec example descriptions containing " \
                     "conditions that belong in a surrounding `context` block instead."
  spec.homepage = "https://github.com/tk0miya/rubocop-rspec-structure"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["default_lint_roller_plugin"] = "RuboCop::RSpec::Structure::Plugin"

  spec.add_dependency "lint_roller", "~> 1.1"
  spec.add_dependency "rubocop", ">= 1.86", "< 2.0"
  spec.add_dependency "rubocop-rspec", ">= 3.0", "< 4.0"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/
                          .rubocop.yml .claude/ .vscode/ Rakefile Steepfile
                          rbs_collection])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { File.basename(_1) }
  spec.require_paths = ["lib"]
end
