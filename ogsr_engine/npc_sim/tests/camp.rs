use npc_sim::{Action, Agent, FailureReason, Location, Observation, Phase, ScriptControl, Supply};
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
fn resident() -> Agent {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    assert!(a.enable_camp());
    a
}
fn reload(a: &Agent) -> Agent {
    let b = Agent::load(&a.save()).unwrap();
    assert_eq!(&b, a);
    b
}
#[test]
fn rest_fetch_and_return_share_one_command_sequence() {
    let mut a = resident();
    let rest = a.step(observation(0.), 1).decision;
    assert_eq!(rest.action, Action::Rest);
    assert_eq!(rest.phase, Phase::Resting);
    a = reload(&a);
    // Losing the bandage does not manufacture knowledge or wander aimlessly.
    assert_eq!(a.step(observation(0.), 0).decision.action, Action::Rest);
    assert!(a.remember(0, point(10.), point(10.)));
    let fetch = a.step(observation(0.), 0).decision;
    assert_eq!(fetch.action, Action::Travel(point(10.)));
    assert!(fetch.command > rest.command);
    a = reload(&a);
    assert_eq!(a.step(observation(10.), 0).decision.action, Action::Collect);
    let mut got = observation(10.);
    got.supply = Supply::Owned;
    let home = a.step(got, 1).decision;
    assert_eq!(home.action, Action::Travel(point(0.)));
    assert!(home.command > fetch.command);
    a = reload(&a);
    let rest2 = a.step(observation(0.), 1).decision;
    assert_eq!(rest2.action, Action::Rest);
    assert!(rest2.command > home.command);
    let mut later = observation(0.);
    later.elapsed_ms = 3_600_000;
    assert_eq!(a.step(later, 1).decision, rest2);
}
#[test]
fn danger_and_script_takeover_pause_rest_and_displacement_requires_a_return() {
    let mut a = resident();
    a.step(observation(0.), 1);
    let mut fight = observation(20.);
    fight.interrupted = true;
    assert_eq!(a.step(fight, 1).decision.action, Action::Wait);
    a = reload(&a);
    assert_eq!(
        a.step_controlled(observation(20.), 1, ScriptControl::Owned)
            .decision
            .action,
        Action::Wait
    );
    a = reload(&a);
    assert_eq!(
        a.step_controlled(observation(20.), 1, ScriptControl::Unobserved)
            .decision
            .action,
        Action::Wait
    );
    assert_eq!(
        a.step_controlled(observation(20.), 1, ScriptControl::Released)
            .decision
            .action,
        Action::Travel(point(0.))
    );
    assert_eq!(a.step(observation(0.), 1).decision.action, Action::Rest);
    let mut dead = observation(0.);
    dead.alive = false;
    assert_eq!(a.step(dead, 1).decision.phase, Phase::Dead);
    a = reload(&a);
    assert_eq!(a.step(observation(0.), 1).decision.phase, Phase::Dead);
}
#[test]
fn blocked_return_backs_off_across_reload_but_supply_can_preempt_it() {
    let mut a = resident();
    a.step(observation(30.), 0);
    let mut blocked = observation(30.);
    blocked.path_blocked = true;
    blocked.elapsed_ms = 60_000;
    let failed = a.step(blocked, 0).decision;
    assert_eq!(failed.action, Action::Wait);
    a = reload(&a);
    let mut wait = observation(30.);
    wait.elapsed_ms = 59_000;
    assert_eq!(a.step(wait, 0).decision.action, Action::Wait);
    a = reload(&a);
    assert!(a.remember(0, point(10.), point(10.)));
    assert_eq!(
        a.step(observation(30.), 0).decision.action,
        Action::Travel(point(10.))
    );
}
#[test]
fn unknown_position_cannot_execute_rest_and_rest_state_round_trips() {
    let mut a = resident();
    a.step(observation(0.), 1);
    let mut unknown = observation(0.);
    unknown.current.position[0] = f32::NAN;
    assert_eq!(a.step(unknown, 1).decision.action, Action::Wait);
    assert_eq!(a.status().decision.action, Action::Wait);
    a = reload(&a);
    assert_eq!(a.step(observation(0.), 1).decision.action, Action::Rest);
}
#[test]
fn previous_medical_save_can_enable_camp_without_losing_sources() {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    a.remember(0, point(10.), point(10.));
    a.step(observation(0.), 0);
    let mut old = a.save();
    old[48] &= 31;
    old[4..8].copy_from_slice(&6u32.to_le_bytes());
    let mut restored = Agent::load(&old).unwrap();
    assert_eq!(restored, a);
    assert!(restored.enable_camp());
    assert_eq!(restored.sources(), a.sources());
    assert_eq!(
        restored.step(observation(0.), 1).decision.action,
        Action::Rest
    );
}

