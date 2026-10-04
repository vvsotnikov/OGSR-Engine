use std::{
    fs::{File, OpenOptions},
    io,
    path::Path,
};

pub mod snapshot;

/// Keep the handle alive for the entire validation. The OS releases the lock
/// even when the owner is terminated; the persistent file is not a sentinel.
pub fn validation_lock(path: &Path) -> io::Result<File> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path)?;
    file.try_lock().map_err(io::Error::other)?;
    Ok(file)
}
