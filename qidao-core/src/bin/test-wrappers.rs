use qidao_core::{GtpEngine, AnalysisEngine};
use serde_json::json;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    println!("Testing GtpEngine wrapper...");
    let gtp = GtpEngine::new();
    let args = vec![
        "gtp".to_string(),
        "-config".to_string(),
        "/opt/homebrew/share/go-engines/gtp_default.cfg".to_string(),
        "-model".to_string(),
        "/opt/homebrew/share/go-engines/kata1-b28c512nbt-s9435149568-d4923088660.bin.gz".to_string(),
    ];
    
    gtp.start("katago".to_string(), args).await?;
    let version = gtp.send_command("version".to_string()).await?;
    println!("GTP Version: {}", version);
    gtp.stop().await?;
    println!("GTP Engine stopped.");

    println!("\nTesting AnalysisEngine wrapper...");
    let analysis = AnalysisEngine::new();
    let a_args = vec![
        "analysis".to_string(),
        "-config".to_string(),
        "/opt/homebrew/share/go-engines/analysis.cfg".to_string(),
        "-model".to_string(),
        "/opt/homebrew/share/go-engines/kata1-b28c512nbt-s9435149568-d4923088660.bin.gz".to_string(),
    ];
    
    analysis.start("katago".to_string(), a_args).await?;
    
    let query = json!({
        "id": "test_query_wrapper",
        "moves": [],
        "initialStones": [],
        "rules": "chinese",
        "komi": 7.5,
        "boardXSize": 19,
        "boardYSize": 19,
        "analyzeTurns": [0]
    });
    
    analysis.analyze(query.to_string()).await?;
    let result = analysis.get_next_result().await?;
    println!("Analysis Result ID: {}", result.id);
    println!("Winrate: {:.2}%", result.root_info.winrate * 100.0);
    println!("Score Lead: {:.2}", result.root_info.score_lead);
    println!("Top moves count: {}", result.move_infos.len());
    
    if let Some(m) = result.move_infos.first() {
        println!("Best move: {} (winrate: {:.2}%)", m.move_str, m.winrate * 100.0);
    }
    
    analysis.stop().await?;
    println!("Analysis Engine stopped.");

    Ok(())
}
