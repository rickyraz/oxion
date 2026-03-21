pub type LifecycleStatus {
  Draft
  Simulated
  Published
  Archived
}

pub type TransitionError {
  InvalidTransition(from: LifecycleStatus, to: LifecycleStatus)
}

pub type ActivationError {
  PolicyNotPublished(status: LifecycleStatus)
  ActivePolicyConflict
  PolicyImmutableArchived
}

// Why: activation invariants in the spec depend on both lifecycle status and
// active-state exclusivity, so the state machine needs to model both.
pub type ActivationState {
  ActivationState(status: LifecycleStatus, is_active: Bool)
}

/// Returns `True` if a lifecycle transition is allowed by policy rules.
pub fn can_transition(from: LifecycleStatus, to: LifecycleStatus) -> Bool {
  case from {
    Draft ->
      case to {
        Draft | Simulated -> True
        _ -> False
      }
    Simulated ->
      case to {
        Draft | Simulated | Published -> True
        _ -> False
      }
    Published ->
      case to {
        Published | Archived -> True
        _ -> False
      }
    Archived -> False
  }
}

/// Performs a lifecycle transition and returns an error when the transition is forbidden.
pub fn transition(
  from: LifecycleStatus,
  to: LifecycleStatus,
) -> Result(LifecycleStatus, TransitionError) {
  case can_transition(from, to) {
    True -> Ok(to)
    False -> Error(InvalidTransition(from:, to:))
  }
}

/// Returns `True` only for statuses that satisfy the publish precondition.
pub fn can_activate(status: LifecycleStatus) -> Bool {
  case status {
    Published -> True
    _ -> False
  }
}

pub fn activate(
  state: ActivationState,
  other_active_published_exists: Bool,
) -> Result(ActivationState, ActivationError) {
  let ActivationState(status:, is_active: _) = state

  case status {
    Archived -> Error(PolicyImmutableArchived)
    Published ->
      case other_active_published_exists {
        True -> Error(ActivePolicyConflict)
        False -> Ok(ActivationState(status: Published, is_active: True))
      }
    _ -> Error(PolicyNotPublished(status: status))
  }
}

pub fn deactivate(state: ActivationState) -> ActivationState {
  let ActivationState(status:, is_active: _) = state
  ActivationState(status: status, is_active: False)
}

/// Indicates whether a policy status is editable.
pub fn is_mutable(status: LifecycleStatus) -> Bool {
  case status {
    Draft | Simulated -> True
    Published | Archived -> False
  }
}
