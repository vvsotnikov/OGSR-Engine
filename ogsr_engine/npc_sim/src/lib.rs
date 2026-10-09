//! Persistent supply-trip decisions. The host supplies observations and executes
//! commands; this crate never moves an entity or changes an inventory itself.
#![deny(unsafe_op_in_unsafe_fn)]

mod ffi;

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Location {
    pub game_vertex: u32,
    pub level_vertex: u32,
    pub position: [f32; 3],
}

impl Location {
    fn valid(self) -> bool {
        self.game_vertex < u16::MAX.into()
            && self.level_vertex != u32::MAX
            && self.position.iter().all(|x| x.is_finite())
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
    Unknown = 0,
    Available = 1,
    Owned = 2,
    Unavailable = 3,
}

#[derive(Clone, Copy, Debug)]
pub struct Observation {
    pub at_source: bool,
    pub at_home: bool,
    pub supply: Supply,
    pub interrupted: bool,
    pub alive: bool,
    pub execution_failed: bool,
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
}

impl Plan {
    pub fn new(identity: u64, home: Location, source: Location) -> Option<Self> {
        (identity != 0 && home.valid() && source.valid()).then_some(Self {
            identity,
            command: 1,
            home,
            source,
            phase: Phase::Outbound,
            interrupted: false,
        })
    }

    fn transition(&mut self, phase: Phase) {
        if self.phase != phase {
            // Repeated observations do not create new commands. Being displaced
            // before collection can return to travel, with a new command number.
            match self.command.checked_add(1) {
                Some(command) => {
                    self.command = command;
                    self.phase = phase;
                }
                None => self.phase = Phase::Failed,
            }
        }
    }

    pub fn step(&mut self, observation: Observation) -> Decision {
        self.interrupted = observation.interrupted;
        if !observation.alive {
            self.transition(Phase::Dead);
        } else if !matches!(self.phase, Phase::Complete | Phase::Failed | Phase::Dead) {
            if observation.execution_failed
                || (self.phase == Phase::Returning && observation.supply != Supply::Owned)
            {
                self.transition(Phase::Failed);
            } else if observation.supply == Supply::Owned {
                self.transition(Phase::Returning);
                if observation.at_home {
                    self.transition(Phase::Complete);
                }
            } else if !observation.at_source {
                self.transition(Phase::Outbound);
            } else {
                if observation.supply == Supply::Unavailable {
                    self.transition(Phase::Failed);
                } else if observation.supply == Supply::Available {
                    self.transition(Phase::Collecting);
                }
            }
        }
        self.decision()
    }

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

    // Fixed, versioned wire format: no Rust layouts, engine IDs, pointers or
    // padding are persisted. The outer engine save binds identity to its objects.
    pub const SNAPSHOT_SIZE: usize = 4 + 8 + 8 + 20 + 20 + 4 + 4;

    pub fn save(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(Self::SNAPSHOT_SIZE);
        bytes.extend_from_slice(&1u32.to_le_bytes());
        bytes.extend_from_slice(&self.identity.to_le_bytes());
        bytes.extend_from_slice(&self.command.to_le_bytes());
        for location in [self.home, self.source] {
            bytes.extend_from_slice(&location.game_vertex.to_le_bytes());
            bytes.extend_from_slice(&location.level_vertex.to_le_bytes());
            for coordinate in location.position {
                bytes.extend_from_slice(&coordinate.to_le_bytes());
            }
        }
        bytes.extend_from_slice(&(self.phase as u32).to_le_bytes());
        bytes.extend_from_slice(&u32::from(self.interrupted).to_le_bytes());
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
        if u32::from_le_bytes(read(bytes, &mut cursor)) != 1 {
            return None;
        }
        let identity = u64::from_le_bytes(read(bytes, &mut cursor));
        let command = u64::from_le_bytes(read(bytes, &mut cursor));
        let mut location = || Location {
            game_vertex: u32::from_le_bytes(read(bytes, &mut cursor)),
            level_vertex: u32::from_le_bytes(read(bytes, &mut cursor)),
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
        let interrupted = match u32::from_le_bytes(read(bytes, &mut cursor)) {
            0 => false,
            1 => true,
            _ => return None,
        };
        if command == 0 {
            return None;
        }
        let mut plan = Self::new(identity, home, source)?;
        plan.command = command;
        plan.phase = phase;
        plan.interrupted = interrupted;
        Some(plan)
    }
}
