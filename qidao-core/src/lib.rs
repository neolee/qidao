uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn add(a: u32, b: u32) -> u32 {
    a + b
}

#[derive(uniffi::Record)]
pub struct GameInfo {
    pub black_player: String,
    pub white_player: String,
    pub komi: f64,
}

#[uniffi::export]
pub fn get_sample_game() -> GameInfo {
    GameInfo {
        black_player: "Player 1".to_string(),
        white_player: "Player 2".to_string(),
        komi: 7.5,
    }
}
