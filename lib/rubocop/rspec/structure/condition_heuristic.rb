# frozen_string_literal: true

module RuboCop
  module RSpec
    module Structure
      # Regex-based first pass over an example description: does it contain
      # a word or phrase (`の場合`, `when`, ...) that usually signals a
      # condition which belongs in a surrounding `context` instead of the
      # example itself? Always run before falling back to TypeSafe, since
      # it is free and catches the common, unambiguous cases.
      class ConditionHeuristic
        # A kanji directly before a keyword means it's the tail of some
        # other, unrelated compound word (実際, 国際, 手際, ...) rather than
        # a condition clause boundary — a real one is always preceded by a
        # particle or a verb/adjective ending, i.e. kana, not another
        # kanji. Range covers CJK Unified Ideographs + Extension A.
        UNICODE_KANJI_RANGE = "㐀-鿿"

        # @rbs keywords: Array[String]
        def initialize(keywords:) #: void
          @pattern = build_pattern(keywords)
        end

        # @rbs description: String
        def condition?(description) #: bool
          !!pattern.match?(description)
        end

        private

        attr_reader :pattern #: Regexp

        # @rbs keywords: Array[String]
        def build_pattern(keywords) #: Regexp
          Regexp.union(keywords.map { pattern_for(_1) })
        end

        # ASCII keywords (e.g. "when") need a word boundary so they don't
        # match inside unrelated words; Japanese keywords instead reject a
        # kanji immediately before them, for the same reason (see
        # `UNICODE_KANJI_RANGE`).
        # @rbs keyword: String
        def pattern_for(keyword) #: Regexp
          if keyword.match?(/\A[a-zA-Z ]+\z/)
            /\b#{Regexp.escape(keyword)}\b/i
          else
            /(?<![#{UNICODE_KANJI_RANGE}])#{Regexp.escape(keyword)}/
          end
        end
      end
    end
  end
end
