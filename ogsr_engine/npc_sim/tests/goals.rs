use npc_sim::{Action, Agent, FailureReason, Location, Observation, Phase, Plan, Supply};

fn point(x: f32) -> Location {
    Location {
        game_vertex: 1,
        level_vertex: 2,
        level: 0,
        position: [x, 0., 0.],
    }
}
fn observation(x: f32) -> Observation {
    Observation {
        current: point(x),
        supply_location: point(10.),
        supply: Supply::Free,
        representation_ready: true,
        pickup_pending: false,
        path_blocked: false,
        elapsed_ms: 100,
        edge_distance: 0.,
        interrupted: false,
        alive: true,
    }
}
fn agent() -> Agent {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    assert!(a.remember(0, point(10.), point(10.)));
    assert!(a.remember(1, point(20.), point(20.)));
    a
}

#[test]
fn any_bandage_satisfies_need_and_loss_replaces_the_return_trip() {
    let mut a = agent();
    let outbound = a.step(observation(0.), 0);
    assert_eq!(outbound.source, Some(0));
    assert_eq!(outbound.decision.action, Action::Travel(point(10.)));
    let homeward = a.step(observation(4.), 1); // gift, loot or another real acquisition
    assert_eq!(homeward.decision.action, Action::Travel(point(0.)));
    assert!(homeward.decision.command > outbound.decision.command);
    let renewed = a.step(observation(3.), 0);
    assert_eq!(renewed.decision.phase, Phase::Outbound);
    assert!(renewed.decision.command > homeward.decision.command);
    assert_eq!(a.sources()[0].failure, FailureReason::None);
    a.step(observation(3.), 1);
    assert_eq!(a.step(observation(0.), 1).decision.phase, Phase::Complete);
    let complete = a.status();
    assert_eq!(a.step(observation(0.), 1), complete);
    assert_eq!(a.step(observation(0.), 0).decision.phase, Phase::Outbound);
}

#[test]
fn initially_stocked_npc_does_not_go_collect() {
    let mut a = agent();
    assert_eq!(a.step(observation(0.), 2).decision.phase, Phase::Complete);
    assert_eq!(a.status().source, None);
    assert_eq!(a.step(observation(0.), 0).source, Some(0));
}

#[test]
fn source_loss_is_learned_on_arrival_and_old_facts_do_not_poison_next_source() {
    let mut a = agent();
    a.step(observation(0.), 0);
    let mut o = observation(3.);
    o.supply = Supply::OtherOwner;
    assert_eq!(a.step(o, 0).source, Some(0));
    assert_eq!(a.sources()[0].failure, FailureReason::None);
    o.current = point(10.);
    let next = a.step(o, 0);
    assert_eq!(next.source, Some(1));
    assert_eq!(next.decision.action, Action::Travel(point(20.)));
    assert_eq!(a.sources()[0].failure, FailureReason::SupplyUnavailable);
    assert_eq!(a.sources()[1].failure, FailureReason::None);
    o.current = point(20.);
    o.supply_location = point(20.);
    assert_eq!(a.step(o, 0).decision.phase, Phase::Waiting);
    let waiting = a.status();
    for _ in 0..20 {
        assert_eq!(a.step(o, 0), waiting);
    }
    assert!(a.remember(0, point(12.), point(12.)));
    assert_eq!(a.step(o, 0).decision.action, Action::Travel(point(12.)));
}

#[test]
fn picked_source_is_exhausted_but_an_unvisited_source_is_not() {
    let mut a = agent();
    a.step(observation(0.), 0);
    assert_eq!(a.step(observation(10.), 0).decision.action, Action::Collect);
    let mut o = observation(10.);
    o.supply = Supply::Owned;
    assert_eq!(a.step(o, 1).decision.phase, Phase::Returning);
    assert_eq!(a.sources()[0].failure, FailureReason::SupplyUnavailable);
    o.current = point(0.);
    a.step(o, 1);
    o.supply = Supply::Missing;
    assert_eq!(a.step(o, 0).source, Some(1));
}

#[test]
fn pending_pickup_and_unavailable_representation_produce_wait_not_reissued_collect() {
    let mut a = agent();
    a.step(observation(0.), 0);
    let mut o = observation(10.);
    assert_eq!(a.step(o, 0).decision.action, Action::Collect);
    o.pickup_pending = true;
    assert_eq!(a.step(o, 0).decision.action, Action::Wait);
    o.elapsed_ms = 20_000;
    o.representation_ready = false;
    assert_eq!(a.step(o, 0).decision.action, Action::Wait);
    o.representation_ready = true;
    assert_eq!(a.step(o, 0).decision.phase, Phase::Collecting);
    // A late pickup after another acquisition still satisfies the same need.
    o.supply = Supply::Owned;
    assert_eq!(a.step(o, 2).decision.phase, Phase::Returning);
}

#[test]
fn inventory_during_combat_revises_intent_without_executing_or_charging_combat() {
    let mut a = agent();
    a.step(observation(0.), 0);
    let mut o = observation(4.);
    o.interrupted = true;
    o.elapsed_ms = 120_000;
    let interrupted = a.step(o, 1);
    assert_eq!(interrupted.decision.phase, Phase::Returning);
    assert_eq!(interrupted.decision.action, Action::Wait);
    let mut a = Agent::load(&a.save()).unwrap();
    o.interrupted = false;
    assert_eq!(a.step(o, 1).decision.action, Action::Travel(point(0.)));
}

