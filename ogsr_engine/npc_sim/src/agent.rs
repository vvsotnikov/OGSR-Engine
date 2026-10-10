use crate::activity::ActivityState;
use crate::goal::{ActivityRequest, Goal, GoalKind};
use crate::knowledge::{Knowledge, Source, SourceKind};
use crate::{
    Action, Decision, FailureReason, Location, Observation, Phase, Plan, ScriptControl, Supply,
};
mod persistence;

#[repr(u32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SourceObservation {
    Rejected = 0,
    Unchanged = 1,
    Updated = 2,
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
    goal: Goal,
    knowledge: Knowledge,
    selected: Option<usize>,
    activity: Option<Plan>,
    command: u64,
    dead: bool,
    interrupted: bool,
    script_suspended: bool,
}

impl Agent {
    pub const MAX_SOURCES: usize = Knowledge::MAX_SOURCES;
    pub fn medical(identity: u64, home: Location) -> Option<Self> {
        (identity != 0 && home.valid()).then_some(Self {
            identity,
            home,
            goal: Goal::new(GoalKind::CarryBandage),
            knowledge: Knowledge::default(),
            selected: None,
            activity: None,
            command: 1,
            dead: false,
            interrupted: false,
            script_suspended: false,
        })
    }
    pub fn assigned(plan: Plan) -> Self {
        let knowledge = Knowledge::from_assigned_trip(&plan);
        Self {
            identity: plan.identity(),
            home: plan.home(),
            goal: Goal::new(GoalKind::AssignedItem),
            knowledge,
            selected: Some(0),
            command: plan.command(),
            dead: false,
            interrupted: false,
            script_suspended: false,
            activity: Some(plan),
        }
    }
    pub fn home(&self) -> Location {
        self.home
    }
    pub fn sources(&self) -> &[Source] {
        self.knowledge.sources()
    }
    pub fn is_medical(&self) -> bool {
        self.goal.is_medical()
    }
    pub fn available_source_slot(&self) -> Option<usize> {
        if !self.is_medical() {
            return None;
        }
        self.knowledge.available_slot(self.selected)
    }
    // The caller supplies new information, not a periodic world-state refresh.
    pub fn remember(&mut self, index: usize, navigation: Location, physical: Location) -> bool {
        if !self.is_medical() {
            return false;
        }
        let replace_activity = self.selected == Some(index)
            && self
                .activity
                .as_ref()
                .is_some_and(|a| a.state() == ActivityState::Fetching);
        let command = if replace_activity {
            let Some(command) = self.command.checked_add(1) else {
                return false;
            };
            command
        } else {
            self.command
        };
        if !self
            .knowledge
            .remember(index, self.home, navigation, physical)
        {
            return false;
        }
        if replace_activity {
            self.command = command;
            self.activity = None;
            self.selected = None;
        }
        true
    }
    pub fn remember_corpse(
        &mut self,
        index: usize,
        navigation: Location,
        physical: Location,
    ) -> bool {
        if !self.remember(index, navigation, physical) {
            return false;
        }
        self.knowledge.set_kind(index, SourceKind::Corpse);
        true
    }

    /// Result of the currently issued search, after a real inventory inspection.
    pub fn searched(&mut self, command: u64, exhausted: bool) -> bool {
        let status = self.status();
        if status.decision.command != command || status.decision.action != Action::Inspect {
            return false;
        }
        let index = self.selected.unwrap();
        self.knowledge.searched(index, exhausted);
        true
    }

