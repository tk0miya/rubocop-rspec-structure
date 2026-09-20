# rubocop-rspec-structure

A RuboCop plugin that checks the structure of RSpec examples.

## `RSpecStructure/AsymmetricContexts`

Flags a `context` that describes one branch of an externally observable
behavioral condition (a boolean state, an enum value, a success/failure
outcome, ...) without a sibling `context` for its natural counterpart,
among the `context` blocks nested directly under the same parent group:

```ruby
# bad - "when the user is logged in" is missing
describe "#dashboard" do
  context "when the user is not logged in" do
    it "redirects to the login page" do
    end
  end
end

# good
describe "#dashboard" do
  context "when the user is not logged in" do
    it "redirects to the login page" do
    end
  end

  context "when the user is logged in" do
    it "renders the dashboard" do
    end
  end
end
```

A `context` is a statement that execution branches on some condition, so
a **lone context with no siblings at all** is always flagged, mechanically
and at no cost (no Jev call, no `TYPESAFE_API_KEY` needed): either its
counterpart is missing, or there was never a real branch to begin with and
it shouldn't have been wrapped in `context`.

```ruby
# bad - a lone context has no counterpart to compare against
describe "#dashboard" do
  context "when the user is not logged in" do
    it "redirects to the login page" do
    end
  end
end
```

With **two or more sibling contexts**, each one is judged individually:
does some sibling — exactly or loosely — represent its natural
complementary branch? That judgment is inherently semantic (no keyword
list can decide it), so it is made only by [Jev][jev]. Unlike
`ConditionInExample`, there is no deterministic fallback for this case:
this cop is a complete no-op for groups of two or more siblings unless
`TYPESAFE_API_KEY` is set. See "Setting up Jev (optional)" and "Checking
only what changed" under `ConditionInExample` below — this cop shares the
exact same cache, `OnJevError`, `CheckScope`, and `DiffBase` machinery,
except that `CheckScope: diff` is checked per **file** here rather than
per line: since a sibling's asymmetry depends on the whole set of
siblings around it, not just its own line, and a Jev call is cheap and
cache-backed, every context in a touched file is judged, not just the
ones whose own lines moved.
Like the rest of Jev's judgments, it returns a bare calibrated probability
with no explanation of why — there is no way to ask it for its reasoning.

Only **direct siblings** are compared. A counterpart implemented
elsewhere — a different `describe`, a different file — does not satisfy
this check. This is intentional, not a shortcut: the point is that a
behavioral branch should be represented in the same context tree, not
merely covered somewhere in the suite.

### Non-goals

This cop does not check for **exhaustive coverage** of a multi-valued
condition — e.g. a 3-way enum (`skip`/`warn`/`raise`) with only two values
tested is a coverage/completeness question, not asymmetry, and is left
untouched.

This cop also does not decide **where in the tree** a missing branch
belongs, or whether existing siblings should be nested more deeply. Each
sibling is judged independently, so several offenses can fire together on
the same flat sibling list — read that as a hint the tree may need
restructuring, not as separate, unrelated findings.

## `RSpecStructure/ConditionInExample`

Flags `it`/`example` descriptions that describe an execution condition
(`〜の場合`, `〜のとき`, `when ...`, `if ...`) which belongs in a surrounding
`context` block instead:

```ruby
# bad
it "when the user is an admin, allows deletion" do
  # ...
end

# good
context "when the user is an admin" do
  it "allows deletion" do
    # ...
  end
end
```

## How it decides

1. A cheap, always-on keyword check runs first (`ConditionKeywords`,
   Japanese and English by default). If it matches, that's the offense —
   no network call is made.
2. If the keyword check finds nothing **and** a `TYPESAFE_API_KEY`
   environment variable is set, the description is also judged
   semantically by [Jev][jev], the first
   [System One model][system-one] from [TypeSafe AI][typesafe]. Jev
   evaluates a single yes/no question ("does this description embed a
   condition that belongs in `context`?") and returns a calibrated
   probability instead of generated text, which this cop compares against
   `JevThreshold` (default `0.6`).
3. Without an API key, only the keyword check runs. **The presence of
   `TYPESAFE_API_KEY` is the only switch** between the two — there is no
   separate "mode" setting.

[jev]: https://docs.typesafe.ai
[system-one]: https://docs.typesafe.ai/concepts/system-one
[typesafe]: https://typesafe.ai

### Setting up Jev (optional)

```bash
export TYPESAFE_API_KEY="..."
```

Never put the key itself in `.rubocop.yml`, since that file is normally
committed. Calling Jev costs money and requires network access, so:

- Results are cached on disk, keyed by the description, the prompt, and
  the model, so the same input is never billed twice. The cache defaults
  to a per-user location following the XDG Base Directory Specification
  (`$XDG_CACHE_HOME/rubocop-rspec-structure/jev_cache.json`, falling back
  to `~/.cache/...`), shared across every project on this machine, since
  a Jev judgment only depends on the input, not the project. Set
  `CachePath` to pin it to a repo-relative path instead — for example to
  persist it across CI runs with `actions/cache`, since a CI runner's
  home directory doesn't survive between runs on its own.
- A network error, timeout, or malformed response is swallowed by default
  (`OnJevError: skip`). Set `warn` to also print a message, or `raise` to
  fail the rubocop run.
- Jev has documented jaggedness — it reads instructions literally and
  loses accuracy when given irrelevant context — so this cop sends it
  only the bare description text by design. Treat a Jev-triggered offense
  as a suggestion to review, not a verdict.

### Checking only what changed

Calling an external API on every example in a large suite, on every run,
is wasteful. `CheckScope` defaults to `diff`: only examples touched by the
current git diff are judged at all (heuristic and Jev alike). Set
`CheckScope: full` to check everything regardless of what changed.

`DiffBase` defaults to `auto`:

- Locally (no `CI` environment variable), it diffs against `HEAD`, i.e.
  your uncommitted changes.
- In CI (`CI` is set), it resolves the actual merge base against the
  pull/merge request's target branch (`GITHUB_BASE_REF` on GitHub Actions,
  `CI_MERGE_REQUEST_TARGET_BRANCH_NAME` on GitLab CI), falling back to
  `origin/HEAD`. A shallow checkout can leave `origin/HEAD` unresolvable —
  fetch enough history (e.g. `actions/checkout` with `fetch-depth: 0`, or
  explicitly fetch the base branch) for this to work.
