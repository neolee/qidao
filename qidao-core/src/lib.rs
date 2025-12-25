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
    pub children: Vec<Arc<SgfNode>>,
}

#[uniffi::export]
impl SgfNode {
    pub fn get_properties(&self) -> Vec<SgfProperty> {
        self.properties.clone()
    }

    pub fn get_children(&self) -> Vec<Arc<SgfNode>> {
        self.children.clone()
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

    Arc::new(SgfNode { properties, children })
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
