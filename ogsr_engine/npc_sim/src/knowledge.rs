use crate::activity::{ActivityOutcome, ActivityReport, ActivityState};
use crate::{FailureReason, Location};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Source {
    pub navigation: Location,
    pub physical: Location,
    // Knowledge changes only after an attempted visit, own pickup, or explicit news.
    pub failure: FailureReason,
    pub(super) retry_ms: u32,
    // Dense ranks keep observation recency bounded without a lifetime counter.
    pub(super) learned_order: u32,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub(super) struct Knowledge {
    pub sources: Vec<Source>,
}

impl Knowledge {
    pub const MAX_SOURCES: usize = 256;
    pub const RETRY_MS: u32 = 60_000;

    pub fn available_slot(&self, selected: Option<usize>) -> Option<usize> {
        if self.sources.len() < Self::MAX_SOURCES {
            return Some(self.sources.len());
        }
        self.sources
            .iter()
            .enumerate()
            .filter(|(i, _)| Some(*i) != selected)
            .min_by_key(|(_, s)| {
                (
                    s.failure == FailureReason::None,
                    s.retry_ms == 0,
                    s.learned_order,
                )
            })
            .map(|(i, _)| i)
    }

    pub fn accepts(
        &self,
        index: usize,
        home: Location,
        navigation: Location,
        physical: Location,
    ) -> bool {
        index <= self.sources.len()
            && index < Self::MAX_SOURCES
            && navigation.valid()
            && physical.spatially_valid()
            && navigation.level == home.level
            && physical.level == home.level
    }

    pub fn remember(&mut self, index: usize, navigation: Location, physical: Location) {
        let mut source = Source {
            navigation,
            physical,
            failure: FailureReason::None,
            retry_ms: 0,
            learned_order: self.sources.len() as u32,
        };
        if index == self.sources.len() {
            self.sources.push(source);
        } else {
            let old_order = self.sources[index].learned_order;
            for existing in &mut self.sources {
                if existing.learned_order > old_order {
                    existing.learned_order -= 1;
                }
            }
            source.learned_order = self.sources.len() as u32 - 1;
            self.sources[index] = source;
        }
    }

    pub fn elapse(&mut self, elapsed_ms: u32) {
        for source in &mut self.sources {
            source.retry_ms = source.retry_ms.saturating_sub(elapsed_ms);
        }
    }

    pub fn acquired(&mut self, selected: Option<usize>) {
        if let Some(i) = selected {
            self.sources[i].failure = FailureReason::SupplyUnavailable;
        }
    }

    pub fn learn(&mut self, selected: Option<usize>, report: &ActivityReport, satisfied: bool) {
        let (Some(i), ActivityOutcome::Failed(reason)) = (selected, report.outcome) else {
            return;
        };
        if report.previous != ActivityState::Fetching
            || satisfied
            || reason == FailureReason::LostSupply
        {
            return;
        }
        if matches!(
            reason,
            FailureReason::SupplyUnavailable | FailureReason::SupplyMoved
        ) {
            self.sources[i].failure = reason;
        } else {
            self.sources[i].retry_ms = Self::RETRY_MS;
        }
    }

    pub fn nearest_available(&self, current: Location) -> Option<usize> {
        self.sources
            .iter()
            .enumerate()
            .filter(|(_, s)| s.failure == FailureReason::None && s.retry_ms == 0)
            .min_by(|(a, x), (b, y)| {
                current
                    .distance(x.navigation)
                    .total_cmp(&current.distance(y.navigation))
                    .then(a.cmp(b))
            })
            .map(|(i, _)| i)
    }
}
