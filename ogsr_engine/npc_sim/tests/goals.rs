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
fn a_stocked_npc_returns_home_after_post_completion_combat_displacement() {
    let mut a = agent();
    assert_eq!(a.step(observation(0.), 1).decision.phase, Phase::Complete);
    let mut o = observation(40.);
    o.interrupted = true;
    assert_eq!(a.step(o, 1).decision.action, Action::Wait);
    let mut a = Agent::load(&a.save()).unwrap();
    o.interrupted = false;
    let returning = a.step(o, 1);
    assert_eq!(returning.decision.action, Action::Travel(point(0.)));
    assert_eq!(a.step(observation(0.), 1).decision.phase, Phase::Complete);
}

#[test]
fn small_nudges_do_not_restart_a_completed_return() {
    let mut a = agent();
    let done = a.step(observation(1.49), 1);
    assert_eq!(done.decision.phase, Phase::Complete);
    assert_eq!(a.step(observation(1.51), 1), done);
    assert_eq!(a.step(observation(2.99), 1), done);
    assert_eq!(
        a.step(observation(3.01), 1).decision.phase,
        Phase::Returning
    );
}

#[test]
fn full_memory_can_accept_news_without_false_failure_or_active_binding_replacement() {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    for i in 0..Agent::MAX_SOURCES {
        assert!(a.remember(i, point(10.), point(10.)));
    }
    a.step(observation(0.), 0);
    let slot = a.available_source_slot().unwrap();
    assert_eq!(slot, 1);
    assert!(a.remember(slot, point(20.), point(20.)));
    let second_slot = a.available_source_slot().unwrap();
    assert_eq!(second_slot, 2);
    assert!(a.remember(second_slot, point(30.), point(30.)));
    assert_eq!(a.sources()[slot].navigation, point(20.));
    assert!(a.remember(3, point(40.), point(40.)));
    assert_eq!(a.available_source_slot(), Some(4));
    a = Agent::load(&a.save()).unwrap();
    assert_eq!(a.available_source_slot(), Some(4));
    assert_eq!(a.status().source, Some(0));
    assert!(a.sources().iter().all(|s| s.failure == FailureReason::None));
    let mut o = observation(0.);
    o.elapsed_ms = 60_000;
    a.step(o, 0);
    // Prefer replacing a cooling route before an untried source, without
    // claiming the item disappeared just because its route was blocked.
    assert_eq!(a.available_source_slot(), Some(0));
    let mut restored = Agent::load(&a.save()).unwrap();
    assert!(restored.remember(0, point(4.), point(4.)));
    assert_ne!(restored.status().source, Some(0));
    assert_eq!(restored.sources()[0].failure, FailureReason::None);
}

#[test]
fn a_gift_at_the_source_trip_deadline_does_not_delay_the_untried_home_route() {
    let mut a = agent();
    a.step(observation(0.), 0);
    let mut o = observation(4.);
    o.elapsed_ms = 1_800_000;
    assert_eq!(a.step(o, 1).decision.action, Action::Travel(point(0.)));
}

