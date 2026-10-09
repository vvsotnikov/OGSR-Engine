use npc_sim::{Action, Location, Observation, Phase, Plan, Supply};

const HOME: Location = Location {
    game_vertex: 1,
    level_vertex: 10,
    position: [0., 0., 0.],
};
const SOURCE: Location = Location {
    game_vertex: 2,
    level_vertex: 20,
    position: [30., 0., 0.],
};
fn observation() -> Observation {
    Observation {
        at_source: false,
        at_home: false,
        supply: Supply::Unknown,
        interrupted: false,
        alive: true,
        execution_failed: false,
    }
}

#[test]
fn trip_waits_for_inventory_confirmation_and_survives_interruption() {
    let mut plan = Plan::new(1234, HOME, SOURCE).unwrap();
    let walking = plan.step(observation());
    assert_eq!(walking.action, Action::Travel(SOURCE));
    let pause = plan.step(Observation {
        interrupted: true,
        ..observation()
    });
    assert_eq!(pause.action, Action::Wait);
    assert_eq!(pause.command, walking.command);
    let mut plan = Plan::load(&plan.save()).unwrap();
    assert_eq!(plan.decision(), pause);
    assert_eq!(plan.step(observation()), walking);
    let at_source = Observation {
        at_source: true,
        supply: Supply::Available,
        ..observation()
    };
    let collect = plan.step(at_source);
    assert_eq!(collect.action, Action::Collect);
    assert_eq!(plan.step(at_source), collect); // no optimistic inventory update
    let returning = plan.step(Observation {
        supply: Supply::Owned,
        ..observation()
    });
    assert_eq!(returning.action, Action::Travel(HOME));
    assert!(returning.command > collect.command);
    assert_eq!(
        plan.step(Observation {
            at_home: true,
            supply: Supply::Owned,
            ..observation()
        })
        .phase,
        Phase::Complete
    );
    assert_eq!(plan.step(observation()).phase, Phase::Complete);
}

#[test]
fn serialized_replay_matches_uninterrupted_decisions_at_every_boundary() {
    let events = [
        observation(),
        Observation {
            interrupted: true,
            ..observation()
        },
        observation(),
        Observation {
            at_source: true,
            supply: Supply::Available,
            ..observation()
        },
        Observation {
            at_source: true,
            supply: Supply::Owned,
            interrupted: true,
            ..observation()
        },
        Observation {
            supply: Supply::Owned,
            ..observation()
        },
        Observation {
            at_home: true,
            supply: Supply::Owned,
            ..observation()
        },
    ];
    let mut baseline = Plan::new(42, HOME, SOURCE).unwrap();
    let expected: Vec<_> = events.iter().map(|&e| baseline.step(e)).collect();
    for boundary in 0..=events.len() {
        let mut plan = Plan::new(42, HOME, SOURCE).unwrap();
        for &event in &events[..boundary] {
            plan.step(event);
        }
        let mut restored = Plan::load(&plan.save()).unwrap();
        let actual: Vec<_> = events[boundary..]
            .iter()
            .map(|&e| restored.step(e))
            .collect();
        assert_eq!(actual, expected[boundary..]);
    }
}

#[test]
fn unavailable_supply_is_discovered_at_destination_not_omnisciently() {
    let mut plan = Plan::new(1, HOME, SOURCE).unwrap();
    assert_eq!(
        plan.step(Observation {
            supply: Supply::Unavailable,
            ..observation()
        })
        .phase,
        Phase::Outbound
    );
    assert_eq!(
        plan.step(Observation {
            at_source: true,
            supply: Supply::Unavailable,
            ..observation()
        })
        .phase,
        Phase::Failed
    );
}

#[test]
fn displacement_reissues_travel_without_collecting_remotely() {
    let mut plan = Plan::new(1, HOME, SOURCE).unwrap();
    let collect = plan.step(Observation {
        at_source: true,
        supply: Supply::Available,
        ..observation()
    });
    let displaced = plan.step(observation());
    assert_eq!(displaced.action, Action::Travel(SOURCE));
    assert!(displaced.command > collect.command);
}

#[test]
fn loss_execution_failure_and_death_stop_the_trip() {
    for event in [
        Observation {
            execution_failed: true,
            ..observation()
        },
        Observation {
            alive: false,
            ..observation()
        },
    ] {
        let mut plan = Plan::new(1, HOME, SOURCE).unwrap();
        assert_eq!(plan.step(event).action, Action::Wait);
        assert_eq!(plan.step(observation()).action, Action::Wait);
    }
    let mut plan = Plan::new(1, HOME, SOURCE).unwrap();
    plan.step(Observation {
        supply: Supply::Owned,
        ..observation()
    });
    assert_eq!(plan.step(observation()).phase, Phase::Failed);
}

#[test]
fn malformed_snapshots_are_rejected() {
    let snapshot = Plan::new(1, HOME, SOURCE).unwrap().save();
    for length in 0..snapshot.len() {
        assert!(Plan::load(&snapshot[..length]).is_none());
    }
    let mut extra = snapshot.clone();
    extra.push(0);
    assert!(Plan::load(&extra).is_none());
    for offset in [0, 4, 12, 20, 60, 64] {
        let mut invalid = snapshot.clone();
        match offset {
            4 | 12 => invalid[offset..offset + 8].fill(0),
            _ => invalid[offset..offset + 4].fill(255),
        }
        assert!(Plan::load(&invalid).is_none(), "offset {offset}");
    }
}
