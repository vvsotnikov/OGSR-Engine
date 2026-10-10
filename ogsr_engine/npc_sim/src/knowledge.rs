use crate::activity::{ActivityOutcome, ActivityReport, ActivityState};
use crate::{valid_source, FailureReason, Location, Plan};

#[repr(u32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SourceKind {
    LooseItem = 0,
    Corpse = 1,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Source {
    pub kind: SourceKind,
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
    sources: Vec<Source>,
}

impl Knowledge {
    pub const MAX_SOURCES: usize = 256;
    const SOURCE_RETRY_MS: u32 = 60_000;

    pub fn from_assigned_trip(trip: &Plan) -> Self {
        // Plan's private state can only originate from its validated constructor
        // or loader; this preserves that source without a second admission rule.
        let (navigation, physical) = trip.source();
        Self {
            sources: vec![Source::new(navigation, physical, 0)],
        }
    }

    pub fn sources(&self) -> &[Source] {
        &self.sources
    }

    pub fn restore(home: Location, sources: Vec<Source>) -> Option<Self> {
        if sources.len() > Self::MAX_SOURCES {
            return None;
        }
        let mut ranks = [false; Self::MAX_SOURCES];
        for source in &sources {
            let rank = source.learned_order as usize;
            if rank >= sources.len()
                || ranks[rank]
                || !valid_source(home, source.navigation, source.physical)
                || source.retry_ms > Self::SOURCE_RETRY_MS
            {
                return None;
            }
            ranks[rank] = true;
        }
        Some(Self { sources })
    }

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

    fn accepts(
        &self,
        index: usize,
        home: Location,
        navigation: Location,
        physical: Location,
    ) -> bool {
        index <= self.sources.len()
            && index < Self::MAX_SOURCES
            && valid_source(home, navigation, physical)
    }

    pub fn remember(
        &mut self,
        index: usize,
        home: Location,
        navigation: Location,
        physical: Location,
    ) -> bool {
        if !self.accepts(index, home, navigation, physical) {
            return false;
        }
        let mut source = Source::new(navigation, physical, self.sources.len() as u32);
        if index == self.sources.len() {
            self.sources.push(source);
        } else {
            self.observe_again(index);
            source.learned_order = self.sources[index].learned_order;
            self.sources[index] = source;
        }
        true
    }

    pub fn set_kind(&mut self, index: usize, kind: SourceKind) {
        self.sources[index].kind = kind;
    }

    pub fn searched(&mut self, index: usize, exhausted: bool) {
        if exhausted {
            self.sources[index].failure = FailureReason::SupplyUnavailable;
        }
    }

    pub(super) fn observe_again(&mut self, index: usize) {
        let newest = self.sources.len() as u32 - 1;
        let old_order = self.sources[index].learned_order;
        if old_order == newest {
            return;
        }
        for existing in &mut self.sources {
            if existing.learned_order > old_order {
                existing.learned_order -= 1;
            }
        }
        self.sources[index].learned_order = newest;
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
            self.sources[i].retry_ms = Self::SOURCE_RETRY_MS;
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

impl Source {
    fn new(navigation: Location, physical: Location, learned_order: u32) -> Self {
        Self {
            kind: SourceKind::LooseItem,
            navigation,
            physical,
            learned_order,
            failure: FailureReason::None,
            retry_ms: 0,
        }
    }
}
