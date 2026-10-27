use regex::Regex;
use serde_json::Value;

pub fn s(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => {
            let trimmed = text.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        }
        Value::Number(number) => Some(number.to_string()),
        _ => None,
    }
}

pub fn raw_s(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => Some(text.clone()),
        Value::Number(number) => Some(number.to_string()),
        _ => None,
    }
}

pub fn f(value: &Value) -> Option<f64> {
    match value {
        Value::Number(number) => number.as_f64(),
        Value::String(text) => text.trim().parse().ok(),
        _ => None,
    }
}

pub fn i(value: &Value) -> Option<i64> {
    match value {
        Value::Number(number) => number.as_i64().or_else(|| number.as_f64().map(|v| v as i64)),
        Value::String(text) => text.trim().parse::<i64>().ok().or_else(|| text.trim().parse::<f64>().ok().map(|v| v as i64)),
        _ => None,
    }
}

pub fn b(value: &Value) -> Option<bool> {
    match value {
        Value::Bool(flag) => Some(*flag),
        Value::Number(number) => number.as_i64().map(|v| v != 0),
        Value::String(text) => Some(matches!(text.to_lowercase().as_str(), "true" | "1" | "yes")),
        _ => None,
    }
}

pub fn arr(value: &Value) -> &[Value] {
    match value {
        Value::Array(items) => items.as_slice(),
        _ => &[],
    }
}

pub fn url(value: &Value) -> Option<String> {
    let text = s(value)?;
    if text.starts_with("//") {
        return Some(format!("https:{text}"));
    }
    if text.starts_with("http://") || text.starts_with("https://") {
        Some(text)
    } else {
        None
    }
}

pub fn exists(value: &Value) -> bool {
    !value.is_null()
}

pub fn parse(text: &str) -> Value {
    serde_json::from_str(text).unwrap_or(Value::Null)
}

pub fn find_all<'a>(root: &'a Value, key: &str, limit: usize) -> Vec<&'a Value> {
    let mut output = Vec::new();
    fn walk<'a>(node: &'a Value, key: &str, limit: usize, depth: usize, output: &mut Vec<&'a Value>) {
        if output.len() >= limit || depth > 60 {
            return;
        }
        match node {
            Value::Object(map) => {
                if let Some(value) = map.get(key) {
                    output.push(value);
                    if output.len() >= limit {
                        return;
                    }
                }
                for value in map.values() {
                    walk(value, key, limit, depth + 1, output);
                    if output.len() >= limit {
                        return;
                    }
                }
            }
            Value::Array(items) => {
                for value in items {
                    walk(value, key, limit, depth + 1, output);
                    if output.len() >= limit {
                        return;
                    }
                }
            }
            _ => {}
        }
    }
    walk(root, key, limit, 0, &mut output);
    output
}

pub fn find_object<'a>(root: &'a Value, predicate: &dyn Fn(&serde_json::Map<String, Value>) -> bool) -> Option<&'a Value> {
    fn walk<'a>(node: &'a Value, predicate: &dyn Fn(&serde_json::Map<String, Value>) -> bool, depth: usize) -> Option<&'a Value> {
        if depth > 60 {
            return None;
        }
        match node {
            Value::Object(map) => {
                if predicate(map) {
                    return Some(node);
                }
                for value in map.values() {
                    if let Some(found) = walk(value, predicate, depth + 1) {
                        return Some(found);
                    }
                }
                None
            }
            Value::Array(items) => {
                for value in items {
                    if let Some(found) = walk(value, predicate, depth + 1) {
                        return Some(found);
                    }
                }
                None
            }
            _ => None,
        }
    }
    walk(root, predicate, 0)
}

pub fn first(pattern: &str, text: &str, group: usize) -> Option<String> {
    let regex = Regex::new(pattern).ok()?;
    let captures = regex.captures(text)?;
    let value = captures.get(group)?.as_str();
    if value.is_empty() {
        None
    } else {
        Some(value.to_string())
    }
}

pub fn all(pattern: &str, text: &str, group: usize) -> Vec<String> {
    let Ok(regex) = Regex::new(pattern) else { return Vec::new() };
    regex
        .captures_iter(text)
        .filter_map(|captures| captures.get(group).map(|m| m.as_str().to_string()))
        .collect()
}

pub fn script_contents(html: &str, attribute_pattern: &str) -> Vec<String> {
    let pattern = format!(r#"(?is)<script[^>]*{attribute_pattern}[^>]*>(.*?)</script>"#);
    all(&pattern, html, 1)
}

pub fn meta_content(property: &str, html: &str) -> Option<String> {
    let escaped = regex::escape(property);
    let patterns = [
        format!(r#"(?i)<meta[^>]+(?:property|name)=["']{escaped}["'][^>]*content=["']([^"']*)["']"#),
        format!(r#"(?i)<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']{escaped}["']"#),
    ];
    for pattern in patterns {
        if let Some(value) = first(&pattern, html, 1) {
            return Some(decode_entities(&value));
        }
    }
    None
}

pub fn decode_entities(text: &str) -> String {
    if !text.contains('&') {
        return text.to_string();
    }
    let mut result = text.to_string();
    for (entity, value) in [
        ("&amp;", "&"),
        ("&quot;", "\""),
        ("&#39;", "'"),
        ("&apos;", "'"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&nbsp;", " "),
        ("&#x27;", "'"),
        ("&#x2F;", "/"),
    ] {
        result = result.replace(entity, value);
    }
    let numeric = Regex::new(r"&#(x?)([0-9a-fA-F]+);").unwrap();
    numeric
        .replace_all(&result, |captures: &regex::Captures| {
            let radix = if &captures[1] == "x" { 16 } else { 10 };
            u32::from_str_radix(&captures[2], radix)
                .ok()
                .and_then(char::from_u32)
                .map(|c| c.to_string())
                .unwrap_or_default()
        })
        .into_owned()
}

pub fn unescape_json_string(raw: &str) -> String {
    serde_json::from_str::<String>(&format!("\"{raw}\"")).unwrap_or_else(|_| raw.to_string())
}
