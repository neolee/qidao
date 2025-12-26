uniffi::setup_scaffolding!();

use sgf_parse::{go::{parse, Prop}, SgfNode as ParserNode, SgfProp};
use std::sync::{Arc, Mutex, OnceLock};
use thiserror::Error;
use tokio::runtime::Runtime;

pub mod engine;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();

fn get_runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("Failed to create Tokio runtime")
    })
}

#[derive(uniffi::Record, Clone, Default)]
pub struct GameMetadata {
    pub black_name: String,
    pub black_rank: String,
    pub white_name: String,
    pub white_rank: String,
    pub komi: f64,
    pub result: String,
    pub date: String,
    pub event: String,
    pub game_name: String,
    pub place: String,
    pub size: u32,
}

#[derive(uniffi::Record, Clone)]
pub struct SgfProperty {
    pub identifier: String,
    pub values: Vec<String>,
}

#[uniffi::export]
pub fn add(a: u32, b: u32) -> u32 {
    a + b
}

#[derive(Debug, Error, uniffi::Error)]
pub enum SgfError {
    #[error("Parse error: {message}")]
    ParseError { message: String },
}

#[derive(uniffi::Object)]
pub struct SgfNode {
    pub properties: Mutex<Vec<SgfProperty>>,
    pub children: Mutex<Vec<Arc<SgfNode>>>,
}

#[uniffi::export]
impl SgfNode {
    pub fn get_id(&self) -> String {
        format!("{:p}", self)
    }

    pub fn get_properties(&self) -> Vec<SgfProperty> {
        self.properties.lock().unwrap().clone()
    }

    pub fn get_children(&self) -> Vec<Arc<SgfNode>> {
        self.children.lock().unwrap().clone()
    }
}

#[derive(uniffi::Object)]
pub struct SgfTree {
    pub root: Arc<SgfNode>,
}

#[uniffi::export]
impl SgfTree {
    pub fn root(&self) -> Arc<SgfNode> {
        self.root.clone()
    }
}

// --- Go Rules Engine ---

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum StoneColor {
    Black,
    White,
}

impl StoneColor {
    pub fn opponent(&self) -> Self {
        match self {
            Self::Black => Self::White,
            Self::White => Self::Black,
        }
    }
}

#[derive(uniffi::Object)]
pub struct Board {
    size: u32,
    grid: Vec<Option<StoneColor>>, // Flat array for performance
    last_captured_pos: Option<(u32, u32)>, // Simple Ko support
}

#[uniffi::export]
impl Board {
    #[uniffi::constructor]
    pub fn new(size: u32) -> Arc<Self> {
        Arc::new(Self {
            size,
            grid: vec![None; (size * size) as usize],
            last_captured_pos: None,
        })
    }

    pub fn get_size(&self) -> u32 {
        self.size
    }

    pub fn get_stone(&self, x: u32, y: u32) -> Option<StoneColor> {
        if x >= self.size || y >= self.size {
            return None;
        }
        self.grid[(y * self.size + x) as usize]
    }

