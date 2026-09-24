# Jev prompt eval

Manual, opt-in scripts for checking a cop's `JEV_INSTRUCTIONS`/`JEV_CRITERIA`
prompt against a small hand-labeled dataset, using the real TypeSafe API.

This is intentionally **not** part of `rspec` or `rake ci`: an LLM judge's
answers aren't fully deterministic, so running this on every commit would
make CI flaky and spend real API budget for no reason. Prompt wording only
changes by hand, so checking it is a manual step you run yourself, after
editing a cop's `JEV_INSTRUCTIONS`/`JEV_CRITERIA`.

## Running

```console
$ export TYPESAFE_API_KEY="..."
$ bundle exec rake benchmark:asymmetric_contexts
```

Each script prints a pass/fail count and a per-case table (`OK`/`XX`/`?`,
`?` meaning the case has no strict expectation and is shown for reference
only). A case can flip between runs since the judge isn't fully
deterministic; a handful of `XX` near the 0.7 threshold isn't necessarily a
regression, but a consistent drop across repeated runs is.

## Adding a dataset for another cop

1. Add `benchmark/<cop>_cases.rb`, building `Eval::Harness::Case` entries
   (see `asymmetric_contexts_cases.rb` for the `pair` helper this cop uses).
2. Add `benchmark/<cop>.rb`, requiring the cases file and calling
   `Eval::Harness.run` with the cop class's own `JEV_INSTRUCTIONS`/
   `JEV_CRITERIA` constants -- read directly from the cop, never copied in,
   so the eval can't drift from what ships.
3. Add a Rakefile task under the `benchmark` namespace.
