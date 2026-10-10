use crate::{valid_source, Action, Decision, FailureReason, Location, Observation, Phase, Supply};

#[derive(Clone, Debug, PartialEq)]
pub struct Plan {
    identity: u64,
    command: u64,
    home: Location,
    source: Location,
    phase: TripPhase,
    interrupted: bool,
    stalled_ms: u32,
    pickup_ms: u32,
    remembered_item: Location,
    progress_anchor: Location,
    edge_distance: f32,
    unavailable_ms: u32,
    representation_ready: bool,
    location_valid: bool,
    active_ms: u32,
    reason: FailureReason,
}
const TRAVEL_STALL_MS: u32 = 60_000;
const PICKUP_TIMEOUT_MS: u32 = 5_000;
const UNAVAILABLE_TIMEOUT_MS: u32 = 300_000;
const TRIP_DEADLINE_MS: u32 = 1_800_000;
impl Plan {
    pub fn new(
        identity: u64,
        home: Location,
        source: Location,
        remembered_item: Location,
    ) -> Option<Self> {
        (identity != 0 && home.valid() && valid_source(home, source, remembered_item)).then_some(
            Self {
                identity,
                command: 1,
                home,
                source,
                phase: TripPhase::Outbound,
                interrupted: false,
                stalled_ms: 0,
                pickup_ms: 0,
                remembered_item,
                progress_anchor: home,
                edge_distance: 0.0,
                unavailable_ms: 0,
                representation_ready: true,
                location_valid: true,
                active_ms: 0,
                reason: FailureReason::None,
            },
        )
    }
    fn transition(&mut self, phase: TripPhase) {
        if self.phase != phase {
            if let Some(command) = self.command.checked_add(1) {
                self.command = command;
                self.phase = phase;
            } else {
                self.phase = TripPhase::Failed;
                self.reason = FailureReason::CounterExhausted;
            }
            if self.phase != TripPhase::Failed {
                self.reason = FailureReason::None;
            }
            self.stalled_ms = 0;
            self.pickup_ms = 0;
            self.unavailable_ms = 0;
        }
    }
    fn fail(&mut self, reason: FailureReason) {
        self.transition(TripPhase::Failed);
        self.reason = reason;
    }
    pub fn step(&mut self, o: Observation) -> Decision {
        self.step_with_goal(o, o.supply == Supply::Owned)
    }
    fn step_with_goal(&mut self, mut o: Observation, satisfied: bool) -> Decision {
        // elapsed_ms describes the interval *before* this observation. Combat
        // may produce only start/end observations, with no ticks in between.
        if !o.edge_distance.is_finite() || o.edge_distance < 0.0 {
            o.edge_distance = 0.0;
        }
        let unknown_item = o.supply == Supply::Free && !o.supply_location.spatially_valid();
        let current_valid = o.current.spatially_valid();
        let was_valid = self.location_valid;
        let resumed =
            (self.interrupted && !o.interrupted) || (!self.location_valid && current_valid);
        let elapsed = if self.interrupted || o.interrupted || (!was_valid && current_valid) {
            0
        } else {
            o.elapsed_ms
        };
        let pickup_elapsed = if self.representation_ready {
            elapsed
        } else {
            0
        };
        self.location_valid = current_valid;
        self.interrupted = o.interrupted;
        self.representation_ready = o.representation_ready && !unknown_item && current_valid;
        if resumed && o.current.spatially_valid() {
            self.stalled_ms = 0;
            self.progress_anchor = o.current;
            self.edge_distance = o.edge_distance;
        }
        let previous_phase = self.phase;
        let terminal = matches!(
            self.phase,
            TripPhase::Complete | TripPhase::Failed | TripPhase::Dead
        );

        if !o.alive {
            self.transition(TripPhase::Dead);
        } else if !terminal {
            self.active_ms = self.active_ms.saturating_add(elapsed).min(TRIP_DEADLINE_MS);
            if self.active_ms >= TRIP_DEADLINE_MS {
                self.fail(FailureReason::TripDeadline);
                return self.decision();
            }
            if !current_valid {
                let unknown_elapsed = if was_valid { 0 } else { elapsed };
                self.unavailable_ms = self
                    .unavailable_ms
                    .saturating_add(unknown_elapsed)
                    .min(UNAVAILABLE_TIMEOUT_MS);
                if self.unavailable_ms >= UNAVAILABLE_TIMEOUT_MS {
                    self.fail(FailureReason::PositionUnknown);
                }
                let mut decision = self.decision();
                decision.action = Action::Wait;
                return decision;
            } else if self.phase == TripPhase::Returning && !satisfied {
                self.fail(FailureReason::LostSupply);
            } else if satisfied {
                self.transition(TripPhase::Returning);
                if o.current.near(self.home, 1.5) {
                    self.transition(TripPhase::Complete);
                }
            } else if !o.current.near(self.source, 1.5) {
                self.transition(TripPhase::Outbound);
            } else if unknown_item {
                self.transition(TripPhase::Collecting);
            } else if o.supply != Supply::Free {
                self.fail(FailureReason::SupplyUnavailable);
            } else if !self
                .remembered_item
                .near(o.supply_location, crate::SOURCE_MOVEMENT_TOLERANCE)
            {
                self.fail(FailureReason::SupplyMoved);
            } else if !o.current.near(o.supply_location, 2.5) {
                // The item is still where remembered, but the NPC must approach
                // the navigation point more closely before it can reach it.
                self.transition(TripPhase::Outbound);
            } else {
                self.transition(TripPhase::Collecting);
            }
        }
        let mut decision = self.decision();
        if o.interrupted {
            return decision;
        }
        let elapsed = if self.phase == previous_phase {
            elapsed
        } else {
            0
        };
        match decision.action {
            Action::Travel(_) => {
                self.unavailable_ms = 0;
                // Count actual movement in any direction (detours included).
                // Offline positions change only at graph vertices, so also use
                // the engine's distance walked within the current edge.
                let edge_progress = o.edge_distance.is_finite()
                    && self.edge_distance.is_finite()
                    && o.current.game_vertex == self.progress_anchor.game_vertex
                    && o.edge_distance - self.edge_distance >= 0.25;
                if !o.path_blocked
                    && (self.phase != previous_phase
                        || o.current.level != self.progress_anchor.level
                        || o.current.distance(self.progress_anchor) >= 0.25
                        || edge_progress)
                {
                    self.progress_anchor = o.current;
                    self.edge_distance = o.edge_distance;
                    self.stalled_ms = 0;
                } else {
                    if o.edge_distance < self.edge_distance {
                        self.edge_distance = o.edge_distance;
                    }
                    self.stalled_ms = self.stalled_ms.saturating_add(elapsed).min(TRAVEL_STALL_MS);
                }
                if self.stalled_ms >= TRAVEL_STALL_MS {
                    self.fail(FailureReason::TravelStalled);
                    decision = self.decision();
                }
            }
            Action::Collect => {
                if !o.representation_ready || unknown_item {
                    self.unavailable_ms = self
                        .unavailable_ms
                        .saturating_add(elapsed)
                        .min(UNAVAILABLE_TIMEOUT_MS);
                    decision.action = Action::Wait;
                    if self.unavailable_ms >= UNAVAILABLE_TIMEOUT_MS {
                        self.fail(FailureReason::RepresentationUnavailable);
                        decision = self.decision();
                    }
                } else {
                    self.unavailable_ms = 0;
                    if o.pickup_pending {
                        self.pickup_ms = self
                            .pickup_ms
                            .saturating_add(pickup_elapsed)
                            .min(PICKUP_TIMEOUT_MS);
                        decision.action = Action::Wait;
                        if self.pickup_ms >= PICKUP_TIMEOUT_MS {
                            self.fail(FailureReason::PickupTimedOut);
                            decision = self.decision();
                        }
                    } else {
                        self.pickup_ms = 0;
                    }
                }
            }
            Action::Inspect => unreachable!("Only Agent translates a collection into inspection"),
            Action::Wait => {}
        }
        decision
    }
    // Status is not an executable command. Only step() incorporates the current
    // representation, pending request and clock observations into its action.
    pub fn decision(&self) -> Decision {
        Decision {
            identity: self.identity,
            command: self.command,
            phase: self.phase.into(),
            reason: self.reason,
            interrupted: self.interrupted,
            action: if self.interrupted {
                Action::Wait
            } else {
                match self.phase {
                    TripPhase::Outbound => Action::Travel(self.source),
                    TripPhase::Collecting => Action::Collect,
                    TripPhase::Returning => Action::Travel(self.home),
                    _ => Action::Wait,
                }
            },
        }
    }
    pub const SNAPSHOT_SIZE: usize = 148;
    pub fn save(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(Self::SNAPSHOT_SIZE);
        bytes.extend_from_slice(&4u32.to_le_bytes());
        bytes.extend_from_slice(&self.identity.to_le_bytes());
        bytes.extend_from_slice(&self.command.to_le_bytes());
        for location in [
            self.home,
            self.source,
            self.remembered_item,
            self.progress_anchor,
        ] {
            for value in [location.game_vertex, location.level_vertex, location.level] {
                bytes.extend_from_slice(&value.to_le_bytes());
            }
            for value in location.position {
                bytes.extend_from_slice(&value.to_le_bytes());
            }
        }
        for value in [
            self.phase as u32,
            self.stalled_ms,
            self.pickup_ms,
            self.unavailable_ms,
            u32::from(self.interrupted)
                | (u32::from(self.representation_ready) << 1)
                | (u32::from(self.location_valid) << 2),
            self.edge_distance.to_bits(),
            self.active_ms,
            self.reason as u32,
        ] {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        bytes
    }
    pub fn load(bytes: &[u8]) -> Option<Self> {
        if bytes.len() != Self::SNAPSHOT_SIZE {
            return None;
        }
        let mut cursor = 0;
        fn read<const N: usize>(bytes: &[u8], cursor: &mut usize) -> [u8; N] {
            let value = bytes[*cursor..*cursor + N].try_into().unwrap();
            *cursor += N;
            value
        }
        if u32::from_le_bytes(read(bytes, &mut cursor)) != 4 {
            return None;
        }
        let identity = u64::from_le_bytes(read(bytes, &mut cursor));
        let command = u64::from_le_bytes(read(bytes, &mut cursor));
        let mut location = || Location {
            game_vertex: u32::from_le_bytes(read(bytes, &mut cursor)),
            level_vertex: u32::from_le_bytes(read(bytes, &mut cursor)),
            level: u32::from_le_bytes(read(bytes, &mut cursor)),
            position: std::array::from_fn(|_| f32::from_le_bytes(read(bytes, &mut cursor))),
        };
        let home = location();
        let source = location();
        let remembered_item = location();
        let progress_anchor = location();
        let phase = match u32::from_le_bytes(read(bytes, &mut cursor)) {
            0 => TripPhase::Outbound,
            1 => TripPhase::Collecting,
            2 => TripPhase::Returning,
            3 => TripPhase::Complete,
            4 => TripPhase::Failed,
            5 => TripPhase::Dead,
            _ => return None,
        };
        let stalled_ms = u32::from_le_bytes(read(bytes, &mut cursor));
        let pickup_ms = u32::from_le_bytes(read(bytes, &mut cursor));
        let unavailable_ms = u32::from_le_bytes(read(bytes, &mut cursor));
        let flags = u32::from_le_bytes(read(bytes, &mut cursor));
        let edge_distance = f32::from_le_bytes(read(bytes, &mut cursor));
        let active_ms = u32::from_le_bytes(read(bytes, &mut cursor));
        let reason = match u32::from_le_bytes(read(bytes, &mut cursor)) {
            0 => FailureReason::None,
            1 => FailureReason::SupplyUnavailable,
            2 => FailureReason::SupplyMoved,
            3 => FailureReason::LostSupply,
            4 => FailureReason::TravelStalled,
            5 => FailureReason::PickupTimedOut,
            6 => FailureReason::RepresentationUnavailable,
            7 => FailureReason::PositionUnknown,
            8 => FailureReason::TripDeadline,
            9 => FailureReason::CounterExhausted,
            _ => return None,
        };
        if command == 0
            || stalled_ms > TRAVEL_STALL_MS
            || pickup_ms > PICKUP_TIMEOUT_MS
            || unavailable_ms > UNAVAILABLE_TIMEOUT_MS
            || flags > 7
            || active_ms > TRIP_DEADLINE_MS
            || (phase == TripPhase::Failed) != (reason != FailureReason::None)
            || !progress_anchor.spatially_valid()
            || !edge_distance.is_finite()
            || edge_distance < 0.0
        {
            return None;
        }
        let mut plan = Self::new(identity, home, source, remembered_item)?;
        plan.command = command;
        plan.phase = phase;
        plan.stalled_ms = stalled_ms;
        plan.pickup_ms = pickup_ms;
        plan.unavailable_ms = unavailable_ms;
        plan.interrupted = flags & 1 != 0;
        plan.representation_ready = flags & 2 != 0;
        plan.progress_anchor = progress_anchor;
        plan.edge_distance = edge_distance;
        plan.location_valid = flags & 4 != 0;
        plan.active_ms = active_ms;
        plan.reason = reason;
        Some(plan)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum ActivityState {
    Fetching,
    Returning,
    Complete,
    Failed,
    Dead,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum ActivityOutcome {
    Running,
    Complete,
    Failed(FailureReason),
    Dead,
}

// This is a supply-trip report, not a general-purpose activity protocol.
// Keep the prior state: a new return failure arms a cooldown, whereas later
// reports of that same terminal failure must not restart it.
#[derive(Debug)]
pub(super) struct ActivityReport {
    pub previous: ActivityState,
    pub outcome: ActivityOutcome,
    pub decision: Decision,
}

impl Plan {
    pub(super) fn start(
        identity: u64,
        command: u64,
        home: Location,
        source: Option<(Location, Location)>,
        interrupted: bool,
    ) -> Self {
        let (navigation, physical) = source.unwrap_or((home, home));
        let mut activity = Self::new(identity, home, navigation, physical).unwrap();
        activity.command = command;
        activity.interrupted = interrupted;
        if source.is_none() {
            activity.phase = TripPhase::Returning;
        }
        activity
    }

    pub(super) fn command(&self) -> u64 {
        self.command
    }

    pub(super) fn identity(&self) -> u64 {
        self.identity
    }
    pub(super) fn home(&self) -> Location {
        self.home
    }
    pub(super) fn source(&self) -> (Location, Location) {
        (self.source, self.remembered_item)
    }

    pub(super) fn state(&self) -> ActivityState {
        match self.phase {
            TripPhase::Outbound | TripPhase::Collecting => ActivityState::Fetching,
            TripPhase::Returning => ActivityState::Returning,
            TripPhase::Complete => ActivityState::Complete,
            TripPhase::Failed => ActivityState::Failed,
            TripPhase::Dead => ActivityState::Dead,
        }
    }

    pub(super) fn advance(&mut self, observation: Observation, satisfied: bool) -> ActivityReport {
        let previous = self.state();
        let decision = match previous {
            ActivityState::Complete | ActivityState::Failed => self.decision(),
            _ => self.step_with_goal(observation, satisfied),
        };
        let outcome = match self.state() {
            ActivityState::Complete => ActivityOutcome::Complete,
            ActivityState::Failed => ActivityOutcome::Failed(self.reason),
            ActivityState::Dead => ActivityOutcome::Dead,
            _ => ActivityOutcome::Running,
        };
        ActivityReport {
            previous,
            outcome,
            decision,
        }
    }
}

// Waiting is an agent state with no activity, never a state of a supply trip.
#[repr(u32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TripPhase {
    Outbound = 0,
    Collecting = 1,
    Returning = 2,
    Complete = 3,
    Failed = 4,
    Dead = 5,
}
impl From<TripPhase> for Phase {
    fn from(value: TripPhase) -> Self {
        match value {
            TripPhase::Outbound => Self::Outbound,
            TripPhase::Collecting => Self::Collecting,
            TripPhase::Returning => Self::Returning,
            TripPhase::Complete => Self::Complete,
            TripPhase::Failed => Self::Failed,
            TripPhase::Dead => Self::Dead,
        }
    }
}