    /// Attempts to place a stone. Returns true if successful.
    pub fn place_stone(&self, x: u32, y: u32, color: StoneColor) -> Result<Arc<Board>, SgfError> {
        if x >= self.size || y >= self.size {
            return Err(SgfError::ParseError { message: "Out of bounds".into() });
        }
        if self.get_stone(x, y).is_some() {
            return Err(SgfError::ParseError { message: "Position occupied".into() });
        }

        let mut new_grid = self.grid.clone();
        let idx = (y * self.size + x) as usize;
        new_grid[idx] = Some(color);

        // 1. Check for captures of opponent
        let opponent = color.opponent();
        let mut captured_any = false;
        let mut last_cap = None;
        let mut capture_count = 0;

        for (nx, ny) in self.neighbors(x, y) {
            if new_grid[(ny * self.size + nx) as usize] == Some(opponent) {
                if self.count_liberties(&new_grid, nx, ny) == 0 {
                    let captured = self.get_group(&new_grid, nx, ny);
                    capture_count += captured.len();
                    for (cx, cy) in &captured {
                        new_grid[(cy * self.size + cx) as usize] = None;
                        last_cap = Some((*cx, *cy));
                    }
                    captured_any = true;
                }
            }
        }

        // 2. Check for suicide (unless it captures)
        if !captured_any && self.count_liberties(&new_grid, x, y) == 0 {
            return Err(SgfError::ParseError { message: "Suicide move".into() });
        }

        // 3. Simple Ko check (if exactly one stone was captured)
        if capture_count == 1 {
            if let Some(pos) = self.last_captured_pos {
                if pos == (x, y) {
                    return Err(SgfError::ParseError { message: "Ko violation".into() });
                }
            }
        } else {
            last_cap = None;
        }

        Ok(Arc::new(Board {
            size: self.size,
            grid: new_grid,
            last_captured_pos: last_cap,
        }))
    }
}

impl Board {
    fn neighbors(&self, x: u32, y: u32) -> Vec<(u32, u32)> {
        let mut n = Vec::new();
        if x > 0 { n.push((x - 1, y)); }
        if x < self.size - 1 { n.push((x + 1, y)); }
        if y > 0 { n.push((x, y - 1)); }
        if y < self.size - 1 { n.push((x, y + 1)); }
        n
    }

    fn get_group(&self, grid: &[Option<StoneColor>], x: u32, y: u32) -> Vec<(u32, u32)> {
        let color = grid[(y * self.size + x) as usize];
        let mut group = Vec::new();
        let mut stack = vec![(x, y)];
        let mut visited = std::collections::HashSet::new();

        while let Some((cx, cy)) = stack.pop() {
            if !visited.insert((cx, cy)) { continue; }
            if grid[(cy * self.size + cx) as usize] == color {
                group.push((cx, cy));
                for (nx, ny) in self.neighbors(cx, cy) {
                    stack.push((nx, ny));
                }
            }
        }
        group
    }

    fn count_liberties(&self, grid: &[Option<StoneColor>], x: u32, y: u32) -> u32 {
        let color = grid[(y * self.size + x) as usize];
        let mut liberties = std::collections::HashSet::new();
        let mut stack = vec![(x, y)];
        let mut visited = std::collections::HashSet::new();

        while let Some((cx, cy)) = stack.pop() {
            if !visited.insert((cx, cy)) { continue; }
            if grid[(cy * self.size + cx) as usize] == color {
                for (nx, ny) in self.neighbors(cx, cy) {
                    stack.push((nx, ny));
                }
            } else if grid[(cy * self.size + cx) as usize].is_none() {
                liberties.insert((cx, cy));
            }
        }
        liberties.len() as u32
    }
}

fn sgf_to_gtp(sgf_coord: &str, size: u32) -> String {
    if sgf_coord.is_empty() {
        return "pass".to_string();
    }
    let chars: Vec<char> = sgf_coord.chars().collect();
    if chars.len() < 2 {
        return "pass".to_string();
    }
    
    let x = (chars[0] as u32).saturating_sub('a' as u32);
    let y = (chars[1] as u32).saturating_sub('a' as u32);
    
    if x >= size || y >= size {
        return "pass".to_string();
    }

    let col_char = if x < 8 {
        (b'A' + x as u8) as char
    } else {
        (b'A' + x as u8 + 1) as char // Skip 'I'
    };
    
    let row = size - y;
    format!("{}{}", col_char, row)
}

