use crate::{Action, Decision, FailureReason, Location, Observation, Phase, Plan};

// Camp residence outlives arrival. Travel is shared with supply execution;
// resting never consumes a travel deadline or invents inventory effects.
#[derive(Clone, Debug, PartialEq)]
pub(super) struct Camp {
    travel: Plan,
    resting: bool,
    interrupted: bool,
    retry_ms: u32,
    position_known: bool,
}
impl Camp {
    const RETRY_MS: u32 = 60_000;
    pub fn new(identity: u64, command: u64, home: Location, interrupted: bool) -> Self {
        Self {
            travel: Plan::start(identity, command, home, None, interrupted),
            resting: false,
            interrupted,
            retry_ms: 0,
            position_known: false,
        }
    }
    pub fn identity(&self) -> u64 {
        self.travel.identity()
    }
    pub fn home(&self) -> Location {
        self.travel.home()
    }
    pub fn decision(&self) -> Decision {
        let mut d = self.travel.decision();
        d.interrupted = self.interrupted;
        if self.resting {
            d.phase = Phase::Resting;
            d.action = Action::Rest;
        }
        if self.interrupted || !self.position_known {
            d.action = Action::Wait;
        }
        d
    }
    pub fn step(&mut self, o: Observation, elapsed: u32) -> Decision {
        self.interrupted = o.interrupted;
        self.position_known = o.current.spatially_valid();
        self.retry_ms = self.retry_ms.saturating_sub(elapsed);
        let old = self.travel.decision();
        if !o.interrupted
            && self.position_known
            && ((old.phase == Phase::Complete && !o.current.near(self.home(), 3.0))
                || (old.phase == Phase::Failed
                    && self.retry_ms == 0
                    && old.reason != FailureReason::CounterExhausted))
        {
            if let Some(command) = old.command.checked_add(1) {
                self.travel = Plan::start(self.identity(), command, self.home(), None, false);
                self.resting = false;
            } else {
                self.resting = false;
                self.travel.exhaust_command();
                return self.decision();
            }
        }
        let mut fresh = o;
        // Camp travel is independent of possession of medical supplies.
        fresh.supply = crate::Supply::Owned;
        fresh.elapsed_ms = elapsed.min(o.elapsed_ms);
        if old.command != self.travel.command() {
            fresh.elapsed_ms = 0;
            fresh.path_blocked = false;
        }
        let report = self.travel.advance(fresh, true);
        self.resting = report.decision.phase == Phase::Complete;
        if old.phase != Phase::Failed && report.decision.phase == Phase::Failed {
            self.retry_ms = Self::RETRY_MS;
        }
        self.decision()
    }
    pub fn save(&self) -> Vec<u8> {
        let mut b = self.travel.save();
        b.extend_from_slice(
            &(u32::from(self.resting)
                | (u32::from(self.interrupted) << 1)
                | (u32::from(self.position_known) << 2))
                .to_le_bytes(),
        );
        b.extend_from_slice(&self.retry_ms.to_le_bytes());
        b
    }
    pub fn load(b: &[u8]) -> Option<Self> {
        if b.len() != Plan::SNAPSHOT_SIZE + 8 {
            return None;
        }
        let travel = Plan::load(&b[..Plan::SNAPSHOT_SIZE])?;
        let flags = u32::from_le_bytes(
            b[Plan::SNAPSHOT_SIZE..Plan::SNAPSHOT_SIZE + 4]
                .try_into()
                .ok()?,
        );
        let retry_ms = u32::from_le_bytes(b[Plan::SNAPSHOT_SIZE + 4..].try_into().ok()?);
        if flags > 7
            || retry_ms > Self::RETRY_MS
            || !matches!(
                travel.decision().phase,
                Phase::Returning | Phase::Complete | Phase::Failed
            )
            || (flags & 1 != 0) != (travel.decision().phase == Phase::Complete)
        {
            return None;
        }
        Some(Self {
            travel,
            resting: flags & 1 != 0,
            interrupted: flags & 2 != 0,
            position_known: flags & 4 != 0,
            retry_ms,
        })
    }
}
