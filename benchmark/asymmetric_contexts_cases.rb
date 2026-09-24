# frozen_string_literal: true

require_relative "support/harness"

module Eval
  # Hand-labeled dataset for `AsymmetricContexts#JEV_INSTRUCTIONS`/
  # `JEV_CRITERIA`: 11 sibling groups, each member scored independently (22
  # cases total), covering true complements, loose complements, enum-style
  # axes, orthogonal (unrelated) conditions, and setup/fixture detail that
  # isn't a condition at all. Kept deliberately small and readable rather
  # than exhaustive -- this is a regression check for prompt wording
  # changes, not a statistical benchmark.
  #
  # `pair(name, members, expected)` scores every member of `members`
  # against the others; `expected` is either one bool applied to all
  # members, or a per-member array (see `setup_vs_condition`, below, where
  # the two members have different expectations).
  # @rbs name: String
  # @rbs members: Array[String]
  # @rbs expected: bool | Array[bool?]
  def self.pair(name, members, expected) #: Array[Harness::Case]
    expectations = expected.is_a?(Array) ? expected : Array.new(members.size, expected)
    members.each_with_index.map do |target, i|
      siblings = members.reject.with_index { |_, j| j == i }
      Harness::Case.new(id: "#{name}__#{i}", target:, siblings:, expected: expectations[i])
    end
  end

  ASYMMETRIC_CONTEXTS_CASES = [
    # Orthogonal conditions: each member is a real axis untouched by its
    # sibling, so every member should be flagged (HIGH / true).
    pair("orthogonal_auth_cache",
         ["when the request is authenticated", "when the response is cached"], true),
    pair("orthogonal_login_malformed_body",
         ["when the user is not logged in", "when the request body is malformed"], true),
    pair("orthogonal_returning_vs_shipping",
         ["as a returning customer", "with express shipping selected"], true),
    pair("orthogonal_coupon_vs_buyer",
         ["with a valid coupon", "as a first-time buyer"], true),

    # True or loose complements on the same axis: not flagged (LOW / false).
    pair("true_complement_payment",
         ["when the payment succeeds", "when the payment fails"], false),
    pair("loose_complement_validity",
         ["when the input is valid", "when the input contains errors"], false),
    pair("true_complement_login",
         ["when the user is not logged in", "when the user is logged in"], false),

    # Same enum axis, neither member the exact opposite of the other: not
    # flagged (LOW / false) -- this is the case the old two-rule design
    # handled inconsistently.
    pair("enum_filetype",
         ["when the file type is CSV", "when the file type is JSON"], false),
    pair("enum_role_admin_viewer",
         ["when the user is an admin", "when the user is a viewer"], false),
    pair("enum_on_jev_error",
         ["when OnJevError is skip", "when OnJevError is warn"], false),

    # Setup/fixture detail alongside a real, untouched condition: the
    # detail itself isn't flagged, but the real condition is.
    pair("setup_vs_condition",
         ["using the factory-built default user", "when rate limiting is enabled"],
         [false, true])
  ].flatten.freeze #: Array[Harness::Case]
end
