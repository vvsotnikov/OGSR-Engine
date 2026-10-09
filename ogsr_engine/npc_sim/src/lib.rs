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
    best_distance: f32,
}
const TRAVEL_STALL_MS: u32 = 60_000;
const PICKUP_TIMEOUT_MS: u32 = 5_000;
impl Plan {
    pub fn new(identity: u64, home: Location, source: Location) -> Option<Self> {
        (identity != 0 && home.valid() && source.valid() && home.level == source.level).then_some(
            Self {
                identity,
                command: 1,
                home,
                source,
                phase: Phase::Outbound,
                interrupted: false,
                stalled_ms: 0,
                pickup_ms: 0,
                best_distance: f32::MAX,
            },
        )
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
            self.best_distance = f32::MAX;
        }
    }
    pub fn step(&mut self, observation: Observation) -> Decision {
        let o = observation;
        self.interrupted = o.interrupted;
        if !o.alive {
            self.transition(Phase::Dead);
        } else if !matches!(self.phase, Phase::Complete | Phase::Failed | Phase::Dead) {
            // Own inventory is always knowable. Remote supply facts are consumed
            // only at the remembered destination, never to chase an unseen item.
            if self.phase == Phase::Returning && o.supply != Supply::Owned {
                self.transition(Phase::Failed);
            } else if o.supply == Supply::Owned {
                self.transition(Phase::Returning);
                if o.current.near(self.home, 1.5) {
                    self.transition(Phase::Complete);
                }
            } else if !o.current.near(self.source, 1.5) {
                self.transition(Phase::Outbound);
            } else if o.supply != Supply::Free || !o.current.near(o.supply_location, 2.5) {
                self.transition(Phase::Failed);
            } else {
                self.transition(Phase::Collecting);
            }
        }
        let mut decision = self.decision();
        if o.interrupted {
            return decision;
        }
        match decision.action {
            Action::Travel(target) => {
                let distance = o.current.distance(target);
                if distance + 0.25 < self.best_distance {
                    self.best_distance = distance;
                    self.stalled_ms = 0;
                } else {
                    self.stalled_ms = self
                        .stalled_ms
                        .saturating_add(o.elapsed_ms)
                        .min(TRAVEL_STALL_MS);
                }
                if o.path_blocked || self.stalled_ms >= TRAVEL_STALL_MS {
                    self.transition(Phase::Failed);
                    decision = self.decision();
                }
            }
            Action::Collect => {
                if !o.representation_ready {
                    decision.action = Action::Wait;
                } else if o.pickup_pending {
                    self.pickup_ms = self
                        .pickup_ms
                        .saturating_add(o.elapsed_ms)
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
    pub const SNAPSHOT_SIZE: usize = 84;
    pub fn save(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(Self::SNAPSHOT_SIZE);
        bytes.extend_from_slice(&2u32.to_le_bytes());
        bytes.extend_from_slice(&self.identity.to_le_bytes());
        bytes.extend_from_slice(&self.command.to_le_bytes());
        for location in [self.home, self.source] {
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
            self.best_distance.to_bits(),
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
        if u32::from_le_bytes(read(bytes, &mut cursor)) != 2 {
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
        let best_distance = f32::from_le_bytes(read(bytes, &mut cursor));
        if command == 0
            || stalled_ms > TRAVEL_STALL_MS
            || pickup_ms > PICKUP_TIMEOUT_MS
            || !best_distance.is_finite()
            || best_distance < 0.0
        {
            return None;
        }
        let mut plan = Self::new(identity, home, source)?;
        plan.command = command;
        plan.phase = phase;
        plan.stalled_ms = stalled_ms;
        plan.pickup_ms = pickup_ms;
        plan.best_distance = best_distance;
        Some(plan)
    }
}
