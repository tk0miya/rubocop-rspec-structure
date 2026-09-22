# frozen_string_literal: true

require "digest"
require "json"

module RuboCop
  module RSpec
    module Structure
      module TypeSafe
        # A single yes/no Noul question, batched together with others into
        # one `nouls(...)` call. `id` only needs to be unique within its own
        # batch — the caller uses it to correlate the returned probability
        # back to whatever it cares about, not as a durable identity.
        NoulQuestion = Struct.new(
          :id,            #: String
          :state,         #: String
          :instructions,  #: String
          :criteria       #: Hash[String, String]?
        )

        # Reopened (rather than defined in `Struct.new`'s own block) since
        # rbs-inline's member-typing support for `Struct.new` doesn't parse
        # methods declared inside that block.
        class NoulQuestion
          # @rbs @cache_key: String?

          # Identifies this question's own content, independent of which
          # model answers it — `Cache` folds the model in separately, since
          # that's its concern, not this question's. Memoized on the
          # instance (a plain Struct, not a frozen Data, precisely so this
          # can be cached rather than recomputed on every lookup).
          def cache_key #: String
            @cache_key ||= Digest::SHA256.hexdigest(JSON.generate({ state:, instructions:, criteria: }))
          end
        end
      end
    end
  end
end
