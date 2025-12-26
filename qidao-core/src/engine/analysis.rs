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
    pub rules: String,
    pub komi: f64,
    pub board_x_size: u32,
    pub board_y_size: u32,
    pub analyze_turns: Vec<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_visits: Option<u32>,
}

pub struct AnalysisClient {
    child: Child,
    stdin: tokio::process::ChildStdin,
    stdout_reader: BufReader<tokio::process::ChildStdout>,
}

impl AnalysisClient {
    pub async fn start(executable: &str, args: &[String]) -> Result<Self> {
        let mut child = Command::new(executable)
            .args(args)
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

    pub async fn stop(mut self) -> Result<()> {
        drop(self.stdin);
        let _ = self.child.wait().await?;
        Ok(())
    }
}