#[test]
fn waiting_knowledge_and_each_trip_transition_survive_reload() {
    let mut a = agent();
    let mut o = observation(0.);
    for (position, supply, bandages, interrupted) in [
        (0., Supply::Free, 0, false),
        (4., Supply::Free, 1, true),
        (4., Supply::Free, 1, false),
        (0., Supply::Free, 1, false),
        (0., Supply::Free, 0, false),
        (10., Supply::Missing, 0, false),
        (20., Supply::Missing, 0, false),
        (0., Supply::Missing, 0, false),
    ] {
        let mut restored = Agent::load(&a.save()).unwrap();
        o.current = point(position);
        o.supply = supply;
        o.interrupted = interrupted;
        assert_eq!(a.step(o, bandages), restored.step(o, bandages));
        assert_eq!(a.save(), restored.save());
    }
    assert_eq!(a.status().decision.phase, Phase::Waiting);
    assert!(a.sources().iter().all(|s| s.failure != FailureReason::None));
}

#[test]
fn failed_returns_retry_after_a_persisted_cooldown_without_poisoning_sources() {
    let mut a = agent();
    a.step(observation(0.), 0);
    a.step(observation(4.), 1);
    let mut o = observation(4.);
    o.elapsed_ms = 60_000;
    assert_eq!(a.step(o, 1).decision.phase, Phase::Failed);
    let failed = a.status();
    o.elapsed_ms = 10_000;
    for _ in 0..5 {
        assert_eq!(a.step(o, 1), failed);
    }
    let mut restored = Agent::load(&a.save()).unwrap();
    let retry = restored.step(o, 1);
    assert_eq!(retry.decision.phase, Phase::Returning);
    assert!(retry.decision.command > failed.decision.command);
    let renewed = restored.step(o, 0);
    assert_eq!(renewed.decision.phase, Phase::Outbound);
    assert_eq!(renewed.source, Some(0));
    assert_eq!(a.sources()[0].failure, FailureReason::None);
}

#[test]
fn a_stalled_source_is_temporarily_delayed_not_forgotten() {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    a.remember(0, point(10.), point(10.));
    let first = a.step(observation(0.), 0);
    let mut o = observation(0.);
    o.elapsed_ms = 60_000;
    assert_eq!(a.step(o, 0).decision.phase, Phase::Waiting);
    assert_eq!(a.sources()[0].failure, FailureReason::None);
    o.elapsed_ms = 30_000;
    assert_eq!(a.step(o, 0).decision.phase, Phase::Waiting);
    let mut a = Agent::load(&a.save()).unwrap();
    o.interrupted = true;
    o.elapsed_ms = 120_000;
    assert_eq!(a.step(o, 0).decision.phase, Phase::Waiting);
    o.interrupted = false;
    assert_eq!(a.step(o, 0).decision.phase, Phase::Waiting);
    o.elapsed_ms = 29_999;
    assert_eq!(a.step(o, 0).decision.phase, Phase::Waiting);
    o.elapsed_ms = 1;
    let retry = a.step(o, 0);
    assert_eq!(retry.source, Some(0));
    assert_eq!(retry.decision.action, Action::Travel(point(10.)));
    assert!(retry.decision.command > first.decision.command);
}

#[test]
fn another_source_can_be_tried_while_a_stalled_route_cools_down() {
    let mut a = agent();
    a.step(observation(0.), 0);
    let mut o = observation(0.);
    o.elapsed_ms = 60_000;
    let alternative = a.step(o, 0);
    assert_eq!(alternative.source, Some(1));
    assert_eq!(a.sources()[0].failure, FailureReason::None);
}

#[test]
fn fresh_information_replaces_an_active_destination_but_not_a_return_home() {
    let mut a = agent();
    let old = a.step(observation(0.), 0);
    assert!(a.remember(0, point(12.), point(12.)));
    assert!(a.status().decision.command > old.decision.command);
    let mut a = Agent::load(&a.save()).unwrap();
    let revised = a.step(observation(4.), 0);
    assert_eq!(revised.decision.action, Action::Travel(point(12.)));
    assert!(revised.decision.command > old.decision.command);
    let returning = a.step(observation(4.), 1);
    assert!(a.remember(0, point(14.), point(14.)));
    assert_eq!(a.step(observation(4.), 1), returning);
}

#[test]
fn legacy_snapshot_keeps_assigned_item_semantics() {
    let mut plan = Plan::new(7, point(0.), point(10.), point(10.)).unwrap();
    plan.step(observation(0.));
    let mut a = Agent::load(&plan.save()).unwrap();
    assert!(!a.is_medical());
    assert_eq!(a.step(observation(4.), 5).decision.phase, Phase::Outbound);
    assert_eq!(Agent::load(&a.save()).unwrap(), a);
}

#[test]
fn truncated_snapshots_and_invalid_memory_are_rejected_without_panics() {
    let mut a = agent();
    a.step(observation(0.), 0);
    let saved = a.save();
    for n in 0..saved.len() {
        assert!(Agent::load(&saved[..n]).is_none());
    }
    let mut trailing = saved.clone();
    trailing.push(0);
    assert!(Agent::load(&trailing).is_none());
    let mut invalid = point(10.);
    invalid.position[0] = f32::NAN;
    assert!(!a.remember(0, invalid, point(10.)));
    assert!(!a.remember(3, point(10.), point(10.)));
    assert_eq!(a.save(), saved);
}
