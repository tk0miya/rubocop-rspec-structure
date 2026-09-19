## [Unreleased]

- Add `RSpecStructure/ConditionInExample`, which flags example
  descriptions that embed an execution condition belonging in a
  surrounding `context` block. A keyword check runs by default; setting
  `TYPESAFE_API_KEY` additionally enables semantic judgment via Jev
  (TypeSafe AI's System One model).
- Add `RSpecStructure/MultipleExamplesInExampleGroup`, which flags an
  example group (`describe`, `context`, `feature`, ...) that directly
  nests more than one example, pushing developers to either merge them
  into a single example or split the group into separate contexts per
  condition.
