use crate::{
    Action, Agent, AgentDecision, Location, Observation, Phase, Plan, ScriptControl, Supply,
};

#[repr(C)]
pub struct Input {
    current: Location,
    supply_location: Location,
    supply: u32,
    representation_ready: u32,
    pickup_pending: u32,
    path_blocked: u32,
    elapsed_ms: u32,
    edge_distance: f32,
    interrupted: u32,
    alive: u32,
    bandages: u32,
}

#[repr(C)]
#[derive(Default)]
pub struct Output {
    identity: u64,
    command: u64,
    phase: u32,
    interrupted: u32,
    action: u32,
    reason: u32,
    game_vertex: u32,
    level_vertex: u32,
    level: u32,
    position: [f32; 3],
    source: u32,
}

impl From<AgentDecision> for Output {
    fn from(value: AgentDecision) -> Self {
        let decision = value.decision;
        let mut output = Self {
            identity: decision.identity,
            command: decision.command,
            phase: decision.phase as u32,
            reason: decision.reason as u32,
            interrupted: u32::from(decision.interrupted),
            source: value.source.map_or(u32::MAX, |i| i as u32),
            ..Self::default()
        };
        match decision.action {
            Action::Wait => {}
            Action::Collect => output.action = 2,
            Action::Travel(location) => {
                output.action = 1;
                output.game_vertex = location.game_vertex;
                output.level_vertex = location.level_vertex;
                output.level = location.level;
                output.position = location.position;
            }
        }
        output
    }
}

// C ABI contract: pointers refer to valid, appropriately aligned host buffers;
// a plan has one owner and calls on it must be serialized. No borrowed pointer
// survives a call. False/null means rejected input, never an engine-side effect.
#[no_mangle]
pub unsafe extern "C" fn npc_agent_create(
    identity: u64,
    home: *const Location,
    source: *const Location,
    remembered_item: *const Location,
) -> *mut Agent {
    let (Some(home), Some(source), Some(remembered_item)) = (
        unsafe { home.as_ref() },
        unsafe { source.as_ref() },
        unsafe { remembered_item.as_ref() },
    ) else {
        return std::ptr::null_mut();
    };
    Plan::new(identity, *home, *source, *remembered_item)
        .map(Agent::assigned)
        .map_or(std::ptr::null_mut(), |plan| Box::into_raw(Box::new(plan)))
}

#[no_mangle]
pub unsafe extern "C" fn npc_agent_destroy(plan: *mut Agent) {
    if !plan.is_null() {
        drop(unsafe { Box::from_raw(plan) });
    }
}

#[no_mangle]
pub unsafe extern "C" fn npc_agent_step(
    plan: *mut Agent,
    input: *const Input,
    output: *mut Output,
    control: u32,
) -> bool {
    let (Some(plan), Some(input), Some(output)) = (
        unsafe { plan.as_mut() },
        unsafe { input.as_ref() },
        unsafe { output.as_mut() },
    ) else {
        return false;
    };
    if [
        input.representation_ready,
        input.pickup_pending,
        input.path_blocked,
        input.interrupted,
        input.alive,
    ]
    .iter()
    .any(|&x| x > 1)
    {
        return false;
    }
    let supply = match input.supply {
        0 => Supply::Missing,
        1 => Supply::Free,
        2 => Supply::Owned,
        3 => Supply::OtherOwner,
        _ => return false,
    };
    let control = match control {
        0 => ScriptControl::Unobserved,
        1 => ScriptControl::Released,
        2 => ScriptControl::Owned,
        _ => return false,
    };
    let decision = plan.step_controlled(
        Observation {
            current: input.current,
            supply_location: input.supply_location,
            supply,
            representation_ready: input.representation_ready != 0,
            pickup_pending: input.pickup_pending != 0,
            path_blocked: input.path_blocked != 0,
            elapsed_ms: input.elapsed_ms,
            edge_distance: input.edge_distance,
            interrupted: input.interrupted != 0,
            alive: input.alive != 0,
        },
        input.bandages,
        control,
    );
    *output = Output::from(decision);
    true
}

