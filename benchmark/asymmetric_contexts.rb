#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "asymmetric_contexts_cases"

cop_class = RuboCop::Cop::RSpecStructure::AsymmetricContexts

# Always reads JEV_INSTRUCTIONS/JEV_CRITERIA off the real cop class, never a
# copy pasted in here, so this eval can't silently drift from what ships.
Eval::Harness.run("AsymmetricContexts", Eval::ASYMMETRIC_CONTEXTS_CASES, cop_class::JEV_INSTRUCTIONS,
                  cop_class::JEV_CRITERIA)
