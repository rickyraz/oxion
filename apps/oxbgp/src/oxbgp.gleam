import gleam/list
import gleam/order
import gleam/string

pub type ControlPlaneRole {
  EdgeTransit
  IxpRouteServer
}

pub type ControlPlaneEngine {
  Frr
  Bird
}

pub type ControlPlanePlan {
  ControlPlanePlan(
    edge_transit_engine: ControlPlaneEngine,
    ixp_route_server_engine: ControlPlaneEngine,
  )
}

pub type PathHealth {
  Healthy
  Degraded
  Critical
}

pub type PathCandidate {
  PathCandidate(
    id: String,
    next_hop: String,
    estimated_cost_score: Int,
    latency_ms: Int,
    packet_loss_bps: Int,
    health: PathHealth,
  )
}

pub type ControlPolicy {
  ControlPolicy(
    max_latency_ms: Int,
    max_packet_loss_bps: Int,
    min_latency_improvement_ms: Int,
    min_cost_improvement_score: Int,
    hold_down_ticks: Int,
    cgnat_saturation_limit_bps: Int,
  )
}

pub type ControlInput {
  ControlInput(
    current_path_id: String,
    candidates: List(PathCandidate),
    ticks_since_last_switch: Int,
    cgnat_saturation_bps: Int,
  )
}

pub type RouteDecision {
  KeepCurrent(reason: String)
  SwitchTo(path_id: String, reason: String)
}

/// Opinionated engine binding by role:
/// - edge/transit routers must use FRR
/// - IXP route-server must use BIRD
pub fn engine_for_role(role: ControlPlaneRole) -> ControlPlaneEngine {
  case role {
    EdgeTransit -> Frr
    IxpRouteServer -> Bird
  }
}

/// Returns the mandatory default control-plane layout used by oxBGP.
pub fn opinionated_control_plane_plan() -> ControlPlanePlan {
  ControlPlanePlan(
    edge_transit_engine: engine_for_role(EdgeTransit),
    ixp_route_server_engine: engine_for_role(IxpRouteServer),
  )
}

/// Computes deterministic optimizer influence while preserving BGP as baseline.
pub fn evaluate(input: ControlInput, policy: ControlPolicy) -> RouteDecision {
  let ControlInput(
    current_path_id: current_path_id,
    candidates: candidates,
    ticks_since_last_switch: ticks_since_last_switch,
    cgnat_saturation_bps: cgnat_saturation_bps,
  ) = input
  let ControlPolicy(
    max_latency_ms: _max_latency_ms,
    max_packet_loss_bps: _max_packet_loss_bps,
    min_latency_improvement_ms: _min_latency_improvement_ms,
    min_cost_improvement_score: _min_cost_improvement_score,
    hold_down_ticks: hold_down_ticks,
    cgnat_saturation_limit_bps: cgnat_saturation_limit_bps,
  ) = policy

  case cgnat_saturation_bps >= cgnat_saturation_limit_bps {
    True -> KeepCurrent(reason: "cgnat_saturation_high")
    False ->
      case ticks_since_last_switch < hold_down_ticks {
        True -> KeepCurrent(reason: "hold_down_active")
        False -> evaluate_paths(current_path_id, candidates, policy)
      }
  }
}

fn evaluate_paths(
  current_path_id: String,
  candidates: List(PathCandidate),
  policy: ControlPolicy,
) -> RouteDecision {
  let eligible_candidates =
    list.filter(candidates, fn(candidate) { is_eligible(candidate, policy) })

  case best_candidate(eligible_candidates) {
    Error(_) -> KeepCurrent(reason: "no_eligible_path")
    Ok(best) ->
      case current_candidate(candidates, current_path_id) {
        Error(_) -> switch_for_missing_current(best)
        Ok(current) -> decide_from_current(best, current, policy)
      }
  }
}

fn switch_for_missing_current(best: PathCandidate) -> RouteDecision {
  let PathCandidate(
    id: best_id,
    next_hop: _next_hop,
    estimated_cost_score: _estimated_cost_score,
    latency_ms: _latency_ms,
    packet_loss_bps: _packet_loss_bps,
    health: _health,
  ) = best

  SwitchTo(path_id: best_id, reason: "current_path_missing")
}