#[test]
fn camp_snapshot_rejects_truncation_and_extra_bytes() {
    let mut a = resident();
    a.step(observation(0.), 1);
    let bytes = a.save();
    for size in 0..bytes.len() {
        assert!(
            Agent::load(&bytes[..size]).is_none(),
            "accepted prefix {size}"
        );
    }
    let mut extra = bytes.clone();
    extra.push(0);
    assert!(Agent::load(&extra).is_none());
}
#[test]
fn combat_time_is_not_charged_to_the_resumed_home_path() {
    let mut a = resident();
    a.step(observation(30.), 1);
    let mut o = observation(30.);
    o.interrupted = true;
    o.elapsed_ms = 60_000;
    assert_eq!(a.step(o, 1).decision.action, Action::Wait);
    a = reload(&a);
    o.interrupted = false;
    let d = a.step(o, 1).decision;
    assert_eq!(d.action, Action::Travel(point(0.)));
    assert_eq!(d.reason, FailureReason::None);
}

#[test]
fn a_return_observes_lost_position_and_resets_progress_after_combat() {
    let mut a = resident();
    a.step(observation(30.), 1);
    let mut stalled = observation(30.);
    stalled.elapsed_ms = 59_000;
    assert_eq!(a.step(stalled, 1).decision.phase, Phase::Returning);
    let mut combat = stalled;
    combat.interrupted = true;
    a.step(combat, 1);
    a = reload(&a);
    let mut resumed = observation(30.);
    resumed.elapsed_ms = 2000;
    assert_eq!(a.step(resumed, 1).decision.phase, Phase::Returning);
    assert_eq!(a.step(resumed, 1).decision.phase, Phase::Returning);
    let mut unknown = observation(30.);
    unknown.current.position[0] = f32::NAN;
    unknown.elapsed_ms = 300_000;
    assert_eq!(a.step(unknown, 1).decision.action, Action::Wait);
    assert_eq!(
        a.step(unknown, 1).decision.reason,
        FailureReason::PositionUnknown
    );
}

#[test]
fn a_failed_acquisition_falls_back_to_camp_without_forgetting_the_failure() {
    let mut a = resident();
    a.remember(0, point(10.), point(10.));
    a.step(observation(0.), 0);
    let mut missing = observation(10.);
    missing.supply = Supply::Missing;
    let d = a.step(missing, 0).decision;
    assert_eq!(d.action, Action::Travel(point(0.)));
    assert_eq!(a.sources()[0].failure, FailureReason::SupplyUnavailable);
    a = reload(&a);
    assert_eq!(a.step(observation(0.), 0).decision.action, Action::Rest);
}
#[test]
fn a_legacy_return_can_become_camp_execution_without_losing_inventory_policy() {
    let mut a = Agent::medical(7, point(0.)).unwrap();
    a.remember(0, point(10.), point(10.));
    a.step(observation(0.), 0);
    a.step(observation(10.), 1);
    let mut old = a.save();
    old[48] &= 31;
    old[4..8].copy_from_slice(&6u32.to_le_bytes());
    let mut restored = Agent::load(&old).unwrap();
    assert!(restored.enable_camp());
    assert_eq!(
        restored.step(observation(10.), 1).decision.action,
        Action::Travel(point(0.))
    );
    restored = reload(&restored);
    assert_eq!(
        restored.step(observation(0.), 1).decision.action,
        Action::Rest
    );
    assert_eq!(
        restored.step(observation(0.), 0).decision.action,
        Action::Travel(point(10.))
    );
}
