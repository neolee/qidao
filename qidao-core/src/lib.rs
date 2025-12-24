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
