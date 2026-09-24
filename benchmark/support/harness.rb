# frozen_string_literal: true

require "rubocop-rspec-structure"

module Eval # named Eval, not Benchmark, to avoid colliding with Ruby's stdlib Benchmark module
  # Shared runner for manually checking a cop's `JEV_INSTRUCTIONS`/
  # `JEV_CRITERIA` prompt against a small hand-labeled dataset, by calling
  # the real TypeSafe API. This is deliberately not an RSpec suite: an LLM
  # judge's output isn't fully deterministic, so folding this into the
  # regular spec run would make CI flaky and would spend real API budget on
  # every commit for no reason -- prompt wording only changes by hand, so
  # checking it is a manual, opt-in step (see benchmark/README.md).
  module Harness
    THRESHOLD = 0.7 #: Float

    Case = Struct.new(
      :id,        #: String
      :target,    #: String
      :siblings,  #: Array[String]
      :expected,  #: bool?
      keyword_init: true
    )

    module_function

    # @rbs name: String
    # @rbs cases: Array[Case]
    # @rbs instructions: String
    # @rbs criteria: Hash[String, String]
    def run(name, cases, instructions, criteria) #: Hash[Symbol, untyped]
      client = RuboCop::RSpec::Structure::TypeSafe::Client.new(
        api_key: ENV.fetch("TYPESAFE_API_KEY"), model: "jev-latest", timeout: 20
      )

      items = cases.map { question_for(_1, instructions, criteria) }
      results = client.nouls(items)

      report(name, cases, results)
    end

    # @rbs kase: Case
    # @rbs instructions: String
    # @rbs criteria: Hash[String, String]
    def question_for(kase, instructions, criteria) #: RuboCop::RSpec::Structure::TypeSafe::NoulQuestion
      RuboCop::RSpec::Structure::TypeSafe::NoulQuestion.new(
        id: kase.id, state: state_for(kase), instructions:, criteria:
      )
    end

    # @rbs kase: Case
    def state_for(kase) #: String
      lines = ["Target context: #{kase.target}"]
      if kase.siblings.empty?
        lines << "Sibling contexts in the same tree: (none)"
      else
        lines << "Sibling contexts in the same tree:"
        kase.siblings.each_with_index { |s, i| lines << "#{i + 1}. #{s}" }
      end
      lines.join("\n")
    end

    # @rbs name: String
    # @rbs cases: Array[Case]
    # @rbs results: Hash[String, Float]
    def report(name, cases, results) #: Hash[Symbol, untyped]
      scored = cases.reject { _1.expected.nil? }
      passed = scored.count { pass?(_1, results.fetch(_1.id)) }

      puts "\n=== #{name}: #{passed}/#{scored.size} passed ==="
      cases.each { print_case_line(_1, results.fetch(_1.id)) }

      { passed:, total: scored.size, results: }
    end

    # @rbs kase: Case
    # @rbs score: Float
    def print_case_line(kase, score) #: void
      mark = mark_for(kase, score)
      expectation = expectation_label(kase.expected)
      printf("  [%<mark>s] %<id>-28s %<target>-40s score=%<score>.2f expected=%<expectation>s\n",
             mark:, id: kase.id, target: kase.target[0, 40], score: score.to_f, expectation:)
    end

    # @rbs expected: bool?
    def expectation_label(expected) #: String
      return "-" if expected.nil?

      expected ? "HIGH" : "LOW"
    end

    # @rbs kase: Case
    # @rbs score: Float
    def mark_for(kase, score) #: String
      return "?" if kase.expected.nil?

      pass?(kase, score) ? "OK" : "XX"
    end

    # @rbs kase: Case
    # @rbs score: Float
    def pass?(kase, score) #: bool
      kase.expected ? (score >= THRESHOLD) : (score < THRESHOLD)
    end
  end
end
