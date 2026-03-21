import policy_lifecycle

pub fn lifecycle_allowed_transitions_test() {
  assert policy_lifecycle.can_transition(
    policy_lifecycle.Draft,
    policy_lifecycle.Simulated,
  )
  assert policy_lifecycle.can_transition(
    policy_lifecycle.Simulated,
    policy_lifecycle.Published,
  )
  assert policy_lifecycle.can_transition(
    policy_lifecycle.Published,
    policy_lifecycle.Archived,
  )
}

pub fn lifecycle_forbidden_transitions_test() {
  assert policy_lifecycle.can_transition(
      policy_lifecycle.Draft,
      policy_lifecycle.Published,
    )
    == False
  assert policy_lifecycle.can_transition(
      policy_lifecycle.Archived,
      policy_lifecycle.Published,
    )
    == False
  assert policy_lifecycle.can_transition(
      policy_lifecycle.Published,
      policy_lifecycle.Draft,
    )
    == False
}

pub fn activate_and_mutability_rules_test() {
  assert policy_lifecycle.can_activate(policy_lifecycle.Published)
  assert policy_lifecycle.can_activate(policy_lifecycle.Draft) == False

  assert policy_lifecycle.is_mutable(policy_lifecycle.Draft)
  assert policy_lifecycle.is_mutable(policy_lifecycle.Simulated)
  assert policy_lifecycle.is_mutable(policy_lifecycle.Published) == False
  assert policy_lifecycle.is_mutable(policy_lifecycle.Archived) == False
}

pub fn activation_requires_published_without_conflict_test() {
  let published =
    policy_lifecycle.ActivationState(
      status: policy_lifecycle.Published,
      is_active: False,
    )

  assert policy_lifecycle.activate(published, False)
    == Ok(policy_lifecycle.ActivationState(
      status: policy_lifecycle.Published,
      is_active: True,
    ))

  assert policy_lifecycle.activate(published, True)
    == Error(policy_lifecycle.ActivePolicyConflict)
}

pub fn activation_rejects_non_published_and_archived_test() {
  let draft =
    policy_lifecycle.ActivationState(
      status: policy_lifecycle.Draft,
      is_active: False,
    )
  let archived =
    policy_lifecycle.ActivationState(
      status: policy_lifecycle.Archived,
      is_active: False,
    )

  assert policy_lifecycle.activate(draft, False)
    == Error(policy_lifecycle.PolicyNotPublished(status: policy_lifecycle.Draft))
  assert policy_lifecycle.activate(archived, False)
    == Error(policy_lifecycle.PolicyImmutableArchived)
}
