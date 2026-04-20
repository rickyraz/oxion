import gleeunit
import oxbgp

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn edge_transit_role_uses_frr_test() {
  assert oxbgp.engine_for_role(oxbgp.EdgeTransit) == oxbgp.Frr
}

pub fn ixp_route_server_role_uses_bird_test() {
  assert oxbgp.engine_for_role(oxbgp.IxpRouteServer) == oxbgp.Bird
}

pub fn opinionated_plan_is_hybrid_and_non_optional_test() {
  assert oxbgp.opinionated_control_plane_plan()
    == oxbgp.ControlPlanePlan(
      edge_transit_engine: oxbgp.Frr,
      ixp_route_server_engine: oxbgp.Bird,
    )
}

pub fn switches_to_better_path_when_threshold_met_test() {
  let input =
    oxbgp.ControlInput(
      current_path_id: "upstream_a",
      candidates: [
        candidate("upstream_a", 120, 60, 400, oxbgp.Healthy),
        candidate("peer_ix", 80, 25, 120, oxbgp.Healthy),
      ],
      ticks_since_last_switch: 12,
      cgnat_saturation_bps: 400,
    )

  assert oxbgp.evaluate(input, default_policy())
    == oxbgp.SwitchTo(path_id: "peer_ix", reason: "optimizer_threshold_met")
}

pub fn keeps_current_when_hold_down_is_active_test() {
  let input =
    oxbgp.ControlInput(
      current_path_id: "upstream_a",
      candidates: [
        candidate("upstream_a", 120, 60, 400, oxbgp.Healthy),
        candidate("peer_ix", 80, 20, 100, oxbgp.Healthy),
      ],
      ticks_since_last_switch: 1,
      cgnat_saturation_bps: 100,
    )

  assert oxbgp.evaluate(input, default_policy())
    == oxbgp.KeepCurrent(reason: "hold_down_active")
}

pub fn keeps_current_when_cgnat_saturation_is_high_test() {
  let input =
    oxbgp.ControlInput(
      current_path_id: "upstream_a",
      candidates: [
        candidate("upstream_a", 120, 60, 400, oxbgp.Healthy),
        candidate("peer_ix", 80, 20, 100, oxbgp.Healthy),
      ],
      ticks_since_last_switch: 12,
      cgnat_saturation_bps: 980,
    )

  assert oxbgp.evaluate(input, default_policy())
    == oxbgp.KeepCurrent(reason: "cgnat_saturation_high")
}

pub fn uses_lexicographic_tie_break_for_determinism_test() {
  let input =
    oxbgp.ControlInput(
      current_path_id: "missing_path",
      candidates: [
        candidate("upstream_b", 100, 40, 200, oxbgp.Healthy),
        candidate("upstream_a", 100, 40, 200, oxbgp.Healthy),
      ],
      ticks_since_last_switch: 12,
      cgnat_saturation_bps: 120,
    )

  assert oxbgp.evaluate(input, default_policy())
    == oxbgp.SwitchTo(path_id: "upstream_a", reason: "current_path_missing")
}

fn default_policy() -> oxbgp.ControlPolicy {
  oxbgp.ControlPolicy(
    max_latency_ms: 100,
    max_packet_loss_bps: 500,
    min_latency_improvement_ms: 10,
    min_cost_improvement_score: 10,
    hold_down_ticks: 3,
    cgnat_saturation_limit_bps: 950,
  )
}

fn candidate(
  id: String,
  estimated_cost_score: Int,
  latency_ms: Int,
  packet_loss_bps: Int,
  health: oxbgp.PathHealth,
) -> oxbgp.PathCandidate {
  oxbgp.PathCandidate(
    id: id,
    next_hop: "192.0.2.1",
    estimated_cost_score: estimated_cost_score,
    latency_ms: latency_ms,
    packet_loss_bps: packet_loss_bps,
    health: health,
  )
}
