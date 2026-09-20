# frozen_string_literal: true

require "open3"
require "pathname"

module RuboCop
  module RSpec
    module Structure
      # Computes which lines changed relative to a base git ref, so
      # `CheckScope: diff` can skip examples nobody touched instead of
      # re-judging the whole suite on every run. `git diff` runs once per
      # process (memoized by resolved base) and is shared by every cop
      # instance, since RuboCop instantiates a cop per file.
      class GitDiffScope
        FILE_HEADER = %r{\A\+\+\+ b/(.+)\z}
        HUNK_HEADER = /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/

        # @rbs @git_root: String

        class << self
          # @rbs self.@instances: Hash[String, GitDiffScope]

          # @rbs diff_base: String
          def for(diff_base:) #: GitDiffScope
            @instances ||= {} #: Hash[String, GitDiffScope]
            @instances[diff_base] ||= new(diff_base:)
          end

          # Test-only: forces the next `for` to recompute against the
          # current git state instead of returning a memoized instance.
          def reset! #: void
            @instances = {}
          end
        end

        # @rbs diff_base: String
        def initialize(diff_base:) #: void
          @changed_lines = compute_diff(resolve_base(diff_base))
        end

        # @rbs path: String
        # @rbs line: Integer
        def changed?(path, line) #: bool
          lines = changed_lines.fetch(relative_path(path), [])
          return true if lines == :all

          lines.is_a?(Array) && lines.include?(line)
        end

        # Whether the file appeared anywhere in the diff at all — added,
        # edited, or had content deleted from it — regardless of which
        # specific line a caller cares about. Coarser than `changed?`, but
        # immune to the line/hunk-boundary bookkeeping `changed?` needs: a
        # pure deletion (removing a sibling `context` outright, say) has no
        # new-side line of its own to record, so a line-precise check can
        # miss it entirely. This only needs to know the file was touched.
        # @rbs path: String
        def changed_file?(path) #: bool
          changed_lines.key?(relative_path(path))
        end

        private

        attr_reader :changed_lines #: Hash[String, (Array[Integer] | Symbol)]

        # `"auto"` resolves the base ref by environment; anything else
        # (an explicit branch/SHA from config or an env override) is used
        # as-is.
        # @rbs diff_base: String
        def resolve_base(diff_base) #: String
          return diff_base unless diff_base == "auto"
          return "HEAD" unless ENV["CI"]

          ci_merge_base || merge_base("origin/HEAD") || "HEAD"
        end

        # GitHub Actions and GitLab CI both expose the pull/merge request's
        # target branch name; resolve it to the actual divergence point so
        # commits already on the base branch are not flagged as "changed".
        def ci_merge_base #: String?
          branch = ENV["GITHUB_BASE_REF"] || ENV.fetch("CI_MERGE_REQUEST_TARGET_BRANCH_NAME", nil)
          return nil if branch.nil? || branch.empty?

          merge_base("origin/#{branch}")
        end

        # @rbs ref: String
        def merge_base(ref) #: String?
          sha, _stderr, status = Open3.capture3("git", "merge-base", "HEAD", ref)
          status.success? ? sha.strip : nil
        end

        # `git diff` never lists untracked files at all (that's not a diff
        # against anything), so a newly-written, not-yet-`git add`ed spec
        # file would otherwise be silently out of scope no matter what it
        # contains. Treat every line of an untracked file as changed.
        # @rbs base: String
        def compute_diff(base) #: Hash[String, (Array[Integer] | Symbol)]
          diff, status = Open3.capture2("git", "diff", "--unified=0", "--no-color", base)
          # Open3 tags the captured string with Encoding.default_external, which is not
          # necessarily UTF-8 (e.g. a plain "C"/"POSIX" locale reports US-ASCII), so a diff
          # containing multibyte content would otherwise raise ArgumentError the moment a
          # regexp touches it below. `scrub` additionally replaces any byte sequence that
          # is not valid UTF-8 (e.g. a diffed file whose real encoding isn't UTF-8 at all);
          # FILE_HEADER/HUNK_HEADER only ever match pure-ASCII header lines, so substituting
          # the multibyte payload itself never affects parsing.
          diff = diff.force_encoding(Encoding::UTF_8).scrub
          changed = status.success? ? parse_diff(diff) : {} #: Hash[String, (Array[Integer] | Symbol)]

          untracked_files.each { changed[_1] = :all }
          changed
        end

        def untracked_files #: Array[String]
          # --full-name: paths relative to the repo root regardless of the
          # current directory, matching the diff parser's paths above.
          output, status = Open3.capture2("git", "ls-files", "--others", "--exclude-standard", "--full-name")
          status.success? ? output.split("\n") : []
        end

        # Parses unified diff hunk headers (`@@ -a,b +c,d @@`) to collect,
        # per file, the line numbers that exist on the new side of the
        # diff. A file with only pure-deletion hunks (new-side count of 0)
        # still gets an entry (an empty array) so `changed_file?` can see
        # it was touched, even though it has no specific new-side line for
        # `changed?` to report.
        # @rbs diff: String
        def parse_diff(diff) #: Hash[String, Array[Integer]]
          changed = {} #: Hash[String, Array[Integer]]
          current_file = nil

          diff.each_line(chomp: true) do |line|
            file_header = line.match(FILE_HEADER)
            if file_header
              current_file = file_from_header(file_header)
            else
              file = current_file
              hunk_header = line.match(HUNK_HEADER)
              next unless file && hunk_header

              # Steep does not narrow `file`/`hunk_header` from the
              # compound guard above, so both are asserted explicitly;
              # the guard itself is what makes this safe at runtime.
              asserted_file = file #: String
              asserted_hunk_header = hunk_header #: MatchData
              record_hunk(changed, asserted_file, asserted_hunk_header)
            end
          end

          changed
        end

        # @rbs changed: Hash[String, Array[Integer]]
        # @rbs file: String
        # @rbs hunk_header: MatchData
        def record_hunk(changed, file, hunk_header) #: void
          (changed[file] ||= []).concat(new_side_lines(hunk_header))
        end

        # @rbs match: MatchData
        def file_from_header(match) #: String?
          # This is git's unified-diff marker for a deleted file, always the
          # literal string "/dev/null" regardless of host OS — not the
          # platform null device, so File::NULL would be wrong here.
          match[1] == "/dev/null" ? nil : match[1] # rubocop:disable Style/FileNull
        end

        # @rbs match: MatchData
        def new_side_lines(match) #: Array[Integer]
          start = match[1].to_i
          count = match[2] ? match[2].to_i : 1
          count.zero? ? [] : (start...(start + count)).to_a
        end

        def git_root #: String
          @git_root ||= Open3.capture2("git", "rev-parse", "--show-toplevel").first.strip
        end

        # @rbs path: String
        def relative_path(path) #: String
          Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(git_root)).to_s
        end
      end
    end
  end
end
