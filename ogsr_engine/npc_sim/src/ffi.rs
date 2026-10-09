use crate::{Action, Location, Observation, Phase, Plan, Supply};

#[repr(C)]
pub struct Input {
    current: Location,
    supply_location: Location,
    supply: u32,
    representation_ready: u32,
    pickup_pending: u32,
    path_blocked: u32,
    elapsed_ms: u32,
    interrupted: u32,
    alive: u32,
}

#[repr(C)]
#[derive(Default)]
pub struct Output {
    identity: u64,
    command: u64,
    phase: u32,
    interrupted: u32,
    action: u32,
    game_vertex: u32,
    level_vertex: u32,
    level: u32,
    position: [f32; 3],
}

impl From<crate::Decision> for Output {
    fn from(decision: crate::Decision) -> Self {
        let mut output = Self {
            identity: decision.identity,
            command: decision.command,
            phase: decision.phase as u32,
            interrupted: u32::from(decision.interrupted),
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
pub unsafe extern "C" fn npc_plan_create(
    identity: u64,
    home: *const Location,
    source: *const Location,
) -> *mut Plan {
    let (Some(home), Some(source)) = (unsafe { home.as_ref() }, unsafe { source.as_ref() }) else {
        return std::ptr::null_mut();
    };
    Plan::new(identity, *home, *source)
        .map_or(std::ptr::null_mut(), |plan| Box::into_raw(Box::new(plan)))
}

#[no_mangle]
pub unsafe extern "C" fn npc_plan_destroy(plan: *mut Plan) {
    if !plan.is_null() {
        drop(unsafe { Box::from_raw(plan) });
    }
}

#[no_mangle]
pub unsafe extern "C" fn npc_plan_step(
    plan: *mut Plan,
    input: *const Input,
    output: *mut Output,
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
    if !input.current.valid() || (supply != Supply::Missing && !input.supply_location.valid()) {
        return false;
    }
    let decision = plan.step(Observation {
        current: input.current,
        supply_location: input.supply_location,
        supply,
        representation_ready: input.representation_ready != 0,
        pickup_pending: input.pickup_pending != 0,
        path_blocked: input.path_blocked != 0,
        elapsed_ms: input.elapsed_ms,
        interrupted: input.interrupted != 0,
        alive: input.alive != 0,
    });
    *output = Output::from(decision);
    true
}

#[no_mangle]
pub unsafe extern "C" fn npc_plan_status(plan: *const Plan, output: *mut Output) -> bool {
    let (Some(plan), Some(output)) = (unsafe { plan.as_ref() }, unsafe { output.as_mut() }) else {
        return false;
    };
    *output = Output::from(plan.decision());
    true
}

#[no_mangle]
pub unsafe extern "C" fn npc_plan_save(
    plan: *const Plan,
    output: *mut u8,
    capacity: usize,
) -> usize {
    let Some(plan) = (unsafe { plan.as_ref() }) else {
        return 0;
    };
    if capacity < Plan::SNAPSHOT_SIZE || output.is_null() {
        return Plan::SNAPSHOT_SIZE;
    }
    let bytes = plan.save();
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len());
    }
    bytes.len()
}

#[no_mangle]
pub unsafe extern "C" fn npc_plan_load(input: *const u8, length: usize) -> *mut Plan {
    if input.is_null() || length != Plan::SNAPSHOT_SIZE {
        return std::ptr::null_mut();
    }
    Plan::load(unsafe { std::slice::from_raw_parts(input, length) })
        .map_or(std::ptr::null_mut(), |plan| Box::into_raw(Box::new(plan)))
}

const _: () = assert!(std::mem::size_of::<Location>() == 24);
const _: () = assert!(std::mem::size_of::<Input>() == 76);
const _: () = assert!(std::mem::size_of::<Output>() == 56);
const _: () = assert!(Phase::Dead as u32 == 5);

#[no_mangle]
pub unsafe extern "C" fn npc_plan_locations(
    plan: *const Plan,
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
    *home = plan.home;
    *source = plan.source;
    true
}

#[cfg(test)]
mod tests {
    use super::*;

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
            let plan = npc_plan_create(7, &home, &source);
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
                interrupted: 0,
                alive: 1,
            };
            assert!(npc_plan_step(plan, &input, &mut output));
            assert_eq!(output.phase, Phase::Collecting as u32);
            let size = npc_plan_save(plan, std::ptr::null_mut(), 0);
            let mut snapshot = vec![0; size];
            assert_eq!(npc_plan_save(plan, snapshot.as_mut_ptr(), size), size);
            input.supply = 99;
            assert!(!npc_plan_step(plan, &input, &mut output));
            let mut unchanged = vec![0; size];
            npc_plan_save(plan, unchanged.as_mut_ptr(), size);
            assert_eq!(snapshot, unchanged);
            let mut too_small = vec![0xab; size - 1];
            assert_eq!(npc_plan_save(plan, too_small.as_mut_ptr(), size - 1), size);
            assert!(too_small.iter().all(|&byte| byte == 0xab));
            let restored = npc_plan_load(snapshot.as_ptr(), size);
            assert!(!restored.is_null());
            npc_plan_destroy(plan);
            input.supply = 2;
            assert!(npc_plan_step(restored, &input, &mut output));
            assert_eq!(output.identity, 7);
            assert_eq!(output.phase, Phase::Returning as u32);
            assert_eq!(output.level_vertex, home.level_vertex);
            npc_plan_destroy(restored);
        }
    }
}
