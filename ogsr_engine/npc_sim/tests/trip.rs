use npc_sim::{Action, Location, Observation, Phase, Plan, Supply};
const HOME: Location = Location {
    game_vertex: 1,
    level_vertex: 10,
    level: 0,
    position: [0., 0., 0.],
};
const SOURCE: Location = Location {
    game_vertex: 2,
    level_vertex: 20,
    level: 0,
    position: [30., 0., 0.],
};
fn observation() -> Observation {
    Observation {
        current: HOME,
        supply_location: SOURCE,
        supply: Supply::Free,
        representation_ready: true,
        pickup_pending: false,
        path_blocked: false,
        elapsed_ms: 0,
        edge_distance: 0.0,
        interrupted: false,
        alive: true,
    }
}
fn at_source() -> Observation {
    Observation {
        current: SOURCE,
        ..observation()
    }
}
fn plan() -> Plan {
    Plan::new(123, HOME, SOURCE, SOURCE).unwrap()
}
#[test]
fn trip_confirms_actual_ownership_and_resumes_after_interruption() {
    let mut p = plan();
    let walking = p.step(observation());
    assert_eq!(walking.action, Action::Travel(SOURCE));
    let paused = p.step(Observation {
        interrupted: true,
        elapsed_ms: 120_000,
        ..observation()
    });
    assert_eq!(paused.action, Action::Wait);
    assert_eq!(paused.command, walking.command);
    let mut p = Plan::load(&p.save()).unwrap();
    assert_eq!(p.step(observation()), walking);
    assert_eq!(p.step(at_source()).action, Action::Collect);
    assert_eq!(
        p.step(Observation {
            pickup_pending: true,
            elapsed_ms: 100,
            ..at_source()
        })
        .action,
        Action::Wait
    );
    assert_eq!(
        p.step(Observation {
            supply: Supply::Owned,
            ..at_source()
        })
        .action,
        Action::Travel(HOME)
    );
    assert_eq!(
        p.step(Observation {
            supply: Supply::Owned,
            ..observation()
        })
        .phase,
        Phase::Complete
    );
}
#[test]
fn serialized_replay_matches_every_observation_boundary() {
    let observations = [
        observation(),
        Observation {
            elapsed_ms: 1000,
            ..observation()
        },
        Observation {
            interrupted: true,
            ..observation()
        },
        at_source(),
        Observation {
            pickup_pending: true,
            elapsed_ms: 300,
            ..at_source()
        },
        Observation {
            representation_ready: false,
            pickup_pending: true,
            elapsed_ms: 60_000,
            ..at_source()
        },
        Observation {
            supply: Supply::Owned,
            ..at_source()
        },
        Observation {
            supply: Supply::Owned,
            ..observation()
        },
    ];
    let mut original = plan();
    let mut restored = plan();
    for input in observations {
        assert_eq!(original.step(input), restored.step(input));
        restored = Plan::load(&restored.save()).unwrap();
    }
}
#[test]
fn remote_world_facts_do_not_become_npc_knowledge() {
    for supply in [Supply::Missing, Supply::OtherOwner, Supply::Free] {
        let mut p = plan();
        assert_eq!(
            p.step(Observation {
                supply,
                ..observation()
            })
            .action,
            Action::Travel(SOURCE)
        );
        if supply != Supply::Free {
            assert_eq!(
                p.step(Observation {
                    supply,
                    ..at_source()
                })
                .phase,
                Phase::Failed
            );
        }
    }
}
#[test]
fn representation_mismatch_waits_without_starting_or_charging_pickup_timeout() {
    let mut p = plan();
    for _ in 0..3 {
        assert_eq!(
            p.step(Observation {
                representation_ready: false,
                elapsed_ms: 60_000,
                ..at_source()
            })
            .action,
            Action::Wait
        );
    }
    assert_eq!(p.step(at_source()).action, Action::Collect);
    assert_eq!(
        p.step(Observation {
            representation_ready: false,
            pickup_pending: true,
            elapsed_ms: 60_000,
            ..at_source()
        })
        .phase,
        Phase::Collecting
    );
    assert_eq!(
        p.step(Observation {
            pickup_pending: true,
            elapsed_ms: 100,
            ..at_source()
        })
        .action,
        Action::Wait
    );
    assert_eq!(
        p.step(Observation {
            supply: Supply::Owned,
            ..at_source()
        })
        .phase,
        Phase::Returning
    );
}
#[test]
fn displacement_changes_command_so_the_executor_can_retry() {
    let mut p = plan();
    let first = p.step(at_source());
    let displaced = p.step(Observation {
        pickup_pending: true,
        ..observation()
    });
    assert_eq!(displaced.action, Action::Travel(SOURCE));
    let retry = p.step(at_source());
    assert_eq!(retry.action, Action::Collect);
    assert!(retry.command > first.command);
    // An already sent ownership event may complete even after displacement.
    assert_eq!(
        p.step(Observation {
            supply: Supply::Owned,
            ..observation()
        })
        .phase,
        Phase::Complete
    );
}
#[test]
fn pickup_timeout_requires_an_uninterrupted_pending_request() {
    let mut p = plan();
    p.step(at_source());
    p.step(Observation {
        pickup_pending: true,
        elapsed_ms: 4000,
        ..at_source()
    });
    p.step(Observation {
        pickup_pending: true,
        interrupted: true,
        elapsed_ms: 30_000,
        ..at_source()
    });
    assert_eq!(
        p.step(Observation {
            pickup_pending: true,
            elapsed_ms: 120_000,
            ..at_source()
        })
        .phase,
        Phase::Collecting
    );
    assert_eq!(
        p.step(Observation {
            pickup_pending: true,
            elapsed_ms: 1000,
            ..at_source()
        })
        .phase,
        Phase::Failed
    );
}
#[test]
fn stalled_travel_is_bounded_and_timer_survives_reload() {
    let mut p = plan();
    p.step(observation());
    p.step(Observation {
        elapsed_ms: 20_000,
        ..observation()
    });
    let mut p = Plan::load(&p.save()).unwrap();
    assert_eq!(
        p.step(Observation {
            elapsed_ms: 40_000,
            ..observation()
        })
        .phase,
        Phase::Failed
    );
    let mut moving = plan();
    moving.step(observation());
    moving.step(Observation {
        elapsed_ms: 50_000,
        ..observation()
    });
    let progressed = Location {
        position: [1., 0., 0.],
        ..HOME
    };
    assert_eq!(
        moving
            .step(Observation {
                current: progressed,
                elapsed_ms: 20_000,
                ..observation()
            })
            .phase,
        Phase::Outbound
    );
}
#[test]
fn graph_boundary_does_not_prevent_arrival_and_elevated_item_uses_ground_target() {
    let mut p = Plan::new(
        123,
        HOME,
        SOURCE,
        Location {
            position: [30., 2., 0.],
            ..SOURCE
        },
    )
    .unwrap();
    let current = Location {
        game_vertex: 1,
        ..SOURCE
    };
    let item = Location {
        position: [30., 2., 0.],
        ..SOURCE
    };
    assert_eq!(
        p.step(Observation {
            current,
            supply_location: item,
            ..at_source()
        })
        .action,
        Action::Collect
    );
    assert!(Plan::new(1, HOME, Location { level: 1, ..SOURCE }, SOURCE).is_none());
}
#[test]
fn loss_blocked_path_and_death_terminate_without_fabricating_success() {
    for event in [
        Observation {
            path_blocked: true,
            ..observation()
        },
        Observation {
            alive: false,
            ..observation()
        },
    ] {
        let mut p = plan();
        assert_eq!(p.step(event).action, Action::Wait);
        assert_eq!(p.step(observation()).action, Action::Wait);
    }
    let mut p = plan();
    p.step(Observation {
        supply: Supply::Owned,
        ..at_source()
    });
    assert_eq!(p.step(observation()).phase, Phase::Failed);
}
#[test]
fn malformed_snapshots_are_rejected() {
    let snapshot = plan().save();
    assert_eq!(snapshot.len(), Plan::SNAPSHOT_SIZE);
    for length in 0..snapshot.len() {
        assert!(Plan::load(&snapshot[..length]).is_none());
    }
    let mut extra = snapshot.clone();
    extra.push(0);
    assert!(Plan::load(&extra).is_none());
    for offset in [0, 4, 12, 20, 28, 116, 120, 124, 128, 132, 136] {
        let mut invalid = snapshot.clone();
        match offset {
            4 | 12 => invalid[offset..offset + 8].fill(0),
            _ => invalid[offset..offset + 4].fill(255),
        }
        assert!(Plan::load(&invalid).is_none(), "offset {offset}");
    }
}

