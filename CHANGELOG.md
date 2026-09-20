## [Unreleased]

- Add `RSpecStructure/AsymmetricContexts`, which flags a `context`
  describing one branch of an externally observable condition that has
  no sibling `context` for its natural counterpart. A lone context with
  no siblings is always flagged mechanically; two or more siblings are
  judged semantically via Jev, with no deterministic fallback.
- Add `RSpecStructure/ConditionInExample`, which flags example
  descriptions that embed an execution condition belonging in a
  surrounding `context` block. A keyword check runs by default; setting
  `TYPESAFE_API_KEY` additionally enables semantic judgment via Jev
  (TypeSafe AI's System One model).
- Add `RSpecStructure/MultipleExamplesInGroup`, which flags a
  group block (`describe`, `context`, `feature`, `shared_examples`,
  `shared_context`, ...) that directly nests more than one example,
  pushing developers to either merge them into a single example or add
  a nested context per condition.