    /// A personal sighting of the same bound object, not a replacement identity.
    pub fn observe_source(
        &mut self,
        index: usize,
        navigation: Location,
        physical: Location,
    ) -> SourceObservation {
        if !self.is_medical() || !crate::valid_source(self.home, navigation, physical) {
            return SourceObservation::Rejected;
        }
        if let Some(source) = self.sources().get(index) {
            // Physics settling and repeated visibility must not restart travel or
            // erase a failed route's retry delay. Navigation snapping is not
            // physical movement; navigation changes only with physical news.
            // Recency still follows sightings, independently of trip/retry state.
            // Compare to the stored sighting so cumulative movement becomes news.
            if (source.failure == FailureReason::None
                || (source.kind == SourceKind::Corpse
                    && source.failure == FailureReason::SupplyUnavailable))
                && source
                    .physical
                    .near(physical, crate::SOURCE_MOVEMENT_TOLERANCE)
            {
                self.knowledge.observe_again(index);
                return SourceObservation::Unchanged;
            }
        }
        let kind = self
            .sources()
            .get(index)
            .map(|s| s.kind)
            .unwrap_or(SourceKind::LooseItem);
        let exhausted = self.sources().get(index).is_some_and(|s| {
            s.kind == SourceKind::Corpse && s.failure == FailureReason::SupplyUnavailable
        });
        if self.remember(index, navigation, physical) {
            self.knowledge.set_kind(index, kind);
            if exhausted {
                self.knowledge.searched(index, true);
            }
            SourceObservation::Updated
        } else {
            SourceObservation::Rejected
        }
    }
    fn start_activity(&mut self, request: ActivityRequest, interrupted: bool) -> bool {
        let Some(command) = self.command.checked_add(1) else {
            return false;
        };
        let source = match request {
            ActivityRequest::Fetch(i) => Some(i),
            ActivityRequest::ReturnHome => None,
        };
        let locations = source.map(|i| {
            let s = self.knowledge.sources()[i];
            (s.navigation, s.physical)
        });
        self.activity = Some(Plan::start(
            self.identity,
            command,
            self.home,
            locations,
            interrupted,
        ));
        self.command = command;
        self.goal.activity_started();
        self.selected = source;
        true
    }
    fn result(&self, mut decision: Decision) -> AgentDecision {
        if decision.action == Action::Collect
            && self
                .selected
                .is_some_and(|i| self.sources()[i].kind == SourceKind::Corpse)
        {
            decision.action = Action::Inspect;
        }
        AgentDecision {
            decision,
            source: self.selected,
        }
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
        } else if let Some(activity) = &self.activity {
            activity.decision()
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
        self.result(decision)
    }
    pub fn step_controlled(
        &mut self,
        o: Observation,
        bandages: u32,
        control: ScriptControl,
    ) -> AgentDecision {
        self.report_script_control(control);
        self.step(o, bandages)
    }
    pub fn report_script_control(&mut self, control: ScriptControl) {
        match control {
            ScriptControl::Released => self.script_suspended = false,
            ScriptControl::Owned => self.script_suspended = true,
            ScriptControl::Unobserved => {}
        }
    }
    pub fn step(&mut self, mut o: Observation, bandages: u32) -> AgentDecision {
        o.interrupted |= self.script_suspended;
        if !self.is_medical() {
            let activity = self.activity.as_mut().unwrap();
            let decision = activity.step(o);
            self.command = activity.command();
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
        self.goal.elapse(elapsed);
        self.knowledge.elapse(elapsed);
        let inventory_changed = self.goal.observe_inventory(bandages);
        if self.selected.is_some_and(|i| {
            self.sources()[i].kind == SourceKind::Corpse
                && self.sources()[i].failure == FailureReason::SupplyUnavailable
        }) {
            o.supply = Supply::Missing;
        }
        if let Some(activity) = self.activity.as_mut() {
            if o.supply == Supply::Owned {
                self.knowledge.acquired(self.selected);
            }
            let report = activity.advance(o, self.goal.satisfied());
            self.command = activity.command();
            self.knowledge
                .learn(self.selected, &report, self.goal.satisfied());
            if self
                .goal
                .reconsider(&report, inventory_changed, o, self.home)
            {
                self.activity = None;
                self.selected = None;
            } else {
                return self.result(report.decision);
            }
        }
        if let Some(request) = self.goal.select(o.current, &self.knowledge) {
            if self.start_activity(request, o.interrupted) && request == ActivityRequest::ReturnHome
            {
                let mut initial = o;
                initial.elapsed_ms = 0;
                initial.path_blocked = false;
                initial.pickup_pending = false;
                let activity = self.activity.as_mut().unwrap();
                activity.advance(initial, self.goal.satisfied());
                self.command = activity.command();
            }
            // Source facts belong to the previous selection. Observe a newly
            // selected source next tick before advancing its activity.
        }
        self.status()
    }
}
