use std::process::{Command, Stdio};
use std::io::{BufRead, BufReader, Write};
use serde_json::json;

fn main() -> anyhow::Result<()> {
    println!("Starting KataGo Analysis API test...");
    
    let mut child = Command::new("katago")
        .arg("analysis")
        .arg("-config")
        .arg("/opt/homebrew/share/go-engines/analysis.cfg")
        .arg("-model")
        .arg("/opt/homebrew/share/go-engines/kata1-b28c512nbt-s9435149568-d4923088660.bin.gz")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?;

    let mut stdin = child.stdin.take().expect("Failed to open stdin");
    let stdout = child.stdout.take().expect("Failed to open stdout");
    let mut reader = BufReader::new(stdout);

    // Example query: analyze an empty board
    let query = json!({
        "id": "test_query_1",
        "moves": [],
        "initialStones": [],
        "rules": "chinese",
        "komi": 7.5,
        "boardXSize": 19,
        "boardYSize": 19,
        "analyzeTurns": [0]
    });

    println!("Sending query: {}", query);
    writeln!(stdin, "{}", query.to_string())?;
    stdin.flush()?;

    let mut response = String::new();
    reader.read_line(&mut response)?;
    println!("Response:\n{}", response);

    // To quit the analysis engine, we just close stdin or kill the process
    drop(stdin);
    let _ = child.wait()?;
    println!("KataGo Analysis exited.");

    Ok(())
}
