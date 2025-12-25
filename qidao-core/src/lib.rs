uniffi::setup_scaffolding!();

use sgf_parse::{go::{parse, Prop}, SgfNode as ParserNode, SgfProp};
use std::sync::Arc;
use thiserror::Error;

#[derive(uniffi::Record)]
pub struct GameInfo {
    pub black_player: String,
    pub white_player: String,
    pub komi: f64,
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
    pub properties: Vec<SgfProperty>,
    pub children: Mutex<Vec<Arc<SgfNode>>>,
}

#[uniffi::export]
impl SgfNode {
    pub fn get_properties(&self) -> Vec<SgfProperty> {
        self.properties.clone()
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
        properties,
        children: Mutex::new(children)
    })
}

fn serialize_node(node: &Arc<SgfNode>, out: &mut String) {
    out.push(';');
    for prop in &node.properties {
        out.push_str(&prop.identifier);
        for val in &prop.values {
            out.push('[');
            // Basic escaping
            out.push_str(&val.replace('\\', "\\\\").replace(']', "\\]"));
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
    let trees = parse(&sgf_content).map_err(|e| SgfError::ParseError {
        message: e.to_string(),
    })?;

    if let Some(first_tree) = trees.iter().next() {
        Ok(Arc::new(SgfTree {
            root: convert_node(first_tree),
        }))
    } else {
        Err(SgfError::ParseError { message: "No tree found in SGF".to_string() })
    }
}

#[uniffi::export]
pub fn get_sample_game() -> GameInfo {
    GameInfo {
        black_player: "Player 1".to_string(),
        white_player: "Player 2".to_string(),
        komi: 7.5,
        size: 19,
    }
}

// --- Game Controller ---

use std::sync::Mutex;

#[derive(uniffi::Object)]
pub struct Game {
    state: Mutex<GameState>,
}

struct GameState {
    root: Arc<SgfNode>,
    current_node: Arc<SgfNode>,
    history: Vec<Arc<SgfNode>>,
    board_cache: std::collections::HashMap<usize, Arc<Board>>,
    size: u32,
}

#[uniffi::export]
impl Game {
    #[uniffi::constructor]
    pub fn new(size: u32) -> Arc<Self> {
        let root = Arc::new(SgfNode {
            properties: vec![SgfProperty {
                identifier: "SZ".to_string(),
                values: vec![size.to_string()],
            }],
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
        let size = root.properties.iter()
            .find(|p| p.identifier == "SZ")
            .and_then(|p| p.values.first())
            .and_then(|v| v.parse::<u32>().ok())
            .unwrap_or(19);

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

    pub fn to_sgf(&self) -> String {
        let state = self.state.lock().unwrap();
        let mut out = String::from("(");
        serialize_node(&state.root, &mut out);
        out.push(')');
        out
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
            for prop in &node.properties {
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

    pub fn get_next_color(&self) -> StoneColor {
        let state = self.state.lock().unwrap();
        // Simple heuristic: if last move was Black, next is White.
        // In a real SGF, we'd check the properties of the current node.
        for prop in &state.current_node.properties {
            if prop.identifier == "B" { return StoneColor::White; }
            if prop.identifier == "W" { return StoneColor::Black; }
        }
        // Default to Black for root or if no move property found
        StoneColor::Black
    }

    pub fn get_last_move(&self) -> Option<SgfProperty> {
        let state = self.state.lock().unwrap();
        state.current_node.properties.iter()
            .find(|p| p.identifier == "B" || p.identifier == "W")
            .cloned()
    }

    pub fn get_current_path_moves(&self) -> Vec<SgfProperty> {
        let state = self.state.lock().unwrap();
        let mut moves = Vec::new();

        // Add moves from history
        for node in &state.history {
            if let Some(prop) = node.properties.iter().find(|p| p.identifier == "B" || p.identifier == "W") {
                moves.push(prop.clone());
            }
        }

        // Add move from current node
        if let Some(prop) = state.current_node.properties.iter().find(|p| p.identifier == "B" || p.identifier == "W") {
            moves.push(prop.clone());
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
                c.properties.iter().any(|p| p.identifier == prop_id && p.values.contains(&coords))
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
            properties: vec![SgfProperty {
                identifier: prop_id.to_string(),
                values: vec![coords],
            }],
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