#[test]
fn long_lived_agents_reuse_exhausted_memory_without_rebinding_the_active_source() {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    for i in 0..Agent::MAX_SOURCES * 3 {
        let slot = a
            .available_source_slot()
            .expect("Exhausted memories must be reusable");
        assert!(a.remember(slot, point(10.), point(10.)));
        let mut o = observation(0.);
        a.step(o, 0);
        assert_eq!(a.status().source, Some(slot));
        assert_ne!(a.available_source_slot(), Some(slot));
        o.current = point(10.);
        o.supply = Supply::Missing;
        assert_eq!(a.step(o, 0).decision.phase, Phase::Waiting);
        if i % Agent::MAX_SOURCES == 0 {
            a = Agent::load(&a.save()).unwrap();
        }
    }
    assert_eq!(a.sources().len(), Agent::MAX_SOURCES);
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

#[test]
fn source_recency_migrates_and_rejects_duplicate_or_out_of_range_ranks() {
    let a = agent();
    let saved = a.save();
    // NPCG v2 has the same header but omits the final rank word of each source.
    let mut previous = saved[..64].to_vec();
    previous[4..8].copy_from_slice(&2u32.to_le_bytes());
    for source in saved[64..].chunks_exact(64) {
        previous.extend_from_slice(&source[..56]);
    }
    assert_eq!(Agent::load(&previous).unwrap(), a);
    let mut duplicate = saved.clone();
    duplicate[64 + 64 + 56..64 + 64 + 60].copy_from_slice(&0u32.to_le_bytes());
    assert!(Agent::load(&duplicate).is_none());
    let mut outside = saved;
    outside[64 + 56..64 + 60].copy_from_slice(&2u32.to_le_bytes());
    assert!(Agent::load(&outside).is_none());
}

#[test]
fn script_control_survives_unobserved_intervals_and_reload_until_explicit_release() {
    use npc_sim::ScriptControl;
    let mut a = agent();
    a.step_controlled(observation(0.), 0, ScriptControl::Released);
    let mut o = observation(4.);
    o.elapsed_ms = 90_000;
    for control in [ScriptControl::Owned, ScriptControl::Unobserved] {
        let d = a.step_controlled(o, 0, control).decision;
        assert_eq!(d.action, Action::Wait);
        assert!(d.interrupted);
        assert_eq!(d.phase, Phase::Outbound);
        a = Agent::load(&a.save()).unwrap();
    }
    let gift = a.step_controlled(o, 1, ScriptControl::Unobserved).decision;
    assert_eq!(gift.phase, Phase::Returning);
    assert_eq!(gift.action, Action::Wait);
    a = Agent::load(&a.save()).unwrap();
    let resumed = a.step_controlled(o, 1, ScriptControl::Released).decision;
    assert_eq!(resumed.action, Action::Travel(point(0.)));
    assert_eq!(resumed.reason, FailureReason::None);
}

#[test]
fn old_goal_saves_default_to_no_script_owner() {
    use npc_sim::ScriptControl;
    let mut a = agent();
    a.step_controlled(observation(0.), 0, ScriptControl::Released);
    let mut bytes = legacy_v4(&a.save());
    bytes[4..8].copy_from_slice(&3u32.to_le_bytes());
    let mut restored = Agent::load(&bytes).unwrap();
    assert_eq!(
        restored
            .step_controlled(observation(0.), 0, ScriptControl::Unobserved)
            .decision
            .action,
        Action::Travel(point(10.))
    );
    a.step_controlled(observation(0.), 0, ScriptControl::Owned);
    let mut invalid_old = legacy_v4(&a.save());
    invalid_old[4..8].copy_from_slice(&3u32.to_le_bytes());
    assert!(Agent::load(&invalid_old).is_none());
}

#[test]
fn assigned_trip_also_honors_persisted_script_control() {
    use npc_sim::ScriptControl;
    let mut original = agent();
    original.step(observation(0.), 0);
    // The legacy activity snapshot is the final activity bytes of the envelope.
    let bytes = original.save();
    let mut a = Agent::load(&bytes[bytes.len() - Plan::SNAPSHOT_SIZE..]).unwrap();
    assert!(!a.is_medical());
    a.step_controlled(observation(0.), 0, ScriptControl::Owned);
    a = Agent::load(&a.save()).unwrap();
    assert_eq!(
        a.step_controlled(observation(0.), 0, ScriptControl::Unobserved)
            .decision
            .action,
        Action::Wait
    );
    assert_eq!(
        a.step_controlled(observation(0.), 0, ScriptControl::Released)
            .decision
            .action,
        Action::Travel(point(10.))
    );
}

#[test]
fn temporary_reaction_does_not_suspend_offline_travel() {
    use npc_sim::ScriptControl;
    let mut a = agent();
    a.step_controlled(observation(0.), 0, ScriptControl::Released);
    let mut meet = observation(4.);
    meet.interrupted = true;
    assert_eq!(
        a.step_controlled(meet, 0, ScriptControl::Released)
            .decision
            .action,
        Action::Wait
    );
    a = Agent::load(&a.save()).unwrap();
    assert_eq!(
        a.step_controlled(observation(4.), 0, ScriptControl::Unobserved)
            .decision
            .action,
        Action::Travel(point(10.))
    );
}

#[test]
fn script_released_during_combat_can_continue_offline() {
    use npc_sim::ScriptControl;
    let mut a = agent();
    a.step_controlled(observation(0.), 0, ScriptControl::Owned);
    let mut combat = observation(4.);
    combat.interrupted = true;
    assert_eq!(
        a.step_controlled(combat, 0, ScriptControl::Released)
            .decision
            .action,
        Action::Wait
    );
    assert_eq!(
        a.step_controlled(observation(4.), 0, ScriptControl::Unobserved)
            .decision
            .action,
        Action::Travel(point(10.))
    );
}

#[test]
fn saving_a_new_script_owner_does_not_advance_the_activity() {
    use npc_sim::ScriptControl;
    let mut a = agent();
    let before = a.step(observation(0.), 0).decision;
    a.report_script_control(ScriptControl::Owned);
    assert_eq!(a.status().decision, before);
    let mut restored = Agent::load(&a.save()).unwrap();
    let paused = restored
        .step_controlled(observation(4.), 0, ScriptControl::Unobserved)
        .decision;
    assert_eq!(paused.phase, Phase::Outbound);
    assert_eq!(paused.action, Action::Wait);
    restored.report_script_control(ScriptControl::Released);
    let mut released = Agent::load(&restored.save()).unwrap();
    assert_eq!(
        released.step(observation(4.), 0).decision.action,
        Action::Travel(point(10.))
    );
}

#[test]
fn personal_sightings_discover_sources_without_resetting_travel_or_retry() {
    use npc_sim::SourceObservation::{Unchanged, Updated};
    let mut a = Agent::medical(7, point(0.)).unwrap();
    assert_eq!(a.step(observation(0.), 0).decision.phase, Phase::Waiting);
    assert_eq!(a.observe_source(0, point(10.), point(10.)), Updated);
    let first = a.step(observation(0.), 0);
    assert_eq!(first.decision.action, Action::Travel(point(10.)));
    let mut o = observation(0.);
    o.elapsed_ms = 10_000;
    for _ in 0..6 {
        let before = a.save();
        assert_eq!(a.observe_source(0, point(10.1), point(10.1)), Unchanged);
        assert_eq!(a.save(), before);
        a.step(o, 0);
    }
    assert_eq!(a.status().decision.phase, Phase::Waiting);
    let mut a = Agent::load(&a.save()).unwrap();
    for _ in 0..5 {
        assert_eq!(a.observe_source(0, point(10.), point(10.)), Unchanged);
        assert_eq!(a.step(o, 0).decision.phase, Phase::Waiting);
    }
    assert_eq!(a.observe_source(0, point(10.), point(10.)), Unchanged);
    let retry = a.step(o, 0);
    assert_eq!(retry.decision.phase, Phase::Outbound);
    assert!(retry.decision.command > first.decision.command);
}

#[test]
fn seen_movement_is_news_but_unseen_movement_is_not_a_destination() {
    use npc_sim::SourceObservation::Updated;
    let mut a = Agent::medical(7, point(0.)).unwrap();
    assert_eq!(a.observe_source(0, point(10.), point(10.)), Updated);
    let first = a.step(observation(0.), 0);
    let mut o = observation(2.);
    o.supply_location = point(20.);
    assert_eq!(a.step(o, 0).decision.action, Action::Travel(point(10.)));
    assert_eq!(a.observe_source(0, point(20.), point(20.)), Updated);
    let moved = a.step(o, 0);
    assert_eq!(moved.decision.action, Action::Travel(point(20.)));
    assert!(moved.decision.command > first.decision.command);
    let a = Agent::load(&a.save()).unwrap();
    assert_eq!(a.sources()[0].physical, point(20.));
    assert_eq!(a.status(), moved);
}

#[test]
fn actual_rediscovery_reopens_an_unavailable_source_and_rejects_invalid_news() {
    use npc_sim::SourceObservation::{Rejected, Updated};
    let mut a = Agent::medical(7, point(0.)).unwrap();
    a.observe_source(0, point(10.), point(10.));
    a.step(observation(0.), 0);
    let mut absent = observation(10.);
    absent.supply = Supply::Missing;
    a.step(absent, 0);
    assert_eq!(a.sources()[0].failure, FailureReason::SupplyUnavailable);
    assert_eq!(a.observe_source(0, point(10.), point(10.)), Updated);
    assert_eq!(a.sources()[0].failure, FailureReason::None);
    let before = a.save();
    assert_eq!(a.observe_source(2, point(10.), point(10.)), Rejected);
    let mut invalid = point(10.);
    invalid.position[0] = f32::NAN;
    assert_eq!(a.observe_source(0, invalid, point(10.)), Rejected);
    assert_eq!(a.save(), before);
    let mut assigned = Agent::assigned(Plan::new(8, point(0.), point(10.), point(10.)).unwrap());
    assert_eq!(assigned.observe_source(0, point(20.), point(20.)), Rejected);
}

#[test]
fn small_nudges_and_navigation_snapping_preserve_pending_pickup() {
    use npc_sim::SourceObservation::{Unchanged, Updated};
    let mut a = Agent::medical(7, point(0.)).unwrap();
    a.observe_source(0, point(10.), point(10.));
    a.step(observation(0.), 0);
    let collecting = a.step(observation(10.), 0);
    assert_eq!(collecting.decision.phase, Phase::Collecting);
    let before = a.save();
    // Navigation may snap to another vertex without meaningful physical motion.
    for physical in [10.25, 10.5, 10.75, 11.] {
        assert_eq!(a.observe_source(0, point(12.), point(physical)), Unchanged);
        assert_eq!(a.save(), before);
    }
    let mut pending = observation(10.);
    pending.supply_location = point(10.5);
    pending.pickup_pending = true;
    let waiting = a.step(pending, 0);
    assert_eq!(waiting.decision.command, collecting.decision.command);
    assert_eq!(waiting.decision.action, Action::Wait);
    assert_eq!(a.observe_source(0, point(12.), point(11.01)), Updated);
    assert!(a.step(pending, 0).decision.command > collecting.decision.command);
}

#[test]
fn seeing_a_previously_moved_item_back_at_its_old_position_is_fresh_evidence() {
    use npc_sim::SourceObservation::Updated;
    let mut a = Agent::medical(7, point(0.)).unwrap();
    a.observe_source(0, point(10.), point(10.));
    a.step(observation(0.), 0);
    let mut moved = observation(10.);
    moved.supply_location = point(20.);
    a.step(moved, 0);
    assert_eq!(a.sources()[0].failure, FailureReason::SupplyMoved);
    // The item has returned and is personally seen, rather than read remotely.
    assert_eq!(a.observe_source(0, point(10.), point(10.)), Updated);
    assert_eq!(a.sources()[0].failure, FailureReason::None);
    assert_eq!(
        a.step(observation(0.), 0).decision.action,
        Action::Travel(point(10.))
    );
}

#[test]
fn sightings_refresh_eviction_recency_across_save_without_restarting_the_trip() {
    use npc_sim::SourceObservation::Unchanged;
    let mut a = Agent::medical(7, point(0.)).unwrap();
    for index in 0..Agent::MAX_SOURCES {
        let source = point(10. + index as f32 * 10.);
        assert!(a.remember(index, source, source));
    }
    let trip = a.step(observation(0.), 0);
    assert_eq!(trip.source, Some(0));
    assert_eq!(a.available_source_slot(), Some(1)); // selected source cannot be evicted
    assert_eq!(a.observe_source(1, point(20.), point(20.)), Unchanged);
    assert_eq!(a.status(), trip);
    assert_eq!(a.available_source_slot(), Some(2));
    let mut a = Agent::load(&a.save()).unwrap();
    assert_eq!(a.status(), trip);
    assert_eq!(a.available_source_slot(), Some(2));
    assert_eq!(a.observe_source(2, point(30.), point(30.)), Unchanged);
    assert_eq!(a.available_source_slot(), Some(3));
    // Repeated observations of the newest source need no rank changes.
    let before = a.save();
    assert_eq!(a.observe_source(2, point(30.), point(30.)), Unchanged);
    assert_eq!(a.save(), before);
    let mut stalled = observation(0.);
    stalled.elapsed_ms = 60_000;
    a.step(stalled, 0);
    assert_ne!(a.status().source, Some(0)); // sightings did not renew travel time
}

fn legacy_v4(bytes: &[u8]) -> Vec<u8> {
    let count = u32::from_le_bytes(bytes[60..64].try_into().unwrap()) as usize;
    let mut old = bytes[..64].to_vec();
    old[4..8].copy_from_slice(&4u32.to_le_bytes());
    for source in bytes[64..64 + count * 64].chunks_exact(64) {
        old.extend_from_slice(&source[..60]);
    }
    old.extend_from_slice(&bytes[64 + count * 64..]);
    old
}

#[test]
fn version_four_sources_restore_as_loose_items() {
    let a = agent();
    assert_eq!(Agent::load(&legacy_v4(&a.save())).unwrap(), a);
}

#[test]
fn corpse_search_requires_arrival_and_survives_save_and_interruption() {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    assert!(a.remember_corpse(0, point(10.), point(10.)));
    let travel = a.step(observation(0.), 0).decision;
    assert_eq!(travel.action, Action::Travel(point(10.)));
    assert!(!a.searched(travel.command, true));
    a = Agent::load(&a.save()).unwrap();
    let mut combat = observation(10.);
    combat.interrupted = true;
    assert_eq!(a.step(combat, 0).decision.action, Action::Wait);
    assert!(!a.searched(a.status().decision.command, true));
    let search = a.step(observation(10.), 0).decision;
    assert_eq!(search.action, Action::Inspect);
    assert!(!a.searched(search.command - 1, true));
    assert!(a.searched(search.command, true));
    let returned = a.step(observation(10.), 1).decision;
    assert_eq!(returned.action, Action::Travel(point(0.)));
    assert_eq!(a.step(observation(0.), 1).decision.phase, Phase::Complete);
}

#[test]
fn empty_search_is_remembered_across_sightings_and_reload() {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    a.remember_corpse(0, point(10.), point(10.));
    a.step(observation(0.), 0);
    let search = a.step(observation(10.), 0).decision;
    assert!(a.searched(search.command, true));
    a = Agent::load(&a.save()).unwrap();
    a.observe_source(0, point(10.), point(10.));
    assert_eq!(a.step(observation(10.), 0).decision.phase, Phase::Waiting);
    for _ in 0..5 {
        a.observe_source(0, point(10.), point(10.));
        assert_eq!(a.step(observation(10.), 0).decision.phase, Phase::Waiting);
    }
    // Another corpse can reuse the same slot, but it is explicit new identity.
    a.remember_corpse(0, point(10.), point(10.));
    a.step(observation(10.), 0);
    assert_eq!(a.step(observation(10.), 0).decision.action, Action::Inspect);
}

#[test]
fn corpse_and_item_share_execution_but_have_distinct_interactions() {
    let mut a = agent();
    a.remember_corpse(0, point(10.), point(10.));
    a.step(observation(0.), 0);
    let search = a.step(observation(10.), 0).decision;
    a.searched(search.command, true);
    assert_eq!(a.step(observation(10.), 0).source, Some(1));
    let mut o = observation(20.);
    o.supply_location = point(20.);
    assert_eq!(a.step(o, 0).decision.action, Action::Collect);
}

#[test]
fn unseen_corpse_loss_is_learned_only_at_destination() {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    a.remember_corpse(0, point(10.), point(10.));
    a.step(observation(0.), 0);
    let mut o = observation(3.);
    o.supply = Supply::Missing;
    assert_eq!(a.step(o, 0).decision.action, Action::Travel(point(10.)));
    o.current = point(10.);
    assert_eq!(a.step(o, 0).decision.phase, Phase::Waiting);
}

#[test]
fn remaining_corpse_supply_can_be_used_after_inventory_is_consumed() {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    a.remember_corpse(0, point(10.), point(10.));
    a.step(observation(0.), 0);
    let search = a.step(observation(10.), 0).decision;
    assert!(a.searched(search.command, false));
    assert_eq!(a.step(observation(10.), 1).decision.phase, Phase::Returning);
    assert_eq!(a.step(observation(0.), 1).decision.phase, Phase::Complete);
    a = Agent::load(&a.save()).unwrap();
    assert_eq!(a.step(observation(0.), 0).decision.phase, Phase::Outbound);
    let again = a.step(observation(10.), 0).decision;
    assert_eq!(again.action, Action::Inspect);
    assert!(again.command > search.command);
    assert!(!a.searched(search.command, true));
    assert!(a.searched(again.command, true));
    a.step(observation(10.), 1);
    a.step(observation(0.), 1);
    assert_eq!(a.step(observation(0.), 0).decision.phase, Phase::Waiting);
}

#[test]
fn corpse_snapshot_rejects_unknown_kind_and_truncated_source() {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    a.remember_corpse(0, point(10.), point(10.));
    let saved = a.save();
    for end in 0..saved.len() {
        assert!(Agent::load(&saved[..end]).is_none());
    }
    let mut invalid = saved.clone();
    invalid[124..128].copy_from_slice(&2u32.to_le_bytes());
    assert!(Agent::load(&invalid).is_none());
    assert_eq!(Agent::load(&saved).unwrap(), a);
}

#[test]
fn moving_an_empty_body_does_not_reveal_new_contents() {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    a.remember_corpse(0, point(10.), point(10.));
    a.step(observation(0.), 0);
    let search = a.step(observation(10.), 0).decision;
    assert!(a.searched(search.command, true));
    a.step(observation(10.), 0);
    a.observe_source(0, point(20.), point(20.));
    assert_eq!(a.sources()[0].physical, point(20.));
    assert_eq!(a.step(observation(10.), 0).decision.phase, Phase::Waiting);
}
