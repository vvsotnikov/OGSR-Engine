use super::*;

impl Agent {
    pub fn save(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"NPCG");
        put(&mut bytes, 6);
        bytes.extend_from_slice(&self.identity.to_le_bytes());
        bytes.extend_from_slice(&self.command.to_le_bytes());
        put_location(&mut bytes, self.home);
        put(
            &mut bytes,
            u32::from(self.is_medical())
                | (u32::from(self.goal.satisfied()) << 1)
                | (u32::from(self.dead) << 2)
                | (u32::from(self.interrupted) << 3)
                | (u32::from(self.script_suspended) << 4),
        );
        put(&mut bytes, self.goal.return_retry_ms());
        put(&mut bytes, self.selected.map_or(u32::MAX, |i| i as u32));
        put(&mut bytes, self.knowledge.sources().len() as u32);
        for source in self.knowledge.sources() {
            put_location(&mut bytes, source.navigation);
            put_location(&mut bytes, source.physical);
            put(&mut bytes, source.failure as u32);
            put(&mut bytes, source.retry_ms);
            put(&mut bytes, source.learned_order);
            put(&mut bytes, source.kind as u32);
            put(&mut bytes, source.rejection_delay_ms);
        }
        if let Some(trip) = &self.activity {
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
        if r.take::<4>()? != *b"NPCG" {
            return None;
        }
        let version = r.u32()?;
        if !(2..=6).contains(&version) {
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
        if command == 0 || flags > if version >= 4 { 31 } else { 15 } || count > Self::MAX_SOURCES {
            return None;
        }
        agent.command = command;
        let kind = if flags & 1 != 0 {
            GoalKind::CarryBandage
        } else {
            GoalKind::AssignedItem
        };
        agent.goal = Goal::restore(kind, flags & 2 != 0, return_retry_ms)?;
        agent.dead = flags & 4 != 0;
        agent.interrupted = flags & 8 != 0;
        agent.script_suspended = flags & 16 != 0;
        let mut sources = Vec::with_capacity(count);
        for index in 0..count {
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
            let learned_order = if version >= 3 { r.u32()? } else { index as u32 };
            let kind = if version >= 5 {
                match r.u32()? {
                    0 => SourceKind::LooseItem,
                    1 => SourceKind::Corpse,
                    _ => return None,
                }
            } else {
                SourceKind::LooseItem
            };
            let rejection_delay_ms = if version >= 6 { r.u32()? } else { 0 };
            sources.push(Source {
                kind,
                navigation,
                physical,
                failure,
                retry_ms,
                rejection_delay_ms,
                learned_order,
            });
        }
        agent.knowledge = Knowledge::restore(home, sources)?;
        if selected != u32::MAX {
            if selected as usize >= count {
                return None;
            }
            agent.selected = Some(selected as usize);
        }
        if !r.0.is_empty() {
            let trip = Plan::load(r.0)?;
            if trip.identity() != identity || trip.home() != home || trip.command() != command {
                return None;
            }
            agent.activity = Some(trip);
        }
        if agent.selected.is_some() && agent.activity.is_none() {
            return None;
        }
        if !agent.is_medical()
            && (count != 1
                || agent.sources()[0].kind != SourceKind::LooseItem
                || agent.selected != Some(0)
                || agent.activity.is_none())
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