fn convert_node(node: &ParserNode<Prop>) -> Arc<SgfNode> {
    let properties = node.properties().map(|prop: &Prop| {
        let s = prop.to_string();
        let id = prop.identifier();

        let mut values = Vec::new();
        let mut current_value = String::new();
        let mut in_brackets = false;
        let mut escaped = false;

        // s is "ID[val1][val2]"
        for c in s.chars().skip(id.len()) {
            if escaped {
                current_value.push(c);
                escaped = false;
            } else if c == '\\' {
                escaped = true;
            } else if c == '[' {
                if in_brackets {
                    current_value.push(c);
                } else {
                    in_brackets = true;
                }
            } else if c == ']' {
                if escaped {
                    current_value.push(c);
                    escaped = false;
                } else {
                    values.push(current_value.clone());
                    current_value.clear();
                    in_brackets = false;
                }
            } else {
                current_value.push(c);
            }
        }

        SgfProperty {
            identifier: id,
            values,
        }
    }).collect();

    let children = node.children().map(|c| convert_node(c)).collect();

    Arc::new(SgfNode {
        properties: Mutex::new(properties),
        children: Mutex::new(children)
    })
}

fn serialize_node(node: &Arc<SgfNode>, out: &mut String) {
    out.push(';');
    let props = node.properties.lock().unwrap();
    for prop in props.iter() {
        out.push_str(&prop.identifier);
        for val in &prop.values {
            out.push('[');
            // Basic escaping
            let escaped = val.replace('\\', "\\\\").replace(']', "\\]");
            out.push_str(&escaped);
            out.push(']');
        }
    }

    let children = node.children.lock().unwrap();
    if children.len() == 1 {
        serialize_node(&children[0], out);
    } else {
        for child in children.iter() {
            out.push('(');
            serialize_node(child, out);
            out.push(')');
        }
    }
}

#[uniffi::export]
pub fn parse_sgf(sgf_content: String) -> Result<Arc<SgfTree>, SgfError> {
    let trimmed = sgf_content.trim().trim_matches('\0').trim().to_string();
    if trimmed.is_empty() {
        return Err(SgfError::ParseError { message: "Empty SGF content".to_string() });
    }

    // Try parsing normally first
    match parse(&trimmed) {
        Ok(trees) => {
            if let Some(first_tree) = trees.iter().next() {
                Ok(Arc::new(SgfTree {
                    root: convert_node(first_tree),
                }))
            } else {
                Err(SgfError::ParseError { message: "No tree found in SGF".to_string() })
            }
        }
        Err(e) => {
            // If it fails, try to "fix" it if it looks truncated
            // This is a common issue with some SGF sources

            // Try different combinations of closing brackets and parentheses
            for brackets in 0..3 {
                let mut base = trimmed.clone();
                for _ in 0..brackets {
                    base.push(']');
                }

                for parens in 1..10 {
                    let mut attempt = base.clone();
                    for _ in 0..parens {
                        attempt.push(')');
                    }

                    if let Ok(trees) = parse(&attempt) {
                        if let Some(first_tree) = trees.iter().next() {
                            return Ok(Arc::new(SgfTree {
                                root: convert_node(first_tree),
                            }));
                        }
                    }
                }
            }

            Err(SgfError::ParseError { message: e.to_string() })
        }
    }
}

struct GameState {
    root: Arc<SgfNode>,
    current_node: Arc<SgfNode>,
    history: Vec<Arc<SgfNode>>,
    board_cache: std::collections::HashMap<usize, Arc<Board>>,
    size: u32,
}

#[derive(uniffi::Object)]
pub struct Game {
    state: Mutex<GameState>,
}

#[uniffi::export]
impl Game {
    #[uniffi::constructor]
    pub fn new(size: u32) -> Arc<Self> {
        let root = Arc::new(SgfNode {
            properties: Mutex::new(vec![SgfProperty {
                identifier: "SZ".to_string(),
                values: vec![size.to_string()],
            }]),
            children: Mutex::new(vec![]),
        });

        let mut board_cache = std::collections::HashMap::new();
        board_cache.insert(Arc::as_ptr(&root) as usize, Board::new(size));

        Arc::new(Self {
            state: Mutex::new(GameState {
                root: root.clone(),
                current_node: root,
                history: vec![],
                board_cache,
                size,
            }),
        })
    }

