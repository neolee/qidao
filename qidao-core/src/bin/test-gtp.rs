use std::process::{Command, Stdio};
use std::io::{BufRead, BufReader, Write};

fn main() -> anyhow::Result<()> {
    println!("Starting KataGo GTP test...");
    
    let mut child = Command::new("katago")
        .arg("gtp")
        .arg("-config")
        .arg("/opt/homebrew/share/go-engines/gtp_default.cfg")
        .arg("-model")
        .arg("/opt/homebrew/share/go-engines/kata1-b28c512nbt-s9435149568-d4923088660.bin.gz")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?;

    let mut stdin = child.stdin.take().expect("Failed to open stdin");
    let stdout = child.stdout.take().expect("Failed to open stdout");
    let mut reader = BufReader::new(stdout);

    let commands = vec!["version", "protocol_version", "list_commands", "quit"];

    for cmd in commands {
        println!("Sending: {}", cmd);
        writeln!(stdin, "{}", cmd)?;
        stdin.flush()?;

        let mut response = String::new();
        loop {
            let mut line = String::new();
            reader.read_line(&mut line)?;
            if line.trim().is_empty() {
                break;
            }
            response.push_str(&line);
        }
        println!("Response:\n{}", response);
    }

    let status = child.wait()?;
    println!("KataGo exited with status: {}", status);

    Ok(())
}
