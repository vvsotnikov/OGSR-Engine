//! Reader for the production service trace. Wall-clock waits are not AI thinking time.
use std::{collections::BTreeMap, fmt::Write};
type Key = (u16, u64);
#[derive(Default)]
struct Object {
    member: Option<(u64, u64)>,
    last: Option<(u64, u64)>,
    online: Option<u64>,
    permission: Option<u64>,
    flags: u32,
    rejection: &'static str,
}
#[derive(Default)]
pub struct Report {
    samples: BTreeMap<&'static str, Vec<(u64, Key)>>,
    pub waits: Vec<String>,
    pub unmatched: u64,
    pub updates: u64,
    pub duration_us: u64,
    pub dropped: u64,
    window: Option<(u64, u64)>,
    collecting: bool,
    measured_updates: u64,
    settings: std::collections::BTreeSet<(u16, i64, u32)>,
    schedules: std::collections::BTreeSet<(u64, u32)>,
    unmatched_kinds: BTreeMap<String, u64>,
}
fn censor(r: &mut Report, key: Key, o: &Object, now: u64, reason: &str) {
    if !r.collecting {
        return;
    }
    if let Some(start) = o.last.or(o.member) {
        r.waits.push(format!(
            "{}, {}, {}, {}, {}, {}, {}",
            key.0,
            key.1,
            if o.last.is_some() {
                "revisit"
            } else {
                "first_visit"
            },
            now - start.0,
            reason,
            o.rejection,
            o.flags
        ));
    }
    for (kind, start) in [
        ("online_to_client", o.online),
        ("permission_to_online", o.permission),
    ] {
        if let Some(start) = start {
            r.waits.push(format!(
                "{}, {}, {}, {}, {}, {}, {}",
                key.0,
                key.1,
                kind,
                now - start,
                reason,
                o.rejection,
                o.flags
            ));
        }
    }
}
fn unmatched(r: &mut Report, kind: String) {
    if r.collecting {
        r.unmatched += 1;
        *r.unmatched_kinds.entry(kind).or_default() += 1;
    }
}
fn sample(r: &mut Report, name: &'static str, value: u64, key: Key) {
    if !r.collecting {
        return;
    }
    r.samples.entry(name).or_default().push((value, key));
}
pub fn read(text: &str) -> Result<Report, String> {
    read_window(text, None)
}
fn read_window(text: &str, window: Option<(u64, u64)>) -> Result<Report, String> {
    if window.is_some_and(|(start, end)| start >= end) {
        return Err("Invalid measurement window".into());
    }
    let mut lines = text.lines();
    if lines.next() != Some("ogsr-service,1")
        || lines.next() != Some("us,kind,id,generation,value,flags")
    {
        return Err("Unsupported service trace header".into());
    }
    let mut r = Report {
        window,
        ..Default::default()
    };
    let mut closed = false;
    let mut objects = BTreeMap::<Key, Object>::new();
    let mut generations = BTreeMap::<u16, u64>::new();
    let mut previous = 0;
    let mut ended = false;
    for (index, line) in lines.enumerate() {
        let f: Vec<_> = line.split(',').collect();
        if ended || f.len() != 6 {
            return Err(format!("Invalid record at line {}", index + 3));
        }
        let number = |i: usize| {
            f[i].parse::<u64>()
                .map_err(|_| format!("Invalid integer at line {}", index + 3))
        };
        let (now, id, generation, value, flags) =
            (number(0)?, number(2)?, number(3)?, number(4)?, number(5)?);
        if now < previous || id > u16::MAX as u64 || flags > u32::MAX as u64 {
            return Err("Invalid clock or field range".into());
        }
        if !matches!(
            f[1],
            "register"
                | "clock"
                | "update"
                | "scheduler"
                | "end"
                | "permission_on"
                | "permission_off"
                | "offline_permission"
                | "enter"
                | "leave"
                | "visit"
                | "remove"
                | "eligible_observed"
                | "online"
                | "offline"
                | "client"
                | "distance_rejected"
                | "permission_rejected"
        ) {
            return Err(format!("Unknown event {}", f[1]));
        }
        previous = now;
        let key = (id as u16, generation);
        if let Some((_, end)) = window {
            if now >= end && !closed {
                r.collecting = true;
                for (key, o) in &objects {
                    censor(&mut r, *key, o, end, "window_end");
                }
                closed = true;
            }
        }
        r.collecting = window.is_none_or(|(start, end)| now >= start && now < end);
        if f[1] == "end" {
            if generation != index as u64 {
                return Err("Record count mismatch: missing or duplicated rows".into());
            }
            r.duration_us = now;
            r.dropped = value;
            ended = true;
            if window.is_some_and(|(_, end)| end > now) {
                return Err("Window exceeds capture".into());
            }
            if !closed {
                for (key, o) in &objects {
                    censor(&mut r, *key, o, now, "capture_end");
                }
            }
            continue;
        }
        if f[1] == "scheduler" {
            if r.collecting {
                r.schedules.insert((value, flags as u32));
            }
            continue;
        }
        if f[1] == "clock" {
            continue;
        }
        if f[1] == "update" {
            if r.collecting {
                r.settings.insert((id as u16, value as i64, flags as u32));
                r.measured_updates += 1;
            }
            r.updates += 1;
            continue;
        }
        if closed {
            continue;
        }
        if f[1] == "register" {
            if generation == 0 || generations.get(&key.0).is_some_and(|g| *g >= generation) {
                return Err("Invalid registration generation".into());
            }
            if let Some(old) = generations.insert(key.0, generation) {
                if let Some(o) = objects.remove(&(key.0, old)) {
                    censor(&mut r, (key.0, old), &o, now, "id_reused");
                }
            }
            objects.insert(
                key,
                Object {
                    flags: flags as u32,
                    ..Default::default()
                },
            );
            continue;
        }
        let Some(o) = objects.get_mut(&key) else {
            unmatched(&mut r, format!("unregistered_{}", f[1]));
            continue;
        };
        match f[1] {
            "permission_on" => {
                o.flags = flags as u32;
                if flags & 1 == 0 {
                    o.permission.get_or_insert(now);
                }
            }
            "permission_off" => {
                o.flags = flags as u32;
                if let Some(start) = o.permission.take() {
                    if r.collecting {
                        r.waits.push(format!(
                            "{}, {}, permission_to_online, {}, permission_revoked, , {}",
                            key.0,
                            key.1,
                            now - start,
                            o.flags
                        ));
                    }
                }
            }
            "offline_permission" => {
                o.flags = flags as u32;
            }
            "enter" => {
                if o.member.is_none() {
                    o.member = Some((now, r.updates));
                    o.flags = flags as u32;
                }
            }
            "visit" => {
                o.flags = flags as u32;
                if let Some((time, update)) = o.last.or(o.member) {
                    sample(
                        &mut r,
                        if o.last.is_some() {
                            "revisit_us"
                        } else {
                            "first_visit_us"
                        },
                        now - time,
                        key,
                    );
                    if flags & 4 != 0 {
                        sample(
                            &mut r,
                            if o.last.is_some() {
                                "creature_revisit_us"
                            } else {
                                "creature_first_visit_us"
                            },
                            now - time,
                            key,
                        );
                    }
                    let gap = r.updates - update;
                    sample(&mut r, "evaluation_update_gap", gap, key);
                } else {
                    unmatched(&mut r, format!("unpaired_{}", f[1]));
                }
                o.last = Some((now, r.updates));
            }
            // Older captures include this synchronous call-boundary event. It
            // adds no eligibility-wait measurement, so accept it without a metric.
            "eligible_observed" => {}
            "online" => {
                if let Some(start) = o.permission.take() {
                    if o.flags & 4 != 0 {
                        sample(&mut r, "creature_permission_to_online_us", now - start, key);
                    }
                    sample(&mut r, "permission_to_online_us", now - start, key);
                }
                if o.online.is_some() {
                    return Err("Online transition before previous activation finished".into());
                }
                o.online = Some(now);
            }
            "client" => {
                if let Some(start) = o.online.take() {
                    if o.flags & 4 != 0 {
                        sample(&mut r, "creature_online_to_client_us", now - start, key);
                    }
                    sample(&mut r, "online_to_client_us", now - start, key);
                } else {
                    unmatched(&mut r, format!("unpaired_{}", f[1]));
                }
            }
            "distance_rejected" => o.rejection = "distance",
            "permission_rejected" => o.rejection = "permission",
            "offline" => {
                if let Some(start) = o.online.take() {
                    if r.collecting {
                        r.waits.push(format!(
                            "{}, {}, online_to_client, {}, offline, , {}",
                            key.0,
                            key.1,
                            now - start,
                            o.flags
                        ));
                    }
                }
            }
            "leave" => {
                censor(&mut r, key, o, now, "left_switch_registry");
                o.permission = None;
                o.member = None;
                o.last = None;
                o.online = None;
            }
            "remove" => {
                censor(&mut r, key, o, now, "removed");
                objects.remove(&key);
            }
            _ => unreachable!(),
        }
    }
    if !ended {
        return Err("Capture is incomplete: no end record (crash or unfinished export)".into());
    }
    Ok(r)
}
impl Report {
    pub fn render(&mut self) -> String {
        let mut out = format!(
            "duration_us={} updates={} dropped={} unmatched={} capture_integrity={}\n",
            self.duration_us,
            self.updates,
            self.dropped,
            self.unmatched,
            if self.dropped == 0 {
                "ok"
            } else {
                "dropped_records"
            }
        );
        if let Some((start, end)) = self.window {
            writeln!(
                out,
                "window_start_us={start} window_end_us={end} measured_updates={}",
                self.measured_updates
            )
            .unwrap();
        }
        for (level, budget, flags) in &self.settings {
            writeln!(
                out,
                "settings level={level} budget_us={budget} whole_map={} mt_alife={}",
                flags & 1 != 0,
                flags & 2 != 0
            )
            .unwrap();
        }
        for (value, count) in &self.schedules {
            writeln!(
                out,
                "scheduler min_ms={} max_ms={} objects_per_update={count}",
                value >> 32,
                value & 0xffffffff
            )
            .unwrap();
        }
        for (kind, count) in &self.unmatched_kinds {
            writeln!(out, "unmatched {kind}={count}").unwrap();
        }
        out.push_str("metric,count,p50,p95,p99,max,worst_id,generation\n");
        for (name, values) in &mut self.samples {
            values.sort_unstable();
            let n = values.len();
            let q = |percent: usize| values[(n * percent).div_ceil(100).saturating_sub(1)].0;
            let worst = values[n - 1];
            writeln!(
                out,
                "{name},{n},{},{},{},{},{},{}",
                q(50),
                q(95),
                q(99),
                worst.0,
                worst.1 .0,
                worst.1 .1
            )
            .unwrap();
        }
        out.push_str(
            "unfinished_id,generation,wait_kind,age_us,termination,last_rejection,flags\n",
        );
        for wait in &self.waits {
            writeln!(out, "{wait}").unwrap();
        }
        out
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn capture(records: &str) -> String {
        let mut out = String::from("ogsr-service,1\nus,kind,id,generation,value,flags\n");
        for (index, line) in records.lines().enumerate() {
            let mut f: Vec<_> = line.split(',').map(str::to_string).collect();
            if f[1] == "end" {
                f[3] = index.to_string();
            }
            writeln!(out, "{}", f.join(",")).unwrap();
        }
        out
    }
    #[test]
    fn first_revisit_and_unfinished_waits() {
        let mut r=read(&capture("0,register,1,1,0,12\n10,enter,1,1,0,12\n20,update,5,0,810,1\n30,visit,1,1,0,12\n40,update,5,0,810,1\n70,visit,1,1,0,12\n100,end,65535,0,0,0\n")).unwrap();
        assert_eq!(r.samples["first_visit_us"][0].0, 20);
        assert_eq!(r.samples["revisit_us"][0].0, 40);
        assert!(r.render().contains("revisit, 30, capture_end"));
    }
    #[test]
    fn never_visited_removal_reuse_and_map_leave() {
        let r=read(&capture("0,register,2,1,0,12\n0,enter,2,1,0,12\n10,leave,2,1,0,0\n11,enter,2,1,0,12\n20,remove,2,1,0,0\n21,register,2,2,0,12\n22,enter,2,2,0,12\n30,end,65535,0,0,0\n")).unwrap();
        assert_eq!(r.waits.len(), 3);
        assert!(r.waits[0].contains("10, left_switch_registry"));
        assert!(r.waits[2].contains("2, 2, first_visit, 8, capture_end"));
    }
    #[test]
    fn activation_completion_and_censoring() {
        let r=read(&capture("0,register,3,1,0,12\n10,eligible_observed,3,1,0,0\n12,online,3,1,0,0\n40,client,3,1,0,0\n50,offline,3,1,0,0\n60,online,3,1,0,0\n100,end,65535,0,0,0\n")).unwrap();
        assert!(!r.samples.contains_key("observed_to_online_us"));
        assert_eq!(r.samples["online_to_client_us"][0].0, 28);
        assert!(r.waits[0].contains("online_to_client, 40, capture_end"));
    }
    #[test]
    fn missing_row_is_detected_even_with_valid_footer() {
        let text = capture("0,register,1,1,0,12\n1,enter,1,1,0,12\n2,end,65535,0,0,0\n");
        assert!(read(&text.replace("1,enter,1,1,0,12\n", "")).is_err());
    }
    #[test]
    fn broken_capture_is_never_silently_accepted() {
        assert!(read(&capture("0,register,1,1,0,0\n")).is_err());
        assert!(read(&capture("10,register,1,1,0,0\n5,end,65535,0,0,0\n")).is_err());
        let mut r = read(&capture("10,end,65535,0,12,0\n")).unwrap();
        assert!(r.render().contains("capture_integrity=dropped_records"));
    }
    #[test]
    fn permission_trigger_and_revocation_are_not_observation_latency() {
        let r=read(&capture("0,register,1,1,0,60\n1,permission_on,1,1,0,60\n2,permission_on,1,1,0,60\n10,eligible_observed,1,1,0,0\n12,online,1,1,0,0\n14,client,1,1,0,0\n20,offline,1,1,0,0\n21,permission_on,1,1,0,60\n30,permission_off,1,1,0,44\n40,end,65535,0,0,0\n")).unwrap();
        assert_eq!(r.samples["permission_to_online_us"][0].0, 11);
        assert!(!r.samples.contains_key("observed_to_online_us"));
        assert!(r.waits[0].contains("permission_to_online, 9, permission_revoked"));
    }
    #[test]
    fn generation_reuse_does_not_complete_old_activation() {
        let r=read(&capture("0,register,1,1,0,12\n1,online,1,1,0,0\n10,register,1,2,0,12\n11,client,1,2,0,0\n20,end,65535,0,0,0\n")).unwrap();
        assert!(!r.samples.contains_key("online_to_client_us"));
        assert!(r.waits[0].contains("id_reused"));
        assert_eq!(r.unmatched, 1);
    }
    #[test]
    fn clock_includes_pause_and_reload_has_separate_identity() {
        let data = capture(
            "0,register,1,1,0,0\n1,enter,1,1,0,0\n1000001,visit,1,1,0,0\n1000002,end,65535,0,0,0\n",
        );
        for _ in 0..2 {
            assert_eq!(read(&data).unwrap().samples["first_visit_us"][0].0, 1000000);
        }
    }
}

struct Frame {
    number: u32,
    game_ms: u64,
    stage: u32,
    ms: f64,
}
fn frames(text: &str) -> Result<Vec<Frame>, String> {
    let mut lines = text.lines();
    if lines.next() != Some("frame,game_ms,stage,wall_ms") {
        return Err("Invalid frame capture header".into());
    }
    let mut result = Vec::new();
    let mut previous = None;
    for line in lines {
        let f: Vec<_> = line.split(',').collect();
        if f.len() != 4 {
            return Err("Invalid frame row".into());
        }
        let number = f[0].parse::<u32>().map_err(|_| "Invalid frame number")?;
        let game_ms = f[1].parse::<u64>().map_err(|_| "Invalid game time")?;
        let stage = f[2].parse::<u32>().map_err(|_| "Invalid frame stage")?;
        let ms = f[3].parse::<f64>().map_err(|_| "Invalid frame interval")?;
        if !ms.is_finite() || ms < 0. || stage > 4 || previous.is_some_and(|v| number <= v) {
            return Err("Invalid frame interval or ordering".into());
        }
        previous = Some(number);
        result.push(Frame {
            number,
            game_ms,
            stage,
            ms,
        });
    }
    if result.is_empty() {
        return Err("Empty frame capture".into());
    }
    Ok(result)
}
pub fn frame_report(text: &str) -> Result<String, String> {
    let rows = frames(text)?;
    let mut stages = BTreeMap::<u32, Vec<f64>>::new();
    for row in rows {
        stages.entry(row.stage).or_default().push(row.ms);
    }
    let mut out = String::from("stage,frames,total_ms,p50_ms,p95_ms,p99_ms,max_ms\n");
    for (stage, mut times) in stages {
        times.sort_by(f64::total_cmp);
        let n = times.len();
        let q = |p: usize| times[(n * p).div_ceil(100).saturating_sub(1)];
        writeln!(
            out,
            "{stage},{n},{:.3},{:.3},{:.3},{:.3},{:.3}",
            times.iter().sum::<f64>(),
            q(50),
            q(95),
            q(99),
            q(100)
        )
        .unwrap();
    }
    Ok(out)
}
pub fn read_warmed(text: &str, frame_text: &str) -> Result<Report, String> {
    let rows = frames(frame_text)?;
    let warm: Vec<_> = rows.iter().filter(|r| r.stage == 4).collect();
    let first = warm.first().ok_or("No warmed frame window")?.number;
    let last = warm.last().unwrap().number;
    let mut start = None;
    let mut end = None;
    let clocks: BTreeMap<_, _> = rows.iter().map(|r| (r.number, r.game_ms)).collect();
    for line in text.lines().skip(2) {
        let f: Vec<_> = line.split(',').collect();
        if f.len() != 6 {
            return Err("Invalid service record".into());
        }
        if f[1] == "clock" {
            let us = f[0].parse::<u64>().map_err(|_| "Invalid clock")?;
            let frame = f[5].parse::<u32>().map_err(|_| "Invalid clock frame")?;
            if let Some(expected) = clocks.get(&frame) {
                if f[4].parse::<u64>().map_err(|_| "Invalid game clock")? != *expected {
                    return Err("Frame and service clocks do not match".into());
                }
            }
            if frame >= first && frame <= last {
                if start.is_none() {
                    start = Some(us);
                }
                end = Some(us);
            }
        }
    }
    read_window(
        text,
        Some((
            start.ok_or("No service clock for warmed frames")?,
            end.ok_or("No end of warmed service window")?,
        )),
    )
}

#[cfg(test)]
mod window_tests {
    use super::*;
    #[test]
    fn warmed_window_preserves_old_unfinished_waits_and_excludes_loading_samples() {
        let text="ogsr-service,1\nus,kind,id,generation,value,flags\n0,register,1,1,0,12\n1,enter,1,1,0,12\n2,visit,1,1,0,12\n3,register,2,1,0,12\n4,enter,2,1,0,12\n10,clock,65535,0,100,10\n11,visit,1,1,0,12\n20,clock,65535,0,110,11\n21,visit,1,1,0,12\n30,clock,65535,0,120,12\n40,end,65535,10,0,0\n";
        let r = read_warmed(
            text,
            "frame,game_ms,stage,wall_ms\n10,100,4,10\n11,110,4,10\n",
        )
        .unwrap();
        assert!(!r.samples.contains_key("first_visit_us"));
        assert_eq!(r.samples["revisit_us"].len(), 1);
        assert!(r
            .waits
            .iter()
            .any(|w| w.contains("2, 1, first_visit, 16, window_end")));
    }
    #[test]
    fn mismatched_frame_capture_is_rejected() {
        let text="ogsr-service,1\nus,kind,id,generation,value,flags\n0,clock,65535,0,100,10\n10,clock,65535,0,110,11\n20,end,65535,2,0,0\n";
        assert!(read_warmed(
            text,
            "frame,game_ms,stage,wall_ms\n10,101,4,10\n11,111,4,10\n"
        )
        .is_err());
    }
    #[test]
    fn frame_reader_checks_bad_values_and_uses_nearest_rank() {
        assert!(frame_report("frame,game_ms,stage,wall_ms\n1,1,4,NaN\n").is_err());
        assert!(frame_report("frame,game_ms,stage,wall_ms\n1,1,4,1\n1,2,4,1\n").is_err());
        assert!(
            frame_report("frame,game_ms,stage,wall_ms\n1,1,4,1\n2,2,4,3\n")
                .unwrap()
                .contains("4,2,4.000,1.000,3.000,3.000,3.000")
        );
    }
}
