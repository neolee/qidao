use std::process::Stdio;
use tokio::process::{Command, Child};
use tokio::io::{BufReader, AsyncBufReadExt, AsyncWriteExt};
use anyhow::{Result, anyhow};
use serde::{Serialize, Deserialize};
use serde_json::Value;

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AnalysisQuery {
    pub id: String,
    pub moves: Vec<(String, String)>, // (color, move)
    pub initial_stones: Vec<(String, String)>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub initial_player: Option<String>,
    pub rules: String,
    pub komi: f64,
    pub board_x_size: u32,
    pub board_y_size: u32,
    pub analyze_turns: Vec<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_visits: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub report_during_search_every: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub include_ownership: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub include_policy: Option<bool>,
}

pub struct AnalysisClient {
    child: Child,
    stdin: tokio::process::ChildStdin,
    stdout_reader: BufReader<tokio::process::ChildStdout>,
    stderr_reader: BufReader<tokio::process::ChildStderr>,
}

impl AnalysisClient {
    pub async fn start(executable: &str, args: &[String]) -> Result<Self> {
        let mut child = Command::new(executable)
            .args(args)
            .current_dir(std::env::temp_dir())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()?;

        let stdin = child.stdin.take().ok_or_else(|| anyhow!("Failed to open stdin"))?;
        let stdout = child.stdout.take().ok_or_else(|| anyhow!("Failed to open stdout"))?;
        let stderr = child.stderr.take().ok_or_else(|| anyhow!("Failed to open stderr"))?;
        let stdout_reader = BufReader::new(stdout);
        let stderr_reader = BufReader::new(stderr);

        Ok(Self {
            child,
            stdin,
            stdout_reader,
            stderr_reader,
        })
    }

    pub async fn send_query(&mut self, query: &AnalysisQuery) -> Result<()> {
        let json = serde_json::to_string(query)?;
        let line = format!("{}\n", json);
        self.stdin.write_all(line.as_bytes()).await?;
        self.stdin.flush().await?;
        Ok(())
    }

    pub async fn read_response(&mut self) -> Result<Value> {
        let mut line = String::new();
        let n = self.stdout_reader.read_line(&mut line).await?;
        if n == 0 {
            return Err(anyhow!("Engine closed stdout"));
        }
        let val: Value = serde_json::from_str(&line)?;
        Ok(val)
    }

    pub async fn read_stderr_line(&mut self) -> Result<Option<String>> {
        let mut line = String::new();
        // Use a timeout or non-blocking read if possible, but for now let's try a simple read_line
        // Actually, we want to read whatever is available.
        // For simplicity in this async context, we'll just read one line.
        match tokio::time::timeout(std::time::Duration::from_millis(10), self.stderr_reader.read_line(&mut line)).await {
            Ok(Ok(n)) if n > 0 => Ok(Some(line.trim().to_string())),
            _ => Ok(None),
        }
    }

    pub async fn stop(mut self) -> Result<()> {
        drop(self.stdin);
        let _ = self.child.wait().await?;
        Ok(())
    }
}