    #[uniffi::constructor]
    pub fn from_sgf(sgf_content: String) -> Result<Arc<Self>, SgfError> {
        let tree = parse_sgf(sgf_content)?;
        let root = tree.root();

        // Try to find size
        let size = {
            let props = root.properties.lock().unwrap();
            props.iter()
                .find(|p| p.identifier == "SZ")
                .and_then(|p| p.values.first())
                .and_then(|v| v.parse::<u32>().ok())
                .unwrap_or(19)
        };

        let mut board_cache = std::collections::HashMap::new();
        board_cache.insert(Arc::as_ptr(&root) as usize, Board::new(size));

        Ok(Arc::new(Self {
            state: Mutex::new(GameState {
                root: root.clone(),
                current_node: root,
                history: vec![],
                board_cache,
                size,
            }),
        }))
    }

    pub fn get_metadata(&self) -> GameMetadata {
        let state = self.state.lock().unwrap();
        let props = state.root.properties.lock().unwrap();

        let mut meta = GameMetadata::default();
        meta.size = state.size;

        for p in props.iter() {
            match p.identifier.as_str() {
                "PB" => meta.black_name = p.values.first().cloned().unwrap_or_default(),
                "BR" => meta.black_rank = p.values.first().cloned().unwrap_or_default(),
                "PW" => meta.white_name = p.values.first().cloned().unwrap_or_default(),
                "WR" => meta.white_rank = p.values.first().cloned().unwrap_or_default(),
                "KM" => meta.komi = p.values.first().and_then(|v| v.parse().ok()).unwrap_or(0.0),
                "RE" => meta.result = p.values.first().cloned().unwrap_or_default(),
                "DT" => meta.date = p.values.first().cloned().unwrap_or_default(),
                "EV" => meta.event = p.values.first().cloned().unwrap_or_default(),
                "GN" => meta.game_name = p.values.first().cloned().unwrap_or_default(),
                "PC" => meta.place = p.values.first().cloned().unwrap_or_default(),
                _ => {}
            }
        }
        meta
    }

    pub fn get_current_node(&self) -> Arc<SgfNode> {
        self.state.lock().unwrap().current_node.clone()
    }

    pub fn get_root_node(&self) -> Arc<SgfNode> {
        self.state.lock().unwrap().root.clone()
    }

    pub fn get_current_variation_index(&self) -> u32 {
        let state = self.state.lock().unwrap();
        if let Some(parent) = state.history.last() {
            let children = parent.children.lock().unwrap();
            for (i, child) in children.iter().enumerate() {
                if Arc::ptr_eq(child, &state.current_node) {
                    return i as u32;
                }
            }
        }
        0
    }

    pub fn get_variation_count(&self) -> u32 {
        let state = self.state.lock().unwrap();
        if let Some(parent) = state.history.last() {
            return parent.children.lock().unwrap().len() as u32;
        }
        1
    }

    pub fn set_metadata(&self, metadata: GameMetadata) {
        let state = self.state.lock().unwrap();
        let mut props = state.root.properties.lock().unwrap();

        let updates = [
            ("PB", metadata.black_name),
            ("BR", metadata.black_rank),
            ("PW", metadata.white_name),
            ("WR", metadata.white_rank),
            ("KM", metadata.komi.to_string()),
            ("RE", metadata.result),
            ("DT", metadata.date),
            ("EV", metadata.event),
            ("GN", metadata.game_name),
            ("PC", metadata.place),
            ("SZ", metadata.size.to_string()),
        ];

        for (id, val) in updates {
            if let Some(p) = props.iter_mut().find(|p| p.identifier == id) {
                p.values = vec![val];
            } else {
                props.push(SgfProperty {
                    identifier: id.to_string(),
                    values: vec![val],
                });
            }
        }
    }

    pub fn to_sgf(&self) -> String {
        let state = self.state.lock().unwrap();
        let mut out = String::from("(");
        serialize_node(&state.root, &mut out);
        out.push(')');
        out
    }