#[test]
fn combat_end_does_not_charge_the_unobserved_interval_or_prior_displacement() {
    let mut p = plan();
    p.step(Observation {
        current: Location {
            position: [20., 0., 0.],
            ..HOME
        },
        ..observation()
    });
    p.step(Observation {
        interrupted: true,
        ..observation()
    });
    let mut p = Plan::load(&p.save()).unwrap();
    assert_eq!(
        p.step(Observation {
            elapsed_ms: 120_000,
            ..observation()
        })
        .phase,
        Phase::Outbound
    );
    // Normal travel away from the pre-combat closest point remains progress.
    for x in [-1., -2., -3.] {
        assert_eq!(
            p.step(Observation {
                current: Location {
                    position: [x, 0., 0.],
                    ..HOME
                },
                elapsed_ms: 30_000,
                ..observation()
            })
            .phase,
            Phase::Outbound
        );
    }
}
#[test]
fn long_detours_and_offline_edges_count_as_movement() {
    let mut p = plan();
    for x in 0..10 {
        assert_eq!(
            p.step(Observation {
                current: Location {
                    position: [-(x as f32), 0., 0.],
                    ..HOME
                },
                elapsed_ms: 10_000,
                ..observation()
            })
            .phase,
            Phase::Outbound
        );
    }
    let mut p = plan();
    for edge_distance in 1..10 {
        assert_eq!(
            p.step(Observation {
                edge_distance: edge_distance as f32,
                elapsed_ms: 30_000,
                ..observation()
            })
            .phase,
            Phase::Outbound
        );
        p = Plan::load(&p.save()).unwrap();
    }
}
#[test]
fn permanently_unavailable_representation_is_bounded_across_save_and_combat() {
    let wait = Observation {
        representation_ready: false,
        ..at_source()
    };
    let mut p = plan();
    p.step(wait);
    p.step(Observation {
        elapsed_ms: 299_000,
        ..wait
    });
    p.step(Observation {
        interrupted: true,
        ..wait
    });
    let mut p = Plan::load(&p.save()).unwrap();
    assert_eq!(
        p.step(Observation {
            elapsed_ms: 120_000,
            ..wait
        })
        .phase,
        Phase::Collecting
    );
    assert_eq!(
        p.step(Observation {
            elapsed_ms: 1000,
            ..wait
        })
        .phase,
        Phase::Failed
    );
}
#[test]
fn restored_pickup_wait_does_not_charge_combat_or_representation_gap() {
    let pending = Observation {
        pickup_pending: true,
        ..at_source()
    };
    let mut p = plan();
    p.step(at_source());
    p.step(Observation {
        elapsed_ms: 4000,
        ..pending
    });
    p.step(Observation {
        interrupted: true,
        ..pending
    });
    let mut p = Plan::load(&p.save()).unwrap();
    assert_eq!(
        p.step(Observation {
            elapsed_ms: 120_000,
            ..pending
        })
        .phase,
        Phase::Collecting
    );
    p.step(Observation {
        representation_ready: false,
        ..pending
    });
    assert_eq!(
        p.step(Observation {
            elapsed_ms: 120_000,
            ..pending
        })
        .phase,
        Phase::Collecting
    );
    assert_eq!(
        p.step(Observation {
            elapsed_ms: 1000,
            ..pending
        })
        .phase,
        Phase::Failed
    );
}
#[test]
fn elevated_item_is_approached_until_reachable_and_moved_item_is_not_chased() {
    let item = Location {
        position: [30., 2.4, 0.],
        ..SOURCE
    };
    let mut p = Plan::new(123, HOME, SOURCE, item).unwrap();
    assert_eq!(
        p.step(Observation {
            current: Location {
                position: [28.6, 0., 0.],
                ..SOURCE
            },
            supply_location: item,
            ..at_source()
        })
        .action,
        Action::Travel(SOURCE)
    );
    assert_eq!(
        p.step(Observation {
            supply_location: item,
            ..at_source()
        })
        .action,
        Action::Collect
    );
    assert_eq!(
        p.step(Observation {
            supply_location: Location {
                position: [33., 2.4, 0.],
                ..SOURCE
            },
            ..at_source()
        })
        .phase,
        Phase::Failed
    );
}
#[test]
fn invalid_navigation_ids_on_physical_facts_do_not_crash_or_invent_missing_items() {
    let mut p = plan();
    assert_eq!(
        p.step(Observation {
            supply_location: Location {
                level_vertex: u32::MAX,
                ..SOURCE
            },
            ..at_source()
        })
        .action,
        Action::Collect
    );
    let unknown = Observation {
        supply_location: Location {
            level: u32::MAX,
            ..SOURCE
        },
        ..at_source()
    };
    assert_eq!(p.step(unknown).action, Action::Wait);
    assert_eq!(
        p.step(Observation {
            elapsed_ms: 300_000,
            ..unknown
        })
        .phase,
        Phase::Failed
    );
    let mut p = plan();
    assert_eq!(
        p.step(Observation {
            current: Location {
                level: u32::MAX,
                ..HOME
            },
            ..observation()
        })
        .phase,
        Phase::Failed
    );
    assert!(Plan::load(&p.save()).is_some());
}
