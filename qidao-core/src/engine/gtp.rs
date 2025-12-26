use std::process::Stdio;
use tokio::process::{Command, Child};
use tokio::io::{BufReader, AsyncBufReadExt, AsyncWriteExt};
use anyhow::{Result, anyhow};

pub struct GtpClient {
    child: Child,
    stdin: tokio::process::ChildStdin,
    stdout_reader: BufReader<tokio::process::ChildStdout>,
}

impl GtpClient {
    pub async fn start(executable: &str, args: &[String]) -> Result<Self> {
        let mut child = Command::new(executable)
            .args(args)
            .current_dir(std::env::temp_dir())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .kill_on_drop(true)
            .spawn()?;

        let stdin = child.stdin.take().ok_or_else(|| anyhow!("Failed to open stdin"))?;
        let stdout = child.stdout.take().ok_or_else(|| anyhow!("Failed to open stdout"))?;
        let stdout_reader = BufReader::new(stdout);

        Ok(Self {
            child,
            stdin,
            stdout_reader,
        })
    }

    pub async fn send_command(&mut self, cmd: &str) -> Result<String> {
        let cmd_line = format!("{}\n", cmd);
        self.stdin.write_all(cmd_line.as_bytes()).await?;
        self.stdin.flush().await?;

        let mut response = String::new();
        loop {
            let mut line = String::new();
            let n = self.stdout_reader.read_line(&mut line).await?;
            if n == 0 {
                return Err(anyhow!("Engine closed stdout"));
            }
            if line.trim().is_empty() {
                if !response.is_empty() {
                    break;
                }
                continue;
            }
            response.push_str(&line);
        }
        
        if response.starts_with('=') {
            Ok(response[1..].trim().to_string())
        } else if response.starts_with('?') {
            Err(anyhow!("GTP Error: {}", response[1..].trim()))
        } else {
            Ok(response.trim().to_string())
        }
    }

    pub async fn stop(mut self) -> Result<()> {
        let _ = self.send_command("quit").await;
        let _ = self.child.wait().await?;
        Ok(())
    }
}