    pub fn jump_to_node(&self, target: Arc<SgfNode>) {
        let mut state = self.state.lock().unwrap();
        if let Some(path) = find_path(&state.root, &target) {
            state.history = path;
            state.current_node = target;
        }
    }

    pub fn jump_to_move_number(&self, target: u32) {
        let mut state = self.state.lock().unwrap();
        if let Some((node, path)) = find_node_at_depth(&state.root, target, vec![]) {
            state.current_node = node;
            state.history = path;
        }
    }

    pub fn get_board(&self) -> Arc<Board> {
        let mut state = self.state.lock().unwrap();
        let current_ptr = Arc::as_ptr(&state.current_node) as usize;

        if let Some(board) = state.board_cache.get(&current_ptr) {
            return board.clone();
        }

        // If not in cache, we must compute it from the path.
        // This can happen after loading an SGF or jumping to a node.
        let mut path = state.history.clone();
        path.push(state.current_node.clone());

        let mut current_board = Board::new(state.size);
        for node in path {
            let node_ptr = Arc::as_ptr(&node) as usize;
            if let Some(cached) = state.board_cache.get(&node_ptr) {
                current_board = cached.clone();
                continue;
            }

            // Apply moves in this node
            let props = node.properties.lock().unwrap();
            for prop in props.iter() {
                let color = if prop.identifier == "B" { Some(StoneColor::Black) }
                           else if prop.identifier == "W" { Some(StoneColor::White) }
                           else { None };

                if let Some(c) = color {
                    if let Some(coords) = prop.values.first() {
                        if coords.len() == 2 {
                            let x = coords.as_bytes()[0] as i32 - 'a' as i32;
                            let y = coords.as_bytes()[1] as i32 - 'a' as i32;
                            if let Ok(next_board) = current_board.place_stone(x as u32, y as u32, c) {
                                current_board = next_board;
                            }
                        }
                    }
                }
            }
            state.board_cache.insert(node_ptr, current_board.clone());
        }

        current_board
    }

    pub fn get_move_count(&self) -> u32 {
        self.state.lock().unwrap().history.len() as u32
    }

    pub fn get_max_move_count(&self) -> u32 {
        let state = self.state.lock().unwrap();
        get_max_depth(&state.root)
    }

    pub fn get_next_color(&self) -> StoneColor {
        let state = self.state.lock().unwrap();
        // Simple heuristic: if last move was Black, next is White.
        // In a real SGF, we'd check the properties of the current node.
        let props = state.current_node.properties.lock().unwrap();
        for prop in props.iter() {
            if prop.identifier == "B" { return StoneColor::White; }
            if prop.identifier == "W" { return StoneColor::Black; }
        }
        // Default to Black for root or if no move property found
        StoneColor::Black
    }

    pub fn get_last_move(&self) -> Option<SgfProperty> {
        let state = self.state.lock().unwrap();
        let props = state.current_node.properties.lock().unwrap();
        props.iter()
            .find(|p| p.identifier == "B" || p.identifier == "W")
            .cloned()
    }

    pub fn get_current_path_moves(&self) -> Vec<SgfProperty> {
        let state = self.state.lock().unwrap();
        let mut moves = Vec::new();

        // Add moves from history
        for node in &state.history {
            let props = node.properties.lock().unwrap();
            if let Some(prop) = props.iter().find(|p| p.identifier == "B" || p.identifier == "W") {
                moves.push(prop.clone());
            }
        }

        // Add move from current node
        let props = state.current_node.properties.lock().unwrap();
        if let Some(prop) = props.iter().find(|p| p.identifier == "B" || p.identifier == "W") {
            moves.push(prop.clone());
        }

        moves
    }