fn decide_from_current(
  best: PathCandidate,
  current: PathCandidate,
  policy: ControlPolicy,
) -> RouteDecision {
  let PathCandidate(
    id: best_id,
    next_hop: _best_next_hop,
    estimated_cost_score: best_cost,
    latency_ms: best_latency,
    packet_loss_bps: _best_packet_loss_bps,
    health: _best_health,
  ) = best
  let PathCandidate(
    id: current_id,
    next_hop: _current_next_hop,
    estimated_cost_score: current_cost,
    latency_ms: current_latency,
    packet_loss_bps: _current_packet_loss_bps,
    health: _current_health,
  ) = current
  let ControlPolicy(
    max_latency_ms: _max_latency_ms,
    max_packet_loss_bps: _max_packet_loss_bps,
    min_latency_improvement_ms: min_latency_improvement_ms,
    min_cost_improvement_score: min_cost_improvement_score,
    hold_down_ticks: _hold_down_ticks,
    cgnat_saturation_limit_bps: _cgnat_saturation_limit_bps,
  ) = policy

  case best_id == current_id {
    True -> KeepCurrent(reason: "current_path_best")
    False ->
      case is_eligible(current, policy) {
        False -> SwitchTo(path_id: best_id, reason: "current_path_unhealthy")
        True -> {
          let latency_gain = current_latency - best_latency
          let cost_gain = current_cost - best_cost

          case
            latency_gain >= min_latency_improvement_ms
            || cost_gain >= min_cost_improvement_score
          {
            True ->
              SwitchTo(path_id: best_id, reason: "optimizer_threshold_met")
            False -> KeepCurrent(reason: "improvement_below_threshold")
          }
        }
      }
  }
}

fn best_candidate(candidates: List(PathCandidate)) -> Result(PathCandidate, Nil) {
  case candidates {
    [] -> Error(Nil)
    [head, ..tail] -> Ok(best_candidate_loop(head, tail))
  }
}

fn best_candidate_loop(
  current_best: PathCandidate,
  remaining: List(PathCandidate),
) -> PathCandidate {
  case remaining {
    [] -> current_best
    [candidate, ..rest] ->
      case candidate_before(candidate, current_best) {
        True -> best_candidate_loop(candidate, rest)
        False -> best_candidate_loop(current_best, rest)
      }
  }
}

fn candidate_before(a: PathCandidate, b: PathCandidate) -> Bool {
  let PathCandidate(
    id: a_id,
    next_hop: _a_next_hop,
    estimated_cost_score: a_cost,
    latency_ms: a_latency,
    packet_loss_bps: _a_packet_loss_bps,
    health: _a_health,
  ) = a
  let PathCandidate(
    id: b_id,
    next_hop: _b_next_hop,
    estimated_cost_score: b_cost,
    latency_ms: b_latency,
    packet_loss_bps: _b_packet_loss_bps,
    health: _b_health,
  ) = b

  case a_cost < b_cost {
    True -> True
    False ->
      case a_cost > b_cost {
        True -> False
        False ->
          case a_latency < b_latency {
            True -> True
            False ->
              case a_latency > b_latency {
                True -> False
                False ->
                  case string.compare(a_id, b_id) {
                    order.Lt -> True
                    _ -> False
                  }
              }
          }
      }
  }
}

fn current_candidate(
  candidates: List(PathCandidate),
  current_path_id: String,
) -> Result(PathCandidate, Nil) {
  list.find(candidates, fn(candidate) {
    let PathCandidate(
      id: candidate_id,
      next_hop: _next_hop,
      estimated_cost_score: _estimated_cost_score,
      latency_ms: _latency_ms,
      packet_loss_bps: _packet_loss_bps,
      health: _health,
    ) = candidate

    candidate_id == current_path_id
  })
}

fn is_eligible(candidate: PathCandidate, policy: ControlPolicy) -> Bool {
  let PathCandidate(
    id: _id,
    next_hop: _next_hop,
    estimated_cost_score: _estimated_cost_score,
    latency_ms: latency_ms,
    packet_loss_bps: packet_loss_bps,
    health: health,
  ) = candidate
  let ControlPolicy(
    max_latency_ms: max_latency_ms,
    max_packet_loss_bps: max_packet_loss_bps,
    min_latency_improvement_ms: _min_latency_improvement_ms,
    min_cost_improvement_score: _min_cost_improvement_score,
    hold_down_ticks: _hold_down_ticks,
    cgnat_saturation_limit_bps: _cgnat_saturation_limit_bps,
  ) = policy

  case health {
    Critical -> False
    _ -> latency_ms <= max_latency_ms && packet_loss_bps <= max_packet_loss_bps
  }
}