#[no_mangle]
pub unsafe extern "C" fn npc_agent_script_control(plan: *mut Agent, control: u32) -> bool {
    let Some(plan) = (unsafe { plan.as_mut() }) else {
        return false;
    };
    let control = match control {
        0 => ScriptControl::Unobserved,
        1 => ScriptControl::Released,
        2 => ScriptControl::Owned,
        _ => return false,
    };
    plan.report_script_control(control);
    true
}

#[no_mangle]
pub unsafe extern "C" fn npc_agent_status(plan: *const Agent, output: *mut Output) -> bool {
    let (Some(plan), Some(output)) = (unsafe { plan.as_ref() }, unsafe { output.as_mut() }) else {
        return false;
    };
    *output = Output::from(plan.status());
    true
}

#[no_mangle]
pub unsafe extern "C" fn npc_agent_save(
    plan: *const Agent,
    output: *mut u8,
    capacity: usize,
) -> usize {
    let Some(plan) = (unsafe { plan.as_ref() }) else {
        return 0;
    };
    let bytes = plan.save();
    if capacity < bytes.len() || output.is_null() {
        return bytes.len();
    }
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len());
    }
    bytes.len()
}

#[no_mangle]
pub unsafe extern "C" fn npc_agent_load(input: *const u8, length: usize) -> *mut Agent {
    if input.is_null() || length > 16384 {
        return std::ptr::null_mut();
    }
    Agent::load(unsafe { std::slice::from_raw_parts(input, length) })
        .map_or(std::ptr::null_mut(), |plan| Box::into_raw(Box::new(plan)))
}

const _: () = assert!(std::mem::size_of::<Location>() == 24);
const _: () = assert!(std::mem::size_of::<Input>() == 84);
const _: () = assert!(std::mem::size_of::<Output>() == 64);
const _: () = assert!(Phase::Dead as u32 == 5);

#[no_mangle]
pub unsafe extern "C" fn npc_agent_create_goal(identity: u64, home: *const Location) -> *mut Agent {
    let Some(home) = (unsafe { home.as_ref() }) else {
        return std::ptr::null_mut();
    };
    Agent::medical(identity, *home)
        .map_or(std::ptr::null_mut(), |agent| Box::into_raw(Box::new(agent)))
}

#[no_mangle]
pub unsafe extern "C" fn npc_agent_remember(
    plan: *mut Agent,
    index: u32,
    navigation: *const Location,
    physical: *const Location,
) -> bool {
    let (Some(plan), Some(navigation), Some(physical)) = (
        unsafe { plan.as_mut() },
        unsafe { navigation.as_ref() },
        unsafe { physical.as_ref() },
    ) else {
        return false;
    };
    plan.remember(index as usize, *navigation, *physical)
}

#[no_mangle]
pub unsafe extern "C" fn npc_agent_available_source_slot(plan: *const Agent) -> u32 {
    unsafe { plan.as_ref() }
        .and_then(Agent::available_source_slot)
        .map_or(u32::MAX, |i| i as u32)
}

#[no_mangle]
pub unsafe extern "C" fn npc_agent_source_count(plan: *const Agent) -> usize {
    unsafe { plan.as_ref() }.map_or(0, |p| p.sources().len())
}

#[no_mangle]
pub unsafe extern "C" fn npc_agent_source(
    plan: *const Agent,
    index: u32,
    navigation: *mut Location,
) -> bool {
    let (Some(plan), Some(navigation)) = (unsafe { plan.as_ref() }, unsafe { navigation.as_mut() })
    else {
        return false;
    };
    let Some(source) = plan.sources().get(index as usize) else {
        return false;
    };
    *navigation = source.navigation;
    true
}