    pub fn get_analysis_moves(&self) -> Vec<Vec<String>> {
        let state = self.state.lock().unwrap();
        let size = state.size;
        let mut path = state.history.clone();
        path.push(state.current_node.clone());
        
        let mut moves = Vec::new();
        for node in path {
            let props = node.properties.lock().unwrap();
            for prop in props.iter() {
                if prop.identifier == "B" || prop.identifier == "W" {
                    if let Some(val) = prop.values.first() {
                        let gtp_move = sgf_to_gtp(val, size);
                        moves.push(vec![prop.identifier.clone(), gtp_move]);
                    }
                }
            }
        }
        moves
    }

    pub fn can_go_back(&self) -> bool {
        !self.state.lock().unwrap().history.is_empty()
    }

    pub fn can_go_forward(&self) -> bool {
        !self.state.lock().unwrap().current_node.children.lock().unwrap().is_empty()
    }

    pub fn go_back(&self) -> bool {
        let mut state = self.state.lock().unwrap();
        if let Some(prev) = state.history.pop() {
            state.current_node = prev;
            true
        } else {
            false
        }
    }

    pub fn go_forward(&self, index: u32) -> bool {
        let mut state = self.state.lock().unwrap();
        let children = state.current_node.children.lock().unwrap();
        let child = children.get(index as usize).cloned();
        drop(children); // Release lock before mutating state

        if let Some(child) = child {
            let current = state.current_node.clone();
            state.history.push(current);
            state.current_node = child;
            true
        } else {
            false
        }
    }

    pub fn place_stone(&self, x: u32, y: u32, color: StoneColor) -> Result<(), SgfError> {
        let mut state = self.state.lock().unwrap();

        // 1. Check if this move already exists as a child
        let coords = format!("{}{}",
            (b'a' + x as u8) as char,
            (b'a' + y as u8) as char
        );
        let prop_id = match color {
            StoneColor::Black => "B",
            StoneColor::White => "W",
        };

        let existing_child = {
            let children = state.current_node.children.lock().unwrap();
            children.iter().find(|c| {
                let props = c.properties.lock().unwrap();
                props.iter().any(|p| p.identifier == prop_id && p.values.contains(&coords))
            }).cloned()
        };

        if let Some(child) = existing_child {
            // Move to existing child
            let current = state.current_node.clone();
            state.history.push(current);
            state.current_node = child;
            return Ok(());
        }

        // 2. Create new move
        let current_board = state.board_cache.get(&(Arc::as_ptr(&state.current_node) as usize))
            .cloned()
            .unwrap_or_else(|| Board::new(state.size));

        let new_board = current_board.place_stone(x, y, color)?;

        let new_node = Arc::new(SgfNode {
            properties: Mutex::new(vec![SgfProperty {
                identifier: prop_id.to_string(),
                values: vec![coords],
            }]),
            children: Mutex::new(vec![]),
        });

        // Attach to tree
        state.current_node.children.lock().unwrap().push(new_node.clone());

        // Update state
        let current = state.current_node.clone();
        state.history.push(current);
        state.current_node = new_node.clone();
        state.board_cache.insert(Arc::as_ptr(&new_node) as usize, new_board);

        Ok(())
    }
}

fn find_path(current: &Arc<SgfNode>, target: &Arc<SgfNode>) -> Option<Vec<Arc<SgfNode>>> {
    if Arc::ptr_eq(current, target) {
        return Some(vec![]);
    }

    let children = current.children.lock().unwrap();
    for child in children.iter() {
        if let Some(mut path) = find_path(child, target) {
            let mut full_path = vec![current.clone()];
            full_path.append(&mut path);
            return Some(full_path);
        }
    }
    None
}

fn get_max_depth(node: &Arc<SgfNode>) -> u32 {
    let children = node.children.lock().unwrap();
    if children.is_empty() {
        0
    } else {
        1 + children.iter().map(|c| get_max_depth(c)).max().unwrap_or(0)
    }
}

