//! Reader for the production service trace. Wall-clock waits are not AI thinking time.
use std::{
    collections::BTreeMap,
    fmt::Write,
    io::{BufRead, Seek},
};
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
    samples: BTreeMap<&'static str, Vec<(u64, u64, u16, bool)>>,
    pub waits: Vec<String>,
    pub unmatched: u64,
    pub updates: u64,
    pub duration_us: u64,
    pub dropped: u64,
    window: Option<(u64, u64)>,
    collecting: bool,
    measured_updates: u64,
    detail: Option<bool>,
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
fn sample(r: &mut Report, name: &'static str, value: u64, key: Key, creature: bool) {
    if !r.collecting {
        return;
    }
    r.samples
        .entry(name)
        .or_default()
        .push((value, key.1, key.0, creature));
}
fn records(reader: impl BufRead) -> Result<impl Iterator<Item = Result<String, String>>, String> {
    let mut lines = reader.lines().map(|line| line.map_err(|e| e.to_string()));
    if lines.next().transpose()?.as_deref() != Some("ogsr-service,1")
        || lines.next().transpose()?.as_deref() != Some("us,kind,id,generation,value,flags")
    {
        return Err("Unsupported service trace header".into());
    }
    Ok(lines)
}
pub fn read(reader: impl BufRead) -> Result<Report, String> {
    read_window(reader, None)
}
fn read_window(reader: impl BufRead, window: Option<(u64, u64)>) -> Result<Report, String> {
    if window.is_some_and(|(start, end)| start >= end) {
        return Err("Invalid measurement window".into());
    }
    let lines = records(reader)?;
    let mut r = Report {
        window,
        ..Default::default()
    };
    let mut closed = false;
    let mut objects = BTreeMap::<Key, Object>::new();
    let mut generations = BTreeMap::<u16, u64>::new();
    let mut previous = 0;
    let mut ended = false;
    let mut settings = None;
    let mut schedule = None;
    let mut slice = None;
    let mut completed_slices = 0;
    for (index, line) in lines.enumerate() {
        let line = line?;
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
                | "mode"
                | "slice_begin"
                | "slice_end"
                | "clock"
                | "update"
                | "scheduler"
                | "settings"
                | "end"
                | "permission_on"
                | "permission_off"
                | "offline_permission"
                | "enter"
                | "leave"
                | "visit"
                | "remove"
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
            if slice.is_some() || (r.detail.is_some() && completed_slices != r.updates) {
                return Err("Incomplete slice coverage".into());
            }
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
        if f[1] == "mode" {
            if index != 0 || value > 1 {
                return Err("Invalid trace mode".into());
            }
            r.detail = Some(value == 1);
            continue;
        }
        if f[1] == "slice_begin" {
            if r.updates != completed_slices + 1 {
                return Err("Slice without a corresponding update".into());
            }
            if slice.replace((now, flags)).is_some() {
                return Err("Overlapping slices".into());
            }
            continue;
        }
        if f[1] == "slice_end" {
            let (start, population) = slice.take().ok_or("Slice end without beginning")?;
            completed_slices += 1;
            sample(&mut r, "slice_wall_us", now - start, (65535, 0), false);
            sample(&mut r, "slice_visits", value, (65535, 0), false);
            sample(
                &mut r,
                "slice_population_before",
                population,
                (65535, 0),
                false,
            );
            sample(&mut r, "slice_population_after", flags, (65535, 0), false);
            continue;
        }
        if f[1] == "scheduler" {
            schedule = Some((value, flags as u32));
            continue;
        }
        if f[1] == "settings" || (f[1] == "update" && id != 65535) {
            settings = Some((id as u16, value as i64, flags as u32));
            if f[1] == "settings" {
                continue;
            }
        }
        if f[1] == "clock" {
            continue;
        }
        if f[1] == "update" {
            if r.detail.is_some() && r.updates != completed_slices {
                return Err("Incomplete slice coverage".into());
            }
            if r.collecting {
                if let Some(settings) = settings {
                    r.settings.insert(settings);
                }
                if let Some(schedule) = schedule {
                    r.schedules.insert(schedule);
                }
                r.measured_updates += 1;
            }
            r.updates += 1;
            continue;
        }
        if r.detail == Some(false) {
            return Err("Object event in slice-only capture".into());
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
                            "{}, {}, permission_to_online, {}, permission_revoked, {}, {}",
                            key.0,
                            key.1,
                            now - start,
                            o.rejection,
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
                    o.rejection = "";
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
                        flags & 4 != 0,
                    );
                    let gap = r.updates - update;
                    sample(&mut r, "evaluation_update_gap", gap, key, false);
                } else {
                    unmatched(&mut r, format!("unpaired_{}", f[1]));
                }
                o.last = Some((now, r.updates));
            }
            "online" => {
                o.rejection = "";
                if let Some(start) = o.permission.take() {
                    sample(
                        &mut r,
                        "permission_to_online_us",
                        now - start,
                        key,
                        o.flags & 4 != 0,
                    );
                }
                if o.online.is_some() {
                    return Err("Online transition before previous activation finished".into());
                }
                o.online = Some(now);
            }
            "client" => {
                if let Some(start) = o.online.take() {
                    sample(
                        &mut r,
                        "online_to_client_us",
                        now - start,
                        key,
                        o.flags & 4 != 0,
                    );
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
                            "{}, {}, online_to_client, {}, offline, {}, {}",
                            key.0,
                            key.1,
                            now - start,
                            o.rejection,
                            o.flags
                        ));
                    }
                }
            }
            "leave" => {
                censor(&mut r, key, o, now, "left_switch_registry");
                o.rejection = "";
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
        writeln!(
            out,
            "mode={}",
            match self.detail {
                Some(true) => "full",
                Some(false) => "slices",
                None => "legacy_full",
            }
        )
        .unwrap();
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
            values.sort_unstable_by_key(|v| (v.0, v.2, v.1));
            for creatures_only in [false, true] {
                let selected = || values.iter().filter(|v| !creatures_only || v.3);
                let n = selected().count();
                if n == 0 {
                    continue;
                }
                let q = |percent: usize| {
                    selected()
                        .nth((n * percent).div_ceil(100).saturating_sub(1))
                        .unwrap()
                        .0
                };
                let worst = selected().next_back().unwrap();
                let prefix = if creatures_only { "creature_" } else { "" };
                writeln!(
                    out,
                    "{prefix}{name},{n},{},{},{},{},{},{}",
                    q(50),
                    q(95),
                    q(99),
                    worst.0,
                    worst.2,
                    worst.1
                )
                .unwrap();
            }
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
    #[test]
    fn slice_only_reports_counts_without_inventing_object_waits() {
        let text = capture(concat!(
            "0,mode,65535,0,0,0\n",
            "1,update,65535,0,0,0\n",
            "2,slice_begin,65535,0,0,40\n",
            "812,slice_end,65535,0,7,41\n",
            "900,end,65535,0,0,0\n",
        ));
        let mut r = read(&text).unwrap();
        assert_eq!(r.samples["slice_wall_us"][0].0, 810);
        assert_eq!(r.samples["slice_visits"][0].0, 7);
        assert_eq!(r.samples["slice_population_before"][0].0, 40);
        assert_eq!(r.samples["slice_population_after"][0].0, 41);
        assert!(r.waits.is_empty());
        assert_eq!(r.unmatched, 0);
        assert!(r.render().contains("mode=slices"));
        assert!(read(&text.replace("812,slice_end", "812,slice_begin")).is_err());
        assert!(read(&text.replace("1,update", "1,register")).is_err());
        assert!(read(&text.replace("2,slice_begin,65535,0,0,40\n", "")).is_err());
    }
    #[test]
    fn modern_capture_requires_a_slice_for_each_update() {
        let text = capture(concat!(
            "0,mode,65535,0,1,0\n",
            "1,update,65535,0,0,0\n",
            "2,end,65535,0,0,0\n",
        ));
        assert_eq!(
            read(&text).err().as_deref(),
            Some("Incomplete slice coverage")
        );
    }
    #[test]
    fn shared_samples_preserve_quantiles_and_worst_identity_for_both_populations() {
        let mut r = Report {
            collecting: true,
            ..Default::default()
        };
        sample(&mut r, "revisit_us", 5, (1, 1), false);
        sample(&mut r, "revisit_us", 10, (9, 1), true);
        sample(&mut r, "revisit_us", 10, (3, 2), true);
        sample(&mut r, "revisit_us", 20, (4, 1), false);
        let text = r.render();
        assert!(text.lines().any(|l| l == "revisit_us,4,10,20,20,20,4,1"));
        assert!(text
            .lines()
            .any(|l| l == "creature_revisit_us,2,10,10,10,10,9,1"));
    }
    fn read(text: &str) -> Result<Report, String> {
        super::read(text.as_bytes())
    }
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
        let mut r = read(&capture(concat!(
            "0,register,1,1,0,12\n",
            "10,enter,1,1,0,12\n",
            "20,update,5,0,810,1\n",
            "30,visit,1,1,0,12\n",
            "40,update,5,0,810,1\n",
            "70,visit,1,1,0,12\n",
            "100,end,65535,0,0,0\n",
        )))
        .unwrap();
        assert_eq!(r.samples["first_visit_us"][0].0, 20);
        assert_eq!(r.samples["revisit_us"][0].0, 40);
        assert!(r.render().contains("revisit, 30, capture_end"));
    }
    #[test]
    fn never_visited_removal_reuse_and_map_leave() {
        let r = read(&capture(concat!(
            "0,register,2,1,0,12\n",
            "0,enter,2,1,0,12\n",
            "10,leave,2,1,0,0\n",
            "11,enter,2,1,0,12\n",
            "20,remove,2,1,0,0\n",
            "21,register,2,2,0,12\n",
            "22,enter,2,2,0,12\n",
            "30,end,65535,0,0,0\n",
        )))
        .unwrap();
        assert_eq!(r.waits.len(), 3);
        assert!(r.waits[0].contains("10, left_switch_registry"));
        assert!(r.waits[2].contains("2, 2, first_visit, 8, capture_end"));
    }
    #[test]
    fn reentry_does_not_inherit_the_previous_membership_rejection() {
        let r = read(&capture(concat!(
            "0,register,1,1,0,44\n",
            "1,enter,1,1,0,44\n",
            "2,visit,1,1,0,44\n",
            "3,permission_rejected,1,1,0,0\n",
            "4,leave,1,1,0,0\n",
            "10,enter,1,1,0,60\n",
            "20,end,65535,0,0,0\n",
        )))
        .unwrap();
        assert!(r.waits[0].contains("left_switch_registry, permission, 44"));
        assert_eq!(r.waits[1], "1, 1, first_visit, 10, capture_end, , 60");
    }
    #[test]
    fn successful_activation_clears_an_earlier_rejection() {
        let r = read(&capture(concat!(
            "0,register,1,1,0,44\n",
            "1,enter,1,1,0,44\n",
            "2,visit,1,1,0,44\n",
            "3,permission_rejected,1,1,0,0\n",
            "4,permission_on,1,1,0,60\n",
            "5,online,1,1,0,0\n",
            "6,client,1,1,0,0\n",
            "10,end,65535,0,0,0\n",
        )))
        .unwrap();
        assert_eq!(r.waits, ["1, 1, revisit, 8, capture_end, , 60"]);
    }
    #[test]
    fn activation_completion_and_censoring() {
        let r = read(&capture(concat!(
            "0,register,3,1,0,12\n",
            "12,online,3,1,0,0\n",
            "40,client,3,1,0,0\n",
            "50,offline,3,1,0,0\n",
            "60,online,3,1,0,0\n",
            "100,end,65535,0,0,0\n",
        )))
        .unwrap();
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
        let r = read(&capture(concat!(
            "0,register,1,1,0,60\n",
            "1,permission_on,1,1,0,60\n",
            "2,permission_on,1,1,0,60\n",
            "12,online,1,1,0,0\n",
            "14,client,1,1,0,0\n",
            "20,offline,1,1,0,0\n",
            "21,permission_on,1,1,0,60\n",
            "30,permission_off,1,1,0,44\n",
            "40,end,65535,0,0,0\n",
        )))
        .unwrap();
        assert_eq!(r.samples["permission_to_online_us"][0].0, 11);
        assert!(r.waits[0].contains("permission_to_online, 9, permission_revoked"));
    }
    #[test]
    fn generation_reuse_does_not_complete_old_activation() {
        let r = read(&capture(concat!(
            "0,register,1,1,0,12\n",
            "1,online,1,1,0,0\n",
            "10,register,1,2,0,12\n",
            "11,client,1,2,0,0\n",
            "20,end,65535,0,0,0\n",
        )))
        .unwrap();
        assert!(!r.samples.contains_key("online_to_client_us"));
        assert!(r.waits[0].contains("id_reused"));
        assert_eq!(r.unmatched, 1);
    }
    #[test]
    fn terminated_waits_preserve_last_observed_rejection() {
        let r = read(&capture(concat!(
            "0,register,1,1,0,12\n",
            "1,permission_on,1,1,0,28\n",
            "2,permission_rejected,1,1,0,0\n",
            "3,permission_off,1,1,0,12\n",
            "4,online,1,1,0,0\n",
            "5,distance_rejected,1,1,0,0\n",
            "6,offline,1,1,0,0\n",
            "7,end,65535,0,0,0\n",
        )))
        .unwrap();
        assert!(r
            .waits
            .iter()
            .any(|w| w.contains("permission_to_online, 2, permission_revoked, permission, 12")));
        assert!(r
            .waits
            .iter()
            .any(|w| w.contains("online_to_client, 2, offline, distance, 12")));
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
pub fn read_warmed(mut reader: impl BufRead + Seek, frame_text: &str) -> Result<Report, String> {
    let rows = frames(frame_text)?;
    let warm: Vec<_> = rows.iter().filter(|r| r.stage == 4).collect();
    let first = warm.first().ok_or("No warmed frame window")?.number;
    let last = warm.last().unwrap().number;
    let mut start = None;
    let mut end = None;
    let clocks: BTreeMap<_, _> = rows.iter().map(|r| (r.number, r.game_ms)).collect();
    for line in records(reader.by_ref())? {
        let line = line?;
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
    reader.rewind().map_err(|e| e.to_string())?;
    read_window(
        reader,
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
    fn warmed_settings_include_prior_state_and_changes_in_the_window() {
        let text = concat!(
            "ogsr-service,1\nus,kind,id,generation,value,flags\n",
            "0,settings,5,0,810,3\n",
            "1,scheduler,65535,0,4294967297,10\n",
            "2,clock,65535,0,100,10\n",
            "3,update,65535,0,0,0\n",
            "4,settings,5,0,900,3\n",
            "5,update,65535,0,0,0\n",
            "6,clock,65535,0,110,11\n",
            "7,end,65535,7,0,0\n",
        );
        let r = read_warmed(
            text,
            "frame,game_ms,stage,wall_ms\n10,100,4,1\n11,110,4,1\n",
        )
        .unwrap();
        assert_eq!(
            r.settings.into_iter().collect::<Vec<_>>(),
            [(5, 810, 3), (5, 900, 3)]
        );
        assert_eq!(
            r.schedules.into_iter().collect::<Vec<_>>(),
            [(4294967297, 10)]
        );
        assert_eq!(r.measured_updates, 2);
    }
    fn read_warmed(text: &str, frames: &str) -> Result<Report, String> {
        super::read_warmed(std::io::Cursor::new(text), frames)
    }
    #[test]
    fn warmed_window_uses_wall_time_when_game_clock_is_stationary() {
        let text = concat!(
            "ogsr-service,1\n",
            "us,kind,id,generation,value,flags\n",
            "0,register,1,1,0,12\n",
            "1,enter,1,1,0,12\n",
            "2,clock,65535,0,100,10\n",
            "3,visit,1,1,0,12\n",
            "1000002,clock,65535,0,100,11\n",
            "1000003,end,65535,5,0,0\n",
        );
        let r = read_warmed(
            text,
            "frame,game_ms,stage,wall_ms\n10,100,4,1\n11,100,4,1000\n",
        )
        .unwrap();
        assert_eq!(r.window, Some((2, 1000002)));
        assert_eq!(r.samples["first_visit_us"][0].0, 2);
        assert!(r
            .waits
            .iter()
            .any(|w| w.contains("1, 1, revisit, 999999, window_end")));
    }
    #[test]
    fn warmed_window_preserves_old_unfinished_waits_and_excludes_loading_samples() {
        let text = concat!(
            "ogsr-service,1\n",
            "us,kind,id,generation,value,flags\n",
            "0,register,1,1,0,12\n",
            "1,enter,1,1,0,12\n",
            "2,visit,1,1,0,12\n",
            "3,register,2,1,0,12\n",
            "4,enter,2,1,0,12\n",
            "10,clock,65535,0,100,10\n",
            "11,visit,1,1,0,12\n",
            "20,clock,65535,0,110,11\n",
            "21,visit,1,1,0,12\n",
            "30,clock,65535,0,120,12\n",
            "40,end,65535,10,0,0\n",
        );
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
        let text = concat!(
            "ogsr-service,1\n",
            "us,kind,id,generation,value,flags\n",
            "0,clock,65535,0,100,10\n",
            "10,clock,65535,0,110,11\n",
            "20,end,65535,2,0,0\n",
        );
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
