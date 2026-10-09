use crate::{Action, Decision, FailureReason, Location, Observation, Phase, Plan, Supply};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Source {
    pub navigation: Location,
    pub physical: Location,
    // Knowledge changes only after an attempted visit, own pickup, or explicit news.
    pub failure: FailureReason,
    retry_ms: u32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct AgentDecision {
    pub decision: Decision,
    pub source: Option<usize>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Agent {
    identity: u64,
    home: Location,
    medical_goal: bool,
    sources: Vec<Source>,
    selected: Option<usize>,
    trip: Option<Plan>,
    command: u64,
    stocked: bool,
    dead: bool,
    interrupted: bool,
    return_retry_ms: u32,
}

impl Agent {
    pub const MAX_SOURCES: usize = 256;
    const RETRY_MS: u32 = 60_000;
    pub fn medical(identity: u64, home: Location) -> Option<Self> {
        (identity != 0 && home.valid()).then_some(Self {
            identity,
            home,
            medical_goal: true,
            sources: Vec::new(),
            selected: None,
            trip: None,
            command: 1,
            stocked: false,
            dead: false,
            interrupted: false,
            return_retry_ms: 0,
        })
    }
    pub fn assigned(plan: Plan) -> Self {
        Self {
            identity: plan.identity,
            home: plan.home,
            medical_goal: false,
            sources: vec![Source {
                navigation: plan.source,
                physical: plan.remembered_item,
                failure: FailureReason::None,
                retry_ms: 0,
            }],
            selected: Some(0),
            command: plan.command,
            stocked: false,
            dead: false,
            interrupted: false,
            return_retry_ms: 0,
            trip: Some(plan),
        }
    }
    pub fn home(&self) -> Location {
        self.home
    }
    pub fn sources(&self) -> &[Source] {
        &self.sources
    }
    pub fn is_medical(&self) -> bool {
        self.medical_goal
    }
    // The caller supplies new information, not a periodic world-state refresh.
    pub fn remember(&mut self, index: usize, navigation: Location, physical: Location) -> bool {
        if !self.medical_goal
            || index > self.sources.len()
            || index >= Self::MAX_SOURCES
            || !navigation.valid()
            || !physical.spatially_valid()
            || navigation.level != self.home.level
            || physical.level != self.home.level
        {
            return false;
        }
        let source = Source {
            navigation,
            physical,
            failure: FailureReason::None,
            retry_ms: 0,
        };
        let replace_trip = self.selected == Some(index)
            && self
                .trip
                .as_ref()
                .is_some_and(|trip| matches!(trip.phase, Phase::Outbound | Phase::Collecting));
        let command = if replace_trip {
            let Some(command) = self.command.checked_add(1) else {
                return false;
            };
            command
        } else {
            self.command
        };
        if index == self.sources.len() {
            self.sources.push(source);
        } else {
            self.sources[index] = source;
        }
        if replace_trip {
            self.command = command;
            self.trip = None;
            self.selected = None;
        }
        true
    }
    fn start_trip(&mut self, source: Option<usize>, interrupted: bool) -> bool {
        let Some(command) = self.command.checked_add(1) else {
            return false;
        };
        let (navigation, physical) = source
            .map(|i| (self.sources[i].navigation, self.sources[i].physical))
            .unwrap_or((self.home, self.home));
        let mut trip = Plan::new(self.identity, self.home, navigation, physical).unwrap();
        trip.command = command;
        trip.interrupted = interrupted;
        if source.is_none() {
            trip.phase = Phase::Returning;
        }
        self.command = command;
        self.return_retry_ms = 0;
        self.selected = source;
        self.trip = Some(trip);
        true
    }
    pub fn status(&self) -> AgentDecision {
        let decision = if self.dead {
            Decision {
                identity: self.identity,
                command: self.command,
                phase: Phase::Dead,
                reason: FailureReason::None,
                interrupted: false,
                action: Action::Wait,
            }
        } else if let Some(trip) = &self.trip {
            trip.decision()
        } else {
            Decision {
                identity: self.identity,
                command: self.command,
                phase: if self.command == u64::MAX {
                    Phase::Failed
                } else {
                    Phase::Waiting
                },
                reason: if self.command == u64::MAX {
                    FailureReason::CounterExhausted
                } else {
                    FailureReason::None
                },
                interrupted: false,
                action: Action::Wait,
            }
        };
        AgentDecision {
            decision,
            source: self.selected,
        }
    }
    pub fn step(&mut self, o: Observation, bandages: u32) -> AgentDecision {
        if !self.medical_goal {
            let trip = self.trip.as_mut().unwrap();
            let decision = trip.step(o);
            self.command = trip.command;
            return AgentDecision {
                decision,
                source: self.selected,
            };
        }
        if !o.alive {
            self.dead = true;
        }
        if self.dead {
            return self.status();
        }
        let elapsed = if self.interrupted || o.interrupted {
            0
        } else {
            o.elapsed_ms
        };
        self.interrupted = o.interrupted;
        self.return_retry_ms = self.return_retry_ms.saturating_sub(elapsed);
        for source in &mut self.sources {
            source.retry_ms = source.retry_ms.saturating_sub(elapsed);
        }
        let stocked = bandages != 0;
        let inventory_changed = stocked != self.stocked;
        self.stocked = stocked;
        // An invalid current location is not a safe origin for choosing a source.
        // Existing trips retain their bounded unknown-location handling.
        if let Some(trip) = self.trip.as_mut() {
            if let Some(i) = self.selected {
                if o.supply == Supply::Owned {
                    self.sources[i].failure = FailureReason::SupplyUnavailable;
                }
            }
            let terminal = matches!(trip.phase, Phase::Complete | Phase::Failed);
            let pursuing_source = matches!(trip.phase, Phase::Outbound | Phase::Collecting);
            let mut decision = trip.decision();
            if !terminal {
                decision = trip.step_with_goal(o, stocked);
                self.command = trip.command;
            }
            let failed = trip.phase == Phase::Failed;
            if pursuing_source && failed && !stocked && trip.reason != FailureReason::LostSupply {
                if let Some(i) = self.selected {
                    if matches!(
                        trip.reason,
                        FailureReason::SupplyUnavailable | FailureReason::SupplyMoved
                    ) {
                        self.sources[i].failure = trip.reason;
                    } else {
                        self.sources[i].retry_ms = Self::RETRY_MS;
                    }
                }
            }
            if failed && stocked && !terminal {
                self.return_retry_ms = Self::RETRY_MS;
            }
            if (failed && (!stocked || self.return_retry_ms == 0))
                || (terminal && inventory_changed)
            {
                self.trip = None;
                self.selected = None;
            } else {
                return AgentDecision {
                    decision,
                    source: self.selected,
                };
            }
        }
        if !o.current.spatially_valid() {
            return self.status();
        }
        if stocked {
            if self.start_trip(None, o.interrupted) {
                let mut initial = o;
                initial.elapsed_ms = 0;
                initial.path_blocked = false;
                initial.pickup_pending = false;
                let trip = self.trip.as_mut().unwrap();
                trip.step_with_goal(initial, true);
                self.command = trip.command;
            }
        } else {
            let source = self
                .sources
                .iter()
                .enumerate()
                .filter(|(_, s)| s.failure == FailureReason::None && s.retry_ms == 0)
                .min_by(|(a, x), (b, y)| {
                    o.current
                        .distance(x.navigation)
                        .total_cmp(&o.current.distance(y.navigation))
                        .then(a.cmp(b))
                })
                .map(|(i, _)| i);
            if let Some(i) = source {
                self.start_trip(Some(i), o.interrupted);
            }
            // The input describes the previously selected source. Do not apply
            // those facts to a new source until the host observes it next tick.
        }
        self.status()
    }

    pub fn save(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"NPCG");
        put(&mut bytes, 2);
        bytes.extend_from_slice(&self.identity.to_le_bytes());
        bytes.extend_from_slice(&self.command.to_le_bytes());
        put_location(&mut bytes, self.home);
        put(
            &mut bytes,
            u32::from(self.medical_goal)
                | (u32::from(self.stocked) << 1)
                | (u32::from(self.dead) << 2)
                | (u32::from(self.interrupted) << 3),
        );
        put(&mut bytes, self.return_retry_ms);
        put(&mut bytes, self.selected.map_or(u32::MAX, |i| i as u32));
        put(&mut bytes, self.sources.len() as u32);
        for source in &self.sources {
            put_location(&mut bytes, source.navigation);
            put_location(&mut bytes, source.physical);
            put(&mut bytes, source.failure as u32);
            put(&mut bytes, source.retry_ms);
        }
        if let Some(trip) = &self.trip {
            bytes.extend(trip.save());
        }
        bytes
    }
    pub fn load(bytes: &[u8]) -> Option<Self> {
        // Preserve assigned trips written by the first planner release.
        if bytes.len() == Plan::SNAPSHOT_SIZE && bytes.get(..4)? == 4u32.to_le_bytes() {
            return Plan::load(bytes).map(Self::assigned);
        }
        let mut r = Reader(bytes);
        if r.take::<4>()? != *b"NPCG" || r.u32()? != 2 {
            return None;
        }
        let identity = u64::from_le_bytes(r.take()?);
        let command = u64::from_le_bytes(r.take()?);
        let home = r.location()?;
        let mut agent = Self::medical(identity, home)?;
        let flags = r.u32()?;
        let return_retry_ms = r.u32()?;
        let selected = r.u32()?;
        let count = r.u32()? as usize;
        if command == 0
            || flags > 15
            || count > Self::MAX_SOURCES
            || return_retry_ms > Self::RETRY_MS
        {
            return None;
        }
        agent.command = command;
        agent.medical_goal = flags & 1 != 0;
        agent.stocked = flags & 2 != 0;
        agent.dead = flags & 4 != 0;
        agent.interrupted = flags & 8 != 0;
        agent.return_retry_ms = return_retry_ms;
        for _ in 0..count {
            let navigation = r.location()?;
            let physical = r.location()?;
            let failure = match r.u32()? {
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
            let retry_ms = r.u32()?;
            if !navigation.valid()
                || !physical.spatially_valid()
                || navigation.level != home.level
                || physical.level != home.level
                || retry_ms > Self::RETRY_MS
            {
                return None;
            }
            agent.sources.push(Source {
                navigation,
                physical,
                failure,
                retry_ms,
            });
        }
        if selected != u32::MAX {
            if selected as usize >= count {
                return None;
            }
            agent.selected = Some(selected as usize);
        }
        if !r.0.is_empty() {
            let trip = Plan::load(r.0)?;
            if trip.identity != identity || trip.home != home || trip.command != command {
                return None;
            }
            agent.trip = Some(trip);
        }
        if agent.selected.is_some() && agent.trip.is_none() {
            return None;
        }
        if !agent.medical_goal && (count != 1 || agent.selected != Some(0) || agent.trip.is_none())
        {
            return None;
        }
        Some(agent)
    }
}

fn put(bytes: &mut Vec<u8>, value: u32) {
    bytes.extend_from_slice(&value.to_le_bytes());
}
fn put_location(bytes: &mut Vec<u8>, p: Location) {
    for v in [p.game_vertex, p.level_vertex, p.level] {
        put(bytes, v);
    }
    for v in p.position {
        put(bytes, v.to_bits());
    }
}
struct Reader<'a>(&'a [u8]);
impl Reader<'_> {
    fn take<const N: usize>(&mut self) -> Option<[u8; N]> {
        let value = self.0.get(..N)?.try_into().ok()?;
        self.0 = &self.0[N..];
        Some(value)
    }
    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take()?))
    }
    fn location(&mut self) -> Option<Location> {
        Some(Location {
            game_vertex: self.u32()?,
            level_vertex: self.u32()?,
            level: self.u32()?,
            position: [
                f32::from_bits(self.u32()?),
                f32::from_bits(self.u32()?),
                f32::from_bits(self.u32()?),
            ],
        })
    }
}