fn find_node_at_depth(current: &Arc<SgfNode>, target: u32, path: Vec<Arc<SgfNode>>) -> Option<(Arc<SgfNode>, Vec<Arc<SgfNode>>)> {
    if path.len() as u32 == target {
        return Some((current.clone(), path));
    }

    let children = current.children.lock().unwrap();
    for child in children.iter() {
        let mut next_path = path.clone();
        next_path.push(current.clone());
        if let Some(result) = find_node_at_depth(child, target, next_path) {
            return Some(result);
        }
    }
    None
}

// --- Engine UniFFI Wrappers ---

#[derive(uniffi::Record, Clone)]
pub struct GtpResponse {
    pub success: bool,
    pub text: String,
}

#[derive(uniffi::Object)]
pub struct GtpEngine {
    client: Arc<tokio::sync::Mutex<Option<engine::GtpClient>>>,
}

#[uniffi::export]
impl GtpEngine {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            client: Arc::new(tokio::sync::Mutex::new(None)),
        })
    }

    pub async fn start(&self, executable: String, args: Vec<String>) -> Result<(), SgfError> {
        let client = get_runtime().spawn(async move {
            engine::GtpClient::start(&executable, &args).await
        }).await
            .map_err(|e| SgfError::ParseError { message: format!("Task join error: {}", e) })?
            .map_err(|e| SgfError::ParseError { message: e.to_string() })?;
        let mut lock = self.client.lock().await;
        *lock = Some(client);
        Ok(())
    }

    pub async fn send_command(&self, cmd: String) -> Result<String, SgfError> {
        let mut lock = self.client.lock().await;
        let mut client = lock.take().ok_or_else(|| SgfError::ParseError { message: "Engine not started".into() })?;
        
        let (client, result) = get_runtime().spawn(async move {
            let res = client.send_command(&cmd).await;
            (client, res)
        }).await.map_err(|e| SgfError::ParseError { message: e.to_string() })?;
        
        *lock = Some(client);
        result.map_err(|e| SgfError::ParseError { message: e.to_string() })
    }

    pub async fn stop(&self) -> Result<(), SgfError> {
        let mut lock = self.client.lock().await;
        if let Some(client) = lock.take() {
            get_runtime().spawn(async move {
                client.stop().await
            }).await
                .map_err(|e| SgfError::ParseError { message: e.to_string() })?
                .map_err(|e| SgfError::ParseError { message: e.to_string() })?;
        }
        Ok(())
    }
}

#[derive(uniffi::Record, Clone)]
pub struct AnalysisMoveInfo {
    pub move_str: String,
    pub visits: u32,
    pub winrate: f64,
    pub score_lead: f64,
    pub pv: Vec<String>,
}

#[derive(uniffi::Record, Clone)]
pub struct AnalysisRootInfo {
    pub winrate: f64,
    pub score_lead: f64,
    pub visits: u32,
}

#[derive(uniffi::Record, Clone)]
pub struct AnalysisResult {
    pub id: String,
    pub turn_number: u32,
    pub root_info: AnalysisRootInfo,
    pub move_infos: Vec<AnalysisMoveInfo>,
}

#[derive(uniffi::Object)]
pub struct AnalysisEngine {
    client: Arc<tokio::sync::Mutex<Option<engine::AnalysisClient>>>,
}

