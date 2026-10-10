use crate::activity::ActivityState;
use crate::goal::{ActivityRequest, Goal, GoalKind};
use crate::knowledge::{Knowledge, Source};
use crate::{
    Action, Decision, FailureReason, Location, Observation, Phase, Plan, ScriptControl, Supply,
};
mod persistence;

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
        AgentDecision {
            decision,
            source: self.selected,
        }
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
                return AgentDecision {
                    decision: report.decision,
                    source: self.selected,
                };
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
