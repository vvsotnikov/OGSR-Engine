use crate::activity::{ActivityOutcome, ActivityReport, ActivityState};
use crate::knowledge::Knowledge;
use crate::{Location, Observation};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum GoalKind {
    AssignedItem,
    CarryBandage,
}

#[derive(Clone, Debug, PartialEq)]
pub(super) struct Goal {
    pub kind: GoalKind,
    pub satisfied: bool,
    pub return_retry_ms: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum ActivityRequest {
    Fetch(usize),
    ReturnHome,
}

impl Goal {
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
        if failed && self.satisfied && report.previous == ActivityState::Returning {
            self.return_retry_ms = Knowledge::RETRY_MS;
        }
        let terminal = matches!(
            report.previous,
            ActivityState::Complete | ActivityState::Failed
        );
        let completed_away = report.previous == ActivityState::Complete
            && self.satisfied
            && !observation.interrupted
            && observation.current.spatially_valid()
            && !observation.current.near(home, 3.0);
        (failed && (!self.satisfied || self.return_retry_ms == 0))
            || (terminal && inventory_changed)
            || completed_away
    }

    pub fn select(&self, current: Location, knowledge: &Knowledge) -> Option<ActivityRequest> {
        if !current.spatially_valid() {
            return None;
        }
        if self.satisfied {
            Some(ActivityRequest::ReturnHome)
        } else {
            knowledge
                .nearest_available(current)
                .map(ActivityRequest::Fetch)
        }
    }
}