#[no_mangle]
pub unsafe extern "C" fn npc_agent_locations(
    plan: *const Agent,
    home: *mut Location,
    source: *mut Location,
) -> bool {
    let (Some(plan), Some(home), Some(source)) =
        (unsafe { plan.as_ref() }, unsafe { home.as_mut() }, unsafe {
            source.as_mut()
        })
    else {
        return false;
    };
    *home = plan.home();
    *source = plan
        .status()
        .source
        .map_or(plan.home(), |i| plan.sources()[i].navigation);
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn goal_memory_round_trips_through_host_owned_buffers() {
        let home = Location {
            game_vertex: 1,
            level_vertex: 2,
            level: 0,
            position: [0.0; 3],
        };
        let source = Location {
            position: [10.0, 0.0, 0.0],
            ..home
        };
        unsafe {
            let agent = npc_agent_create_goal(19, &home);
            assert!(!agent.is_null());
            assert!(npc_agent_remember(agent, 0, &source, &source));
            assert_eq!(npc_agent_available_source_slot(agent), 1);
            assert!(!npc_agent_remember(agent, 2, &source, &source));
            let size = npc_agent_save(agent, std::ptr::null_mut(), 0);
            let mut bytes = vec![0; size];
            assert_eq!(npc_agent_save(agent, bytes.as_mut_ptr(), size), size);
            let restored = npc_agent_load(bytes.as_ptr(), size);
            npc_agent_destroy(agent);
            assert!(!restored.is_null());
            assert_eq!(npc_agent_source_count(restored), 1);
            let mut location = home;
            assert!(npc_agent_source(restored, 0, &mut location));
            assert_eq!(location, source);
            let mut status = Output::default();
            assert!(npc_agent_status(restored, &mut status));
            assert_eq!(status.identity, 19);
            assert_eq!(status.phase, Phase::Waiting as u32);
            assert_eq!(status.source, u32::MAX);
            npc_agent_destroy(restored);
        }
    }

    #[test]
    fn host_buffers_round_trip_and_invalid_input_cannot_mutate_the_plan() {
        let home = Location {
            game_vertex: 1,
            level_vertex: 2,
            level: 0,
            position: [0.0; 3],
        };
        let source = Location {
            game_vertex: 1,
            level_vertex: 3,
            level: 0,
            position: [10.0, 0.0, 0.0],
        };
        // Separate host buffers and uniquely owned plans obey the C ABI contract.
        unsafe {
            let plan = npc_agent_create(7, &home, &source, &source);
            assert!(!plan.is_null());
            let mut output = Output::default();
            let mut input = Input {
                current: source,
                supply_location: source,
                supply: 1,
                representation_ready: 1,
                pickup_pending: 0,
                path_blocked: 0,
                elapsed_ms: 0,
                edge_distance: 0.0,
                interrupted: 0,
                alive: 1,
                bandages: 0,
            };
            assert!(npc_agent_step(plan, &input, &mut output, 0));
            assert_eq!(output.phase, Phase::Collecting as u32);
            input.supply_location.level_vertex = u32::MAX;
            assert!(npc_agent_step(plan, &input, &mut output, 0));
            assert_eq!(output.phase, Phase::Collecting as u32);
            input.supply_location = source;
            let size = npc_agent_save(plan, std::ptr::null_mut(), 0);
            let mut snapshot = vec![0; size];
            assert_eq!(npc_agent_save(plan, snapshot.as_mut_ptr(), size), size);
            assert!(!npc_agent_step(plan, &input, &mut output, 99));
            assert!(!npc_agent_script_control(plan, 99));
            assert!(!npc_agent_script_control(std::ptr::null_mut(), 2));
            let mut invalid_control = vec![0; size];
            npc_agent_save(plan, invalid_control.as_mut_ptr(), size);
            assert_eq!(snapshot, invalid_control);
            input.supply = 99;
            assert!(!npc_agent_step(plan, &input, &mut output, 0));
            let mut unchanged = vec![0; size];
            npc_agent_save(plan, unchanged.as_mut_ptr(), size);
            assert_eq!(snapshot, unchanged);
            let mut too_small = vec![0xab; size - 1];
            assert_eq!(npc_agent_save(plan, too_small.as_mut_ptr(), size - 1), size);
            assert!(too_small.iter().all(|&byte| byte == 0xab));
            let restored = npc_agent_load(snapshot.as_ptr(), size);
            assert!(!restored.is_null());
            npc_agent_destroy(plan);
            input.supply = 2;
            assert!(npc_agent_step(restored, &input, &mut output, 0));
            assert_eq!(output.identity, 7);
            assert_eq!(output.phase, Phase::Returning as u32);
            assert_eq!(output.level_vertex, home.level_vertex);
            npc_agent_destroy(restored);
        }
    }
}
