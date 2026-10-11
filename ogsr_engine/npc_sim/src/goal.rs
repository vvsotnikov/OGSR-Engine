use crate::activity::{ActivityOutcome, ActivityReport, ActivityState};
use crate::knowledge::Knowledge;
use crate::{Location, Observation};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum GoalKind {
    AssignedItem,
    CarryBandage,
    Resident,
}

#[derive(Clone, Debug, PartialEq)]
pub(super) struct Goal {
    kind: GoalKind,
    satisfied: bool,
    return_retry_ms: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum ActivityRequest {
    Fetch(usize),
    ReturnHome,
}

impl Goal {
    const RETURN_RETRY_MS: u32 = 60_000;

    pub fn restore(kind: GoalKind, satisfied: bool, return_retry_ms: u32) -> Option<Self> {
        (return_retry_ms <= Self::RETURN_RETRY_MS).then_some(Self {
            kind,
            satisfied,
            return_retry_ms,
        })
    }
    pub fn is_medical(&self) -> bool {
        self.kind != GoalKind::AssignedItem
    }
    pub fn is_resident(&self) -> bool {
        self.kind == GoalKind::Resident
    }
    pub fn enable_camp(&mut self) -> bool {
        if !self.is_medical() {
            return false;
        }
        self.kind = GoalKind::Resident;
        true
    }
    pub fn satisfied(&self) -> bool {
        self.satisfied
    }
    pub fn return_retry_ms(&self) -> u32 {
        self.return_retry_ms
    }
    pub fn elapse(&mut self, elapsed_ms: u32) {
        self.return_retry_ms = self.return_retry_ms.saturating_sub(elapsed_ms);
    }
    pub fn activity_started(&mut self) {
        self.return_retry_ms = 0;
    }

    pub fn new(kind: GoalKind) -> Self {
        Self {
            kind,
            satisfied: false,
            return_retry_ms: 0,
        }
    }

    pub fn observe_inventory(&mut self, bandages: u32) -> bool {
        let satisfied = bandages != 0;
        let changed = satisfied != self.satisfied;
        self.satisfied = satisfied;
        changed
    }

    pub fn reconsider(
        &mut self,
        report: &ActivityReport,
        inventory_changed: bool,
        observation: Observation,
        home: Location,
    ) -> bool {
        let failed = matches!(report.outcome, ActivityOutcome::Failed(_));
        if failed
            && (self.satisfied || self.is_resident())
            && report.previous == ActivityState::Returning
        {
            self.return_retry_ms = Self::RETURN_RETRY_MS;
        }
        // A resident fetch is preempted once its acquired bandage satisfies the goal:
        // cargo ownership and bandage count come from the same inventory snapshot.
        // Starting any new activity clears this timer, so fetch failures do not inherit it.
        if self.is_resident() && failed && self.return_retry_ms != 0 {
            return false;
        }
        let terminal = matches!(
            report.previous,
            ActivityState::Complete | ActivityState::Failed
        );
        let completed_away = report.previous == ActivityState::Complete
            && (self.satisfied || self.is_resident())
            && !observation.interrupted
            && observation.current.spatially_valid()
            && !observation.current.near(home, 3.0);
        (failed && (!self.satisfied || self.return_retry_ms == 0))
            || (terminal && inventory_changed)
            || completed_away
    }

    pub fn preempts(&self, fetching: bool, current: Location, knowledge: &Knowledge) -> bool {
        self.is_resident()
            && ((fetching && self.satisfied)
                || (!fetching
                    && !self.satisfied
                    && current.spatially_valid()
                    && knowledge.nearest_available(current).is_some()))
    }
    pub fn select(&self, current: Location, knowledge: &Knowledge) -> Option<ActivityRequest> {
        if !current.spatially_valid() {
            return None;
        }
        if self.is_resident() {
            if !self.satisfied {
                if let Some(source) = knowledge.nearest_available(current) {
                    return Some(ActivityRequest::Fetch(source));
                }
            }
            (self.return_retry_ms == 0).then_some(ActivityRequest::ReturnHome)
        } else if self.satisfied {
            Some(ActivityRequest::ReturnHome)
        } else {
            knowledge
                .nearest_available(current)
                .map(ActivityRequest::Fetch)
        }
    }
}