- If none of the above resolves (e.g. no `origin` remote at all), it falls
  back to `HEAD` as a last resort. In CI that usually means an empty diff —
  nothing gets checked, rather than the run failing outright. If a PR seems
  to go unchecked, this fallback is the first thing to rule out; set
  `DiffBase` explicitly (or `CheckScope: full`) if it does.
- New files git doesn't know about yet (not `git add`ed) are always
  in scope in full, regardless of `DiffBase` — `git diff` never lists
  untracked files, so this is handled as a special case.

Both settings can be overridden per run without touching `.rubocop.yml`:

```bash
RUBOCOP_RSPEC_STRUCTURE_CHECK_SCOPE=full bundle exec rubocop
RUBOCOP_RSPEC_STRUCTURE_DIFF_BASE=origin/main bundle exec rubocop
```

## `RSpecStructure/MultipleExamplesInGroup`

Flags a group block (`describe`, `context`, `feature`, `shared_examples`,
`shared_context`, ...) that directly nests more than one example. Under
BDD's Given-When-Then structure, a group's own body is a single
precondition — the subject under `describe`, the "Given"/"When" under
`context`, or whatever precondition its includer supplies under
`shared_examples`/`shared_context` — so it should set up exactly one
"Then". Two examples sitting side by side in the same group with nothing
distinguishing them push the reader to guess whether they share one
condition (so they belong in a single example) or cover different
conditions (so they belong in separate `context` blocks):

```ruby
# bad
describe User do
  it "allows deletion" do
  end

  it "allows editing" do
  end
end

# good - merged into one example
context "when the user is an admin" do
  it "allows deletion and editing" do
  end
end

# good - split into separate contexts
describe User do
  context "when the user is an admin" do
    it "allows deletion" do
    end
  end

  context "when the user is a viewer" do
    it "allows editing" do
    end
  end
end

# good - nested groups are fine; each one still has a single example
context "when the user is an admin" do
  context "and the record is archived" do
    it "still allows deletion" do
    end
  end

  context "and the record is active" do
    it "allows deletion" do
    end
  end
end

# bad - a shared group is checked the same as any other group
shared_examples "a paginated collection" do
  it "returns the first page" do
  end

  it "returns the total count" do
  end
end
```

Only examples nested directly in a group's own body count; examples
inside a nested group are that group's concern, not this one's. Unlike
`RSpec/NestedGroups` or `RSpec/MultipleExpectations`, there is no `Max`
to raise: more than one example is always an offense, by design — the
point is to force a merge or a split, not to give a project a knob to
allow more.

Unlike `RSpecStructure/ConditionInExample`, this cop doesn't honor
`CheckScope`/`DiffBase`: the check is a cheap, purely mechanical AST
inspection with no external API to call, so there's no cost to weigh
against always checking every group in full.

## Installation

```bash
bundle add rubocop-rspec-structure
```

## Configuration

```yaml
# .rubocop.yml
plugins:
  - rubocop-rspec
  - rubocop-rspec-structure

RSpecStructure/AsymmetricContexts:
  CheckScope: diff # diff | full
  DiffBase: auto
  JevThreshold: 0.7
  JevTimeoutSeconds: 5
  OnJevError: skip # skip | warn | raise
  CacheEnabled: true

RSpecStructure/ConditionInExample:
  ConditionKeywords:
    - の場合
    - のとき
    - 場合
    - 際
    - when
    - if
    - in case
    - given that
  CheckScope: diff # diff | full
  DiffBase: auto
  JevThreshold: 0.6
  JevTimeoutSeconds: 5
  OnJevError: skip # skip | warn | raise
  CacheEnabled: true
  # CachePath: tmp/rubocop-rspec-structure/jev_cache.json # see "Setting up Jev" above

RSpecStructure/MultipleExamplesInGroup:
  Enabled: true # this cop has no other options
```

`rubocop-rspec` must also be listed under `plugins:` (this gem depends on
it for the `it`/`specify`/`example` alias detection); if it is missing,
every cop in this gem raises a clear error rather than silently running
against a guessed set of aliases.

## Development

After checking out the repo, run `bin/setup` to install dependencies.
`bundle exec rake ci` runs everything CI runs (rubocop, rspec, steep,
rbs:validate). Type signatures under `sig/` are generated automatically
from `# @rbs` inline annotations in `lib/`; do not edit `sig/` by hand.

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/tk0miya/rubocop-rspec-structure.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
