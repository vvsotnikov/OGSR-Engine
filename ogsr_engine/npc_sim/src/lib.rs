//! Persistent intentions and policy. The host reports facts and executes commands.
#![deny(unsafe_op_in_unsafe_fn)]
mod ffi;

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Location {
    pub game_vertex: u32,
    pub level_vertex: u32,
    pub level: u32,
    pub position: [f32; 3],
}
impl Location {
    fn spatially_valid(self) -> bool {
        self.level < u16::MAX.into() && self.position.iter().all(|x| x.is_finite())
    }
    fn valid(self) -> bool {
        self.game_vertex < u16::MAX.into()
            && self.level_vertex != u32::MAX
            && self.level < u16::MAX.into()
            && self.position.iter().all(|x| x.is_finite())
    }
    fn distance(self, other: Self) -> f32 {
        self.position
            .iter()
            .zip(other.position)
            .map(|(a, b)| (a - b) * (a - b))
            .sum::<f32>()
            .sqrt()
    }
    fn near(self, other: Self, radius: f32) -> bool {
        self.level == other.level && self.distance(other) <= radius
    }
}
#[repr(u32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Outbound = 0,
    Collecting = 1,
    Returning = 2,
    Complete = 3,
    Failed = 4,
    Dead = 5,
}
#[repr(u32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Supply {
    Missing = 0,
    Free = 1,
    Owned = 2,
    OtherOwner = 3,
}
#[derive(Clone, Copy, Debug)]
pub struct Observation {
    pub current: Location,
    pub supply_location: Location,
    pub supply: Supply,
    pub representation_ready: bool,
    pub pickup_pending: bool,
    pub path_blocked: bool,
    pub elapsed_ms: u32,
    pub edge_distance: f32, // Offline distance walked on the current game-graph edge.
    pub interrupted: bool,
    pub alive: bool,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Action {
    Wait,
    Travel(Location),
    Collect,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Decision {
    pub identity: u64,
    pub command: u64,
    pub phase: Phase,
    pub interrupted: bool,
    pub action: Action,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Plan {
    identity: u64,
    command: u64,
    home: Location,
    source: Location,
    phase: Phase,
    interrupted: bool,
    stalled_ms: u32,
    pickup_ms: u32,
    remembered_item: Location,
    progress_anchor: Location,
    edge_distance: f32,
    unavailable_ms: u32,
    representation_ready: bool,
}
const TRAVEL_STALL_MS: u32 = 60_000;
const PICKUP_TIMEOUT_MS: u32 = 5_000;
const UNAVAILABLE_TIMEOUT_MS: u32 = 300_000;
impl Plan {
    pub fn new(
        identity: u64,
        home: Location,
        source: Location,
        remembered_item: Location,
    ) -> Option<Self> {
        (identity != 0
            && home.valid()
            && source.valid()
            && remembered_item.spatially_valid()
            && home.level == source.level
            && source.level == remembered_item.level)
            .then_some(Self {
                identity,
                command: 1,
                home,
                source,
                phase: Phase::Outbound,
                interrupted: false,
                stalled_ms: 0,
                pickup_ms: 0,
                remembered_item,
                progress_anchor: home,
                edge_distance: 0.0,
                unavailable_ms: 0,
                representation_ready: true,
            })
    }
    fn transition(&mut self, phase: Phase) {
        if self.phase != phase {
            if let Some(command) = self.command.checked_add(1) {
                self.command = command;
                self.phase = phase;
            } else {
                self.phase = Phase::Failed;
            }
            self.stalled_ms = 0;
            self.pickup_ms = 0;
            self.unavailable_ms = 0;
        }
    }
    pub fn step(&mut self, mut o: Observation) -> Decision {
        // elapsed_ms describes the interval *before* this observation. Combat
        // may produce only start/end observations, with no ticks in between.
        if !o.edge_distance.is_finite() || o.edge_distance < 0.0 {
            o.edge_distance = 0.0;
        }
        let unknown_item = o.supply == Supply::Free && !o.supply_location.spatially_valid();
        let resumed = self.interrupted && !o.interrupted;
        let elapsed = if self.interrupted || o.interrupted {
            0
        } else {
            o.elapsed_ms
        };
        let pickup_elapsed = if self.representation_ready {
            elapsed
        } else {
            0
        };
        self.interrupted = o.interrupted;
        self.representation_ready = o.representation_ready && !unknown_item;
        if resumed && o.current.spatially_valid() {
            self.stalled_ms = 0;
            self.progress_anchor = o.current;
            self.edge_distance = o.edge_distance;
        }
        let previous_phase = self.phase;
        let terminal = matches!(self.phase, Phase::Complete | Phase::Failed | Phase::Dead);

        if !o.alive {
            self.transition(Phase::Dead);
        } else if !terminal {
            if !o.current.spatially_valid() {
                self.transition(Phase::Failed);
            } else if self.phase == Phase::Returning && o.supply != Supply::Owned {
                self.transition(Phase::Failed);
            } else if o.supply == Supply::Owned {
                self.transition(Phase::Returning);
                if o.current.near(self.home, 1.5) {
                    self.transition(Phase::Complete);
                }
            } else if !o.current.near(self.source, 1.5) {
                self.transition(Phase::Outbound);
            } else if unknown_item {
                self.transition(Phase::Collecting);
            } else if o.supply != Supply::Free || !self.remembered_item.near(o.supply_location, 1.0)
            {
                self.transition(Phase::Failed);
            } else if !o.current.near(o.supply_location, 2.5) {
                // The item is still where remembered, but the NPC must approach
                // the navigation point more closely before it can reach it.
                self.transition(Phase::Outbound);
            } else {
                self.transition(Phase::Collecting);
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
                // Count actual movement in any direction (detours included).
                // Offline positions change only at graph vertices, so also use
                // the engine's distance walked within the current edge.
                let edge_progress = o.edge_distance.is_finite()
                    && self.edge_distance.is_finite()
                    && o.current.game_vertex == self.progress_anchor.game_vertex
                    && o.edge_distance - self.edge_distance >= 0.25;
                if self.phase != previous_phase
                    || o.current.level != self.progress_anchor.level
                    || o.current.distance(self.progress_anchor) >= 0.25
                    || edge_progress
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
                if o.path_blocked || self.stalled_ms >= TRAVEL_STALL_MS {
                    self.transition(Phase::Failed);
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
                        self.transition(Phase::Failed);
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
                            self.transition(Phase::Failed);
                            decision = self.decision();
                        }
                    } else {
                        self.pickup_ms = 0;
                    }
                }
            }
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
            phase: self.phase,
            interrupted: self.interrupted,
            action: if self.interrupted {
                Action::Wait
            } else {
                match self.phase {
                    Phase::Outbound => Action::Travel(self.source),
                    Phase::Collecting => Action::Collect,
                    Phase::Returning => Action::Travel(self.home),
                    _ => Action::Wait,
                }
            },
        }
    }
    pub const SNAPSHOT_SIZE: usize = 140;
    pub fn save(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(Self::SNAPSHOT_SIZE);
        bytes.extend_from_slice(&3u32.to_le_bytes());
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
            u32::from(self.interrupted) | (u32::from(self.representation_ready) << 1),
            self.edge_distance.to_bits(),
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
        if u32::from_le_bytes(read(bytes, &mut cursor)) != 3 {
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
            0 => Phase::Outbound,
            1 => Phase::Collecting,
            2 => Phase::Returning,
            3 => Phase::Complete,
            4 => Phase::Failed,
            5 => Phase::Dead,
            _ => return None,
        };
        let stalled_ms = u32::from_le_bytes(read(bytes, &mut cursor));
        let pickup_ms = u32::from_le_bytes(read(bytes, &mut cursor));
        let unavailable_ms = u32::from_le_bytes(read(bytes, &mut cursor));
        let flags = u32::from_le_bytes(read(bytes, &mut cursor));
        let edge_distance = f32::from_le_bytes(read(bytes, &mut cursor));
        if command == 0
            || stalled_ms > TRAVEL_STALL_MS
            || pickup_ms > PICKUP_TIMEOUT_MS
            || unavailable_ms > UNAVAILABLE_TIMEOUT_MS
            || flags > 3
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
        Some(plan)
    }
}