#[uniffi::export]
impl AnalysisEngine {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            client: Arc::new(tokio::sync::Mutex::new(None)),
        })
    }

    pub async fn start(&self, executable: String, args: Vec<String>) -> Result<(), SgfError> {
        let client_mutex = Arc::clone(&self.client);
        get_runtime().spawn(async move {
            let client = engine::AnalysisClient::start(&executable, &args).await
                .map_err(|e| SgfError::ParseError { message: e.to_string() })?;
            let mut lock = client_mutex.lock().await;
            *lock = Some(client);
            Ok(())
        }).await
            .map_err(|e| SgfError::ParseError { message: format!("Task join error: {}", e) })?
    }

    pub async fn analyze(&self, query_json: String) -> Result<(), SgfError> {
        let client_mutex = Arc::clone(&self.client);
        get_runtime().spawn(async move {
            let mut lock = client_mutex.lock().await;
            let mut client = lock.take().ok_or_else(|| SgfError::ParseError { message: "Engine not started".into() })?;
            
            let query: engine::AnalysisQuery = serde_json::from_str(&query_json)
                .map_err(|e| SgfError::ParseError { message: e.to_string() })?;

            let res = client.send_query(&query).await;
            *lock = Some(client);
            res.map_err(|e| SgfError::ParseError { message: e.to_string() })
        }).await
            .map_err(|e| SgfError::ParseError { message: format!("Task join error: {}", e) })?
    }

    pub async fn get_next_result(&self) -> Result<AnalysisResult, SgfError> {
        let client_mutex = Arc::clone(&self.client);
        get_runtime().spawn(async move {
            let mut lock = client_mutex.lock().await;
            let mut client = lock.take().ok_or_else(|| SgfError::ParseError { message: "Engine not started".into() })?;
            
            // Use a longer timeout (2s) to wait for analysis results
            let result = match tokio::time::timeout(std::time::Duration::from_secs(2), client.read_response()).await {
                Ok(res) => res,
                Err(_) => {
                    *lock = Some(client);
                    return Err(SgfError::ParseError { message: "Timeout".into() });
                }
            };

            *lock = Some(client);
            
            let val = result.map_err(|e| SgfError::ParseError { message: e.to_string() })?;
            
            // Parse the complex KataGo JSON into our simpler Record
            let id = val["id"].as_str().unwrap_or("").to_string();
            let turn_number = val["turnNumber"].as_u64().unwrap_or(0) as u32;
            
            let root_info_val = &val["rootInfo"];
            let root_info = AnalysisRootInfo {
                winrate: root_info_val["winrate"].as_f64().unwrap_or(0.0),
                score_lead: root_info_val["scoreLead"].as_f64().unwrap_or(0.0),
                visits: root_info_val["visits"].as_u64().unwrap_or(0) as u32,
            };
            
            let mut move_infos = Vec::new();
            if let Some(moves) = val["moveInfos"].as_array() {
                for m in moves {
                    let mut pv = Vec::new();
                    if let Some(pv_arr) = m["pv"].as_array() {
                        for p in pv_arr {
                            if let Some(s) = p.as_str() {
                                pv.push(s.to_string());
                            }
                        }
                    }
                    move_infos.push(AnalysisMoveInfo {
                        move_str: m["move"].as_str().unwrap_or("").to_string(),
                        visits: m["visits"].as_u64().unwrap_or(0) as u32,
                        winrate: m["winrate"].as_f64().unwrap_or(0.0),
                        score_lead: m["scoreLead"].as_f64().unwrap_or(0.0),
                        pv,
                    });
                }
            }
            
            Ok(AnalysisResult {
                id,
                turn_number,
                root_info,
                move_infos,
            })
        }).await
            .map_err(|e| SgfError::ParseError { message: format!("Task join error: {}", e) })?
    }

    pub async fn get_logs(&self) -> Vec<String> {
        let client_mutex = Arc::clone(&self.client);
        get_runtime().spawn(async move {
            let mut lock = client_mutex.lock().await;
            let mut client = match lock.take() {
                Some(c) => c,
                None => return vec![],
            };

            let mut logs = Vec::new();
            // Try to read multiple lines if available
            for _ in 0..50 {
                match client.read_stderr_line().await {
                    Ok(Some(line)) => logs.push(line),
                    _ => break,
                }
            }

            *lock = Some(client);
            logs
        }).await.unwrap_or_default()
    }

    pub async fn stop(&self) -> Result<(), SgfError> {
        let client_mutex = Arc::clone(&self.client);
        get_runtime().spawn(async move {
            let mut lock = client_mutex.lock().await;
            if let Some(client) = lock.take() {
                let _ = client.stop().await;
            }
            Ok(())
        }).await
            .map_err(|e| SgfError::ParseError { message: format!("Task join error: {}", e) })?
    }
}
