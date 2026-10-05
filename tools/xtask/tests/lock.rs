use std::{
    fs,
    io::{BufRead, BufReader, Write},
    process::{Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

#[test]
#[ignore = "child process for the termination test"]
fn lock_owner() {
    let path = std::env::var_os("OGSR_TEST_LOCK").expect("child lock path");
    let _lock = xtask::validation_lock(std::path::Path::new(&path)).unwrap();
    println!("LOCK_READY");
    std::io::stdout().flush().unwrap();
    loop {
        std::thread::park();
    }
}

#[test]
fn lock_is_exclusive_and_recovers_after_termination() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!("ogsr-lock-{}-{unique}", std::process::id()));
    let mut child = Command::new(std::env::current_exe().unwrap())
        .args(["--exact", "lock_owner", "--ignored", "--nocapture"])
        .env("OGSR_TEST_LOCK", &path)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut ready = false;
    for line in BufReader::new(child.stdout.take().unwrap()).lines() {
        if line.unwrap().contains("LOCK_READY") {
            ready = true;
            break;
        }
    }
    let competing = xtask::validation_lock(&path);
    child.kill().unwrap();
    child.wait().unwrap();
    assert!(
        ready && competing.is_err(),
        "the second owner must be rejected"
    );
    let recovered = xtask::validation_lock(&path).expect("dead owner's lock must be released");
    drop(recovered);
    fs::remove_file(path).unwrap();
}
