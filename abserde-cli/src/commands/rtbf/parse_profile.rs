use std::{fs, path::Path};

use anyhow::{Context, Result, anyhow, bail};
use full_moon::ast::{
    Ast, Call, Expression, Field, FunctionArgs, LastStmt, Prefix, Suffix, TableConstructor,
};
use serde::{Deserialize, Serialize};

pub const MAX_RTBF_TEMPLATES: usize = 100;

// Represents a single RTBF template entry for the open cloud configs api.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct UserDataTemplate {
    pub key_template: KeyTemplate,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct KeyTemplate {
    pub data_store_type: String,
    pub data_store_name: String,
    pub key_pattern: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scope_patten: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataStoresConfigPayload {
    pub entries: UserDataTemplates,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserDataTemplates {
    pub user_data_templates: Vec<UserDataTemplate>,
}

/// Parses an Abserde Profile file with full-moon, extracting all datastore RTBF templates
/// and appends them to the templates vector.
///
/// Returns an error if parsing fails, or the length of the vector exceeds
/// MAX_RTBF_TEMPLATES (100).
pub fn parse_profile_rtbf_templates(
    source: &Path,
    templates: &mut Vec<UserDataTemplate>,
) -> Result<()> {
    let source_code = fs::read_to_string(source)?;

    let ast = full_moon::parse(&source_code).map_err(|e| anyhow!("Failed to parse luau: {e:?}"))?;

    let profile_table =
        find_profile_constructor(&ast).context("Cound not find return `Abserde.Profile(...)`")?;

    // Extract 'Name', 'SlotLimit', and 'Keys' from the profile
    let profile_name_expr =
        find_field_in_table(profile_table, "Name").context("Profile missing 'Name' field.")?;
    let profile_name = extract_string_literal(profile_name_expr)
        .context("'Name' field in Abserde.Profile must be a string literal.")?;

    let slot_limit = find_field_in_table(profile_table, "SlotLimit")
        .and_then(extract_number_literal)
        .unwrap_or(1);

    let keys_expr =
        find_field_in_table(profile_table, "Keys").context("Profile missing 'Keys' field.")?;

    let keys_table = match keys_expr {
        Expression::TableConstructor(table) => table,
        _ => bail!("'Keys' field in Abserde.Profile must be a table literal"),
    };

    // Iterate over key definitions
    for field in keys_table.fields() {
        if let Field::NameKey { key, value, .. } = field {
            let key_name = key.token().to_string().trim().to_string();

            // Extract table inside Abserde.Key({ ... })
            let key_table = check_expr_is_abserde_call(value, "Key");
            let is_multislot = key_table
                .and_then(|tbl| find_field_in_table(tbl, "Multislot"))
                .and_then(extract_boolean_literal)
                .unwrap_or(false);

            let slots_to_generate = if is_multislot && slot_limit > 1 {
                slot_limit
            } else {
                1
            };

            for slot_idx in 0..slots_to_generate {
                let data_store_name = format!("{profile_name}_{key_name}{slot_idx}");

                templates.push(UserDataTemplate {
                    key_template: KeyTemplate {
                        data_store_type: "STANDARD".to_string(),
                        data_store_name,
                        key_pattern: "{UserId}".to_string(),
                        scope_patten: None,
                    },
                });

                if templates.len() > MAX_RTBF_TEMPLATES {
                    bail!("Exceeded maximum allowed RTBF templates ({MAX_RTBF_TEMPLATES}).");
                }
            }
        }
    }

    Ok(())
}

fn find_profile_constructor(ast: &Ast) -> Option<&TableConstructor> {
    if let Some(LastStmt::Return(ret)) = ast.nodes().last_stmt() {
        for expr in ret.returns() {
            if let Some(table) = check_expr_is_abserde_call(expr, "Profile") {
                return Some(table);
            }
        }
    }
    None
}

fn check_expr_is_abserde_call<'a>(
    expr: &'a Expression,
    func_name: &str,
) -> Option<&'a TableConstructor> {
    if let Expression::FunctionCall(func_call) = expr {
        let prefix_name = match func_call.prefix() {
            Prefix::Name(token) => token.token().to_string(),
            _ => return None,
        };

        if prefix_name.trim().to_lowercase() != "abserde" {
            return None;
        }

        let mut suffixes = func_call.suffixes();

        // First suffix: .Profile or .Key
        let first_suffix = suffixes.next()?;
        if let Suffix::Index(full_moon::ast::Index::Dot { name, .. }) = first_suffix {
            if name.token().to_string().trim() != func_name {
                return None;
            }
        } else {
            return None;
        }

        // Second suffix: ({ ... }) or { ... }
        let second_suffix = suffixes.next()?;
        if let Suffix::Call(call) = second_suffix {
            return extract_table_from_call(call);
        }
    }
    None
}

fn extract_table_from_call<'a>(call: &'a Call) -> Option<&'a TableConstructor> {
    match call {
        Call::AnonymousCall(FunctionArgs::Parentheses { arguments, .. }) => {
            if let Some(Expression::TableConstructor(table)) =
                arguments.first().map(|pair| pair.value())
            {
                Some(table)
            } else {
                None
            }
        }
        Call::AnonymousCall(FunctionArgs::TableConstructor(table)) => Some(table),
        _ => None,
    }
}

fn find_field_in_table<'a>(
    table: &'a TableConstructor,
    field_name: &str,
) -> Option<&'a Expression> {
    for field in table.fields() {
        if let Field::NameKey { key, value, .. } = field {
            if key.token().to_string().trim() == field_name {
                return Some(value);
            }
        }
    }
    None
}

fn extract_string_literal(expr: &Expression) -> Option<String> {
    let raw = expr.to_string();
    let trimmed = raw.trim();
    if (trimmed.starts_with('"') && trimmed.ends_with('"'))
        || (trimmed.starts_with('\'') && trimmed.ends_with('\''))
    {
        Some(trimmed[1..trimmed.len() - 1].to_string())
    } else {
        None
    }
}

fn extract_number_literal(expr: &Expression) -> Option<usize> {
    expr.to_string().trim().parse::<usize>().ok()
}

fn extract_boolean_literal(expr: &Expression) -> Option<bool> {
    match expr.to_string().trim() {
        "true" => Some(true),
        "false" => Some(false),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_parse() {
        let source = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/example_profile.luau")
            .canonicalize()
            .expect("Could not locate file");
        let mut templates = Vec::new();

        parse_profile_rtbf_templates(&source, &mut templates).expect("Failed to parse profile");

        let json = serde_json::to_string_pretty(&UserDataTemplates {
            user_data_templates: templates,
        })
        .expect("Failed to serialize json");

        assert_eq!(
            json,
            include_str!("../../../tests/fixtures/example_profile_templates.json")
        )
    }
}
