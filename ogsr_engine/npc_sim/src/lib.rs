//! Persistent intentions and policy. The host reports facts and executes commands.
#![deny(unsafe_op_in_unsafe_fn)]
mod activity;
mod agent;
mod ffi;
mod goal;
mod knowledge;
pub use activity::Plan;
pub use agent::{Agent, AgentDecision};
pub use knowledge::Source;

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
    Waiting = 6,
}
#[repr(u32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FailureReason {
    None = 0,
    SupplyUnavailable = 1,
    SupplyMoved = 2,
    LostSupply = 3,
    TravelStalled = 4,
    PickupTimedOut = 5,
    RepresentationUnavailable = 6,
    PositionUnknown = 7,
    TripDeadline = 8,
    CounterExhausted = 9,
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
    pub reason: FailureReason,
    pub interrupted: bool,
    pub action: Action,
}

fn valid_source(home: Location, navigation: Location, physical: Location) -> bool {
    navigation.valid()
        && physical.spatially_valid()
        && navigation.level == home.level
        && physical.level == home.level
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScriptControl {
    Unobserved = 0,
    Released = 1,
    Owned = 2,
}
