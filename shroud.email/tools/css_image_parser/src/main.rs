mod parser;

use std::io::{Read, Write};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Limits apply only to this disposable process, never to the delivery BEAM.
    limit_resources()?;
    let mut stdin = std::io::stdin().lock();
    let mut length = [0; 4];
    stdin.read_exact(&mut length)?;
    let length = u32::from_be_bytes(length) as usize;
    if length > 1024 * 1024 {
        return Err("css_too_large".into());
    }
    let mut source = vec![0; length];
    stdin.read_exact(&mut source)?;
    let source = String::from_utf8(source)?;
    let inline = std::env::args().nth(1).as_deref() == Some("inline");
    let result = std::panic::catch_unwind(|| parser::extract(&source, inline))
        .unwrap_or_else(|_| Err("parser_panicked".into()));
    let reply = match result {
        Ok(references) => serde_json::json!({"Ok": references}),
        Err(reason) => serde_json::json!({"Err": reason}),
    };
    std::io::stdout().write_all(&serde_json::to_vec(&reply)?)?;
    Ok(())
}

#[cfg(unix)]
fn limit_resources() -> std::io::Result<()> {
    // A wall-clock alarm also terminates helpers blocked on input or output.
    // SAFETY: SIGALRM's default action terminates only this disposable process.
    unsafe {
        libc::signal(libc::SIGALRM, libc::SIG_DFL);
        libc::alarm(3);
    }
    for (resource, limit) in [
        (libc::RLIMIT_AS, 256 * 1024 * 1024),
        (libc::RLIMIT_CPU, 2),
        (libc::RLIMIT_CORE, 0),
    ] {
        let limit = libc::rlimit {
            rlim_cur: limit,
            rlim_max: limit,
        };
        // SAFETY: limit points to an initialized rlimit, and resource is a libc constant.
        if unsafe { libc::setrlimit(resource, &limit) } != 0 {
            return Err(std::io::Error::last_os_error());
        }
    }
    Ok(())
}

#[cfg(not(unix))]
fn limit_resources() -> std::io::Result<()> {
    Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "resource_limits_unavailable",
    ))
}
