# frozen_string_literal: true

# A representative `RSpec/Language` config, standing in for the real one
# `rubocop-rspec` merges in when loaded as a plugin. Cop specs in this
# project inject it via `other_cops` so their cops (which all raise without
# one — see `RuboCop::RSpec::Structure::RequiresRuboCopRspec`) can run.
RSPEC_LANGUAGE_CONFIG = {
  "ExampleGroups" => {
    "Regular" => %w[describe context feature example_group],
    "Focused" => %w[fdescribe fcontext ffeature],
    "Skipped" => %w[xdescribe xcontext xfeature]
  },
  "SharedGroups" => {
    "Examples" => %w[shared_examples shared_examples_for],
    "Context" => ["shared_context"]
  },
  "Examples" => {
    "Regular" => %w[it specify example],
    "Focused" => %w[fit fspecify fexample],
    "Skipped" => %w[xit xspecify xexample skip],
    "Pending" => ["pending"]
  }
}.freeze
