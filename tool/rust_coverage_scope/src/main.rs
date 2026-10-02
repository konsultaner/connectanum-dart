//! Source scopes only: no native transport build, loading, or execution.
use proc_macro2::{Span, TokenStream, TokenTree};
use quote::ToTokens;
use serde_json::{json, Value};
use std::{collections::BTreeSet, env, fs, process};
use syn::{
    parse::Parser, punctuated::Punctuated, spanned::Spanned, visit::Visit, Attribute, Meta, Token,
};

// Unknown platform predicates remain production candidates. Only explicit
// test-only predicates are removed; this is not a host-specific cfg evaluator.
fn cfg_value(meta: &Meta) -> Option<bool> {
    match meta {
        Meta::Path(path) if path.is_ident("test") => Some(false),
        Meta::NameValue(value) if value.path.is_ident("feature") => {
            if let syn::Expr::Lit(value) = &value.value {
                if let syn::Lit::Str(value) = &value.lit {
                    if value.value() == "ffi-test" {
                        return Some(false);
                    }
                }
            }
            None
        }
        Meta::List(list) => {
            let values = Punctuated::<Meta, Token![,]>::parse_terminated
                .parse2(list.tokens.clone())
                .ok()?;
            let values: Vec<_> = values.iter().map(cfg_value).collect();
            if list.path.is_ident("not") && values.len() == 1 {
                values[0].map(|value| !value)
            } else if list.path.is_ident("all") {
                if values.contains(&Some(false)) {
                    Some(false)
                } else if values.iter().all(|value| *value == Some(true)) {
                    Some(true)
                } else {
                    None
                }
            } else if list.path.is_ident("any") {
                if values.contains(&Some(true)) {
                    Some(true)
                } else if values.iter().all(|value| *value == Some(false)) {
                    Some(false)
                } else {
                    None
                }
            } else {
                None
            }
        }
        _ => None,
    }
}

fn affects_scope(meta: &Meta) -> bool {
    let path = meta.path();
    path.is_ident("cfg")
        || path
            .segments
            .last()
            .is_some_and(|segment| segment.ident == "test")
        || path.is_ident("path")
        || (path.is_ident("cfg_attr")
            && match meta {
                Meta::List(list) => Punctuated::<Meta, Token![,]>::parse_terminated
                    .parse2(list.tokens.clone())
                    .map_or(true, |items| items.iter().skip(1).any(affects_scope)),
                _ => true,
            })
}

#[derive(Clone, Copy)]
struct Range {
    start: (usize, usize),
    end: (usize, usize),
}
impl Range {
    fn of(span: Span) -> Self {
        let (start, end) = (span.start(), span.end());
        Self {
            start: (start.line, start.column),
            end: (end.line, end.column),
        }
    }
    fn contains(self, other: Self) -> bool {
        self.start <= other.start && self.end >= other.end
    }
    fn json(self) -> Value {
        json!({"start": self.start, "end": self.end})
    }
}

#[derive(Default)]
struct Scopes {
    excluded: Vec<(Range, String)>,
    problems: Vec<String>,
    modules: Vec<Value>,
    inline: Vec<String>,
    test_only: bool,
    macro_definitions: Vec<String>,
    production_macro_calls: BTreeSet<String>,
    function_bodies: Vec<(String, Range, TokenStream)>,
}

impl Scopes {
    fn record_function_body(&mut self, name: &syn::Ident, block: &syn::Block) {
        if self.test_only {
            return;
        }
        if let (Some(first), Some(last)) = (block.stmts.first(), block.stmts.last()) {
            let range = Range {
                start: Range::of(first.span()).start,
                end: Range::of(last.span()).end,
            };
            let mut tokens = TokenStream::new();
            for stmt in &block.stmts {
                stmt.to_tokens(&mut tokens);
            }
            self.function_bodies.push((name.to_string(), range, tokens));
        }
    }

    fn enter(&mut self, attrs: &[Attribute], span: Span) -> bool {
        let previous = self.test_only;
        for attr in attrs {
            let path = attr.path().to_token_stream().to_string().replace(' ', "");
            let reason = if matches!(path.as_str(), "test" | "tokio::test" | "async_std::test") {
                Some(path)
            } else if attr.path().is_ident("cfg") {
                match attr.parse_args::<Meta>() {
                    Ok(meta) if cfg_value(&meta) == Some(false) => {
                        Some(attr.to_token_stream().to_string())
                    }
                    Ok(_) => None,
                    Err(error) => {
                        self.problems.push(error.to_string());
                        None
                    }
                }
            } else {
                None
            };
            if let Some(reason) = reason {
                if !self.test_only {
                    self.excluded.push((Range::of(span), reason));
                }
                self.test_only = true;
            }
            if !self.test_only && attr.path().is_ident("cfg_attr") && affects_scope(&attr.meta) {
                self.problems.push(format!(
                    "scope-changing cfg_attr at line {}",
                    span.start().line
                ));
            }
        }
        previous
    }

    fn enter_node(&mut self, node: &(impl ToTokens + Spanned)) -> bool {
        let parser = |input: syn::parse::ParseStream| {
            let attrs = input.call(Attribute::parse_outer)?;
            let _: TokenStream = input.parse()?;
            Ok(attrs)
        };
        match parser.parse2(node.to_token_stream()) {
            Ok(attrs) => self.enter(&attrs, node.span()),
            Err(error) => {
                self.problems.push(error.to_string());
                self.test_only
            }
        }
    }
}

macro_rules! scoped_visit {
    ($method:ident, $ty:ty) => {
        fn $method(&mut self, node: &'ast $ty) {
            let previous = self.enter_node(node);
            syn::visit::$method(self, node);
            self.test_only = previous;
        }
    };
}

impl<'ast> Visit<'ast> for Scopes {
    scoped_visit!(visit_item, syn::Item);
    scoped_visit!(visit_impl_item, syn::ImplItem);
    scoped_visit!(visit_trait_item, syn::TraitItem);
    scoped_visit!(visit_foreign_item, syn::ForeignItem);
    scoped_visit!(visit_expr, syn::Expr);
    scoped_visit!(visit_stmt, syn::Stmt);
    scoped_visit!(visit_local, syn::Local);
    scoped_visit!(visit_arm, syn::Arm);
    scoped_visit!(visit_field, syn::Field);
    scoped_visit!(visit_variant, syn::Variant);

    fn visit_item_fn(&mut self, node: &'ast syn::ItemFn) {
        self.record_function_body(&node.sig.ident, &node.block);
        syn::visit::visit_item_fn(self, node);
    }

    fn visit_impl_item_fn(&mut self, node: &'ast syn::ImplItemFn) {
        self.record_function_body(&node.sig.ident, &node.block);
        syn::visit::visit_impl_item_fn(self, node);
    }

    fn visit_trait_item_fn(&mut self, node: &'ast syn::TraitItemFn) {
        if let Some(block) = &node.default {
            self.record_function_body(&node.sig.ident, block);
        }
        syn::visit::visit_trait_item_fn(self, node);
    }

    fn visit_item_macro(&mut self, node: &'ast syn::ItemMacro) {
        if !self.test_only && node.mac.path.is_ident("macro_rules") {
            if let Some(name) = &node.ident {
                self.macro_definitions.push(name.to_string());
            }
        }
        syn::visit::visit_item_macro(self, node);
    }

    fn visit_item_mod(&mut self, node: &'ast syn::ItemMod) {
        for attr in &node.attrs {
            self.visit_attribute(attr);
        }
        let paths: Vec<_> = node
            .attrs
            .iter()
            .filter(|attr| attr.path().is_ident("path"))
            .collect();
        if let Some((_, items)) = &node.content {
            if !paths.is_empty() {
                self.problems.push(format!(
                    "inline #[path] at line {}",
                    node.span().start().line
                ));
            }
            self.inline.push(node.ident.to_string());
            for item in items {
                self.visit_item(item);
            }
            self.inline.pop();
        } else {
            let path = match paths.as_slice() {
                [] => None,
                [attr] => match &attr.meta {
                    Meta::NameValue(value) => match &value.value {
                        syn::Expr::Lit(value) => match &value.lit {
                            syn::Lit::Str(value) => Some(value.value()),
                            _ => {
                                self.problems.push("non-string module path".into());
                                None
                            }
                        },
                        _ => {
                            self.problems.push("nonliteral module path".into());
                            None
                        }
                    },
                    _ => {
                        self.problems.push("invalid module path".into());
                        None
                    }
                },
                _ => {
                    self.problems.push("multiple module paths".into());
                    None
                }
            };
            self.modules.push(
                json!({"name": node.ident.to_string(), "inline": self.inline,
                "path": path, "testOnly": self.test_only}),
            );
        }
    }

    fn visit_attribute(&mut self, node: &'ast Attribute) {
        if !self.test_only
            && matches!(node.style, syn::AttrStyle::Inner(_))
            && affects_scope(&node.meta)
        {
            self.problems.push(format!(
                "inner scope attribute at line {}",
                node.span().start().line
            ));
        }
    }

    fn visit_macro(&mut self, node: &'ast syn::Macro) {
        if !self.test_only {
            if let Some(name) = node.path.get_ident() {
                self.production_macro_calls.insert(name.to_string());
            }
        }
        if !self.test_only
            && node.path.to_token_stream().to_string().replace(' ', "") == "tokio::select"
        {
            match syn::parse2::<SelectExpressions>(node.tokens.clone()) {
                Ok(expressions) => {
                    for expr in &expressions.0 {
                        self.visit_expr(expr);
                    }
                }
                Err(error) => self.problems.push(format!(
                    "unparsed tokio::select at line {}: {error}",
                    node.span().start().line
                )),
            }
            return;
        }
        if !self.test_only && (node.path.is_ident("include") || opaque_scope(node.tokens.clone())) {
            self.problems.push(format!(
                "opaque source-generating macro at line {}",
                node.span().start().line
            ));
        }
    }
}

// The select macro has a non-Rust outer grammar, but its futures, guards and
// handlers are ordinary Rust expressions with original source spans.
struct SelectExpressions(Vec<syn::Expr>);
impl syn::parse::Parse for SelectExpressions {
    fn parse(input: syn::parse::ParseStream) -> syn::Result<Self> {
        let mut expressions = Vec::new();
        if input.peek(syn::Ident) && input.peek2(Token![;]) {
            let ident: syn::Ident = input.parse()?;
            if ident != "biased" {
                return Err(syn::Error::new(ident.span(), "expected biased"));
            }
            input.parse::<Token![;]>()?;
        }
        while !input.is_empty() {
            if input.peek(Token![else]) {
                input.parse::<Token![else]>()?;
            } else {
                input.call(syn::Pat::parse_multi_with_leading_vert)?;
                input.parse::<Token![=]>()?;
                expressions.push(input.parse()?);
                if input.peek(Token![,]) {
                    input.parse::<Token![,]>()?;
                    input.parse::<Token![if]>()?;
                    expressions.push(input.parse()?);
                }
            }
            input.parse::<Token![=>]>()?;
            expressions.push(input.parse()?);
            if input.peek(Token![,]) {
                input.parse::<Token![,]>()?;
            }
        }
        Ok(Self(expressions))
    }
}

fn opaque_scope(tokens: TokenStream) -> bool {
    let mut attribute = false;
    for token in tokens {
        if let TokenTree::Punct(punct) = &token {
            if punct.as_char() == '#' {
                attribute = true;
                continue;
            }
            if attribute && punct.as_char() == '!' {
                continue;
            }
        }
        if let TokenTree::Group(group) = token {
            if attribute && group.delimiter() == proc_macro2::Delimiter::Bracket {
                if let Ok(meta) = syn::parse2::<Meta>(group.stream()) {
                    if affects_scope(&meta) {
                        return true;
                    }
                }
            }
            if opaque_scope(group.stream()) {
                return true;
            }
        }
        attribute = false;
    }
    false
}

fn token_lines(
    tokens: TokenStream,
    ranges: &[(Range, String)],
    included: &mut BTreeSet<usize>,
    excluded: &mut BTreeSet<usize>,
) {
    for token in tokens {
        let spans = if let TokenTree::Group(group) = &token {
            token_lines(group.stream(), ranges, included, excluded);
            vec![group.span_open(), group.span_close()]
        } else {
            vec![token.span()]
        };
        for span in spans {
            let range = Range::of(span);
            let lines = if ranges.iter().any(|(outer, _)| outer.contains(range)) {
                &mut *excluded
            } else {
                &mut *included
            };
            let last = if range.end.1 == 0 {
                range.end.0.saturating_sub(1)
            } else {
                range.end.0
            };
            lines.extend(range.start.0..=last);
        }
    }
}

fn analyze(source: &str) -> Result<Value, syn::Error> {
    let ast = syn::parse_file(source)?;
    let mut scopes = Scopes::default();
    scopes.enter(&ast.attrs, ast.span());
    for item in &ast.items {
        scopes.visit_item(item);
    }
    let mut definitions = BTreeSet::new();
    for name in &scopes.macro_definitions {
        if !definitions.insert(name) || !scopes.production_macro_calls.contains(name) {
            scopes.problems.push(format!(
                "macro definition {name} has ambiguous or no local production invocation"
            ));
        }
    }
    let (mut included, mut excluded) = (BTreeSet::new(), BTreeSet::new());
    token_lines(
        source.parse::<TokenStream>()?,
        &scopes.excluded,
        &mut included,
        &mut excluded,
    );
    // LLVM line regions can cover blank/comment-only lines inside test bodies.
    // Token ownership detects mixed lines, but must not leave those regions in
    // the production denominator simply because they contain no Rust tokens.
    for (range, _) in &scopes.excluded {
        let last = if range.end.1 == 0 {
            range.end.0.saturating_sub(1)
        } else {
            range.end.0
        };
        excluded.extend(range.start.0..=last);
    }
    // Cargo's FnValue span covers statements, not the outer braces. Require
    // production tokens after nested test scopes are removed, not just blanks.
    let production_bodies: Vec<_> = scopes
        .function_bodies
        .iter()
        .filter_map(|(name, span, tokens)| {
            let (mut production, mut test) = (BTreeSet::new(), BTreeSet::new());
            token_lines(tokens.clone(), &scopes.excluded, &mut production, &mut test);
            (!production.is_empty()).then(|| json!({"name":name,"span":span.json()}))
        })
        .collect();
    Ok(json!({
        "exclusions": scopes.excluded.iter().map(|(span, reason)| json!({"span":span.json(),"reason":reason})).collect::<Vec<_>>(),
        "excludedLines": excluded.difference(&included).copied().collect::<Vec<_>>(),
        "mixedLines": excluded.intersection(&included).copied().collect::<Vec<_>>(),
        "modules": scopes.modules, "problems": scopes.problems,
        "fileTestOnly": scopes.test_only,
        "productionFunctionBodies": production_bodies,
    }))
}

fn main() {
    let mut output = serde_json::Map::new();
    for path in env::args().skip(1) {
        let result = fs::read_to_string(&path)
            .map_err(|e| e.to_string())
            .and_then(|source| analyze(&source).map_err(|e| e.to_string()));
        match result {
            Ok(value) => {
                output.insert(path, value);
            }
            Err(error) => {
                eprintln!("{path}: {error}");
                process::exit(1);
            }
        }
    }
    println!("{}", Value::Object(output));
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn three_valued_predicates() {
        for (source, expected) in [
            ("test", Some(false)),
            ("not(test)", Some(true)),
            ("all(test, unix)", Some(false)),
            ("any(test, unix)", None),
            ("not(all(feature = \"ffi-test\", legacy))", Some(true)),
            ("feature = \"production\"", None),
            ("all()", Some(true)),
            ("any()", Some(false)),
        ] {
            assert_eq!(
                cfg_value(&syn::parse_str::<Meta>(source).unwrap()),
                expected,
                "{source}"
            );
        }
    }
    #[test]
    fn strings_and_nested_braces_are_not_attributes() {
        let report = analyze("fn prod() { let _ = r###\"#[cfg(test)] mod x { }\"###; }\n#[cfg(test)]\nmod tests { fn nested() { if true { } } }").unwrap();
        assert_eq!(report["excludedLines"], json!([2, 3]));
        assert_eq!(report["mixedLines"], json!([]));
    }
    #[test]
    fn mixed_lines_cannot_be_removed() {
        let report = analyze("fn prod() {} #[cfg(test)] fn helper() {}").unwrap();
        assert_eq!(report["excludedLines"], json!([]));
        assert_eq!(report["mixedLines"], json!([1]));
    }
    #[test]
    fn production_function_bodies_keep_nested_test_regions_without_admitting_helpers() {
        let source = "fn prod(value: i32) -> i32 {\n    let result = value;\n    #[cfg(test)] { debug(); }\n    result\n}\n#[cfg(test)] fn helper() { debug(); }\n#[cfg(feature = \"ffi-test\")] fn ffi_helper() { debug(); }\nfn only_debug() { #[cfg(test)] debug(); }\n";
        let report = analyze(source).unwrap();
        assert_eq!(
            report["productionFunctionBodies"],
            json!([
                {"name":"prod", "span":{"start":[2,4],"end":[4,10]}}
            ])
        );
        assert!(report["excludedLines"]
            .as_array()
            .unwrap()
            .contains(&json!(3)));
        assert!(report["problems"].as_array().unwrap().is_empty());
    }
    #[test]
    fn production_method_bodies_include_impls_and_trait_defaults_not_tests() {
        let report = analyze("impl A {\nfn live() { work(); }\n#[test] fn check() { work(); }\n}\ntrait T {\nfn required();\nfn defaulted() { work(); }\n#[cfg(test)] fn test_default() { work(); }\n}\n#[cfg(test)] mod tests { fn nested() { work(); } }").unwrap();
        let names: Vec<_> = report["productionFunctionBodies"]
            .as_array()
            .unwrap()
            .iter()
            .map(|body| body["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, ["live", "defaulted"]);
    }
    #[test]
    fn local_expression_impl_and_external_module_scopes() {
        let report = analyze("fn prod() {\n#[cfg(test)] let x = 1;\n#[cfg(feature = \"ffi-test\")] { helper(); }\n}\nimpl A {\n#[cfg(test)] fn helper() {}\n}\n#[cfg(test)] mod tests;\nmod nested { #[path = \"alternate.rs\"] mod child; }").unwrap();
        assert_eq!(report["excludedLines"], json!([2, 3, 6, 8]));
        assert_eq!(report["modules"][0]["testOnly"], true);
        assert_eq!(report["modules"][1]["inline"], json!(["nested"]));
        assert_eq!(report["modules"][1]["path"], "alternate.rs");
    }
    #[test]
    fn unknown_cfg_is_retained_and_opaque_generation_is_flagged() {
        let report = analyze("#[cfg(any(test, unix))] fn prod() {}\nmacro_rules! make { () => { #[cfg(test)] fn t() {} }; }\ninclude!(\"generated.rs\");\n#[cfg_attr(test, cfg(unix))] fn ambiguous() {}").unwrap();
        assert_eq!(report["excludedLines"], json!([]));
        assert_eq!(report["problems"].as_array().unwrap().len(), 4);
    }
    #[test]
    fn non_scope_cfg_attr_and_test_macros_are_safe() {
        let report = analyze("#[cfg_attr(unix, allow(dead_code))] fn prod() {}\n#[cfg(test)] mod tests { include!(\"test_generated.rs\"); }").unwrap();
        assert_eq!(report["problems"], json!([]));
        assert_eq!(report["excludedLines"], json!([2]));
    }
    #[test]
    fn select_handlers_are_parsed_without_excluding_the_whole_macro() {
        let report = analyze("async fn prod() { tokio::select! { biased;\n_ = future(), if enabled() => {\n#[cfg(feature = \"ffi-test\")] debug();\nproduction();\n}, else => fallback(), } }").unwrap();
        assert_eq!(report["problems"], json!([]));
        assert_eq!(report["excludedLines"], json!([3]));
    }
    #[test]
    fn unsupported_inner_cfg_cannot_be_silently_included() {
        for source in [
            "fn prod() { #![cfg(test)] helper(); }",
            "mod nested { #![cfg(test)] fn helper() {} }",
        ] {
            let report = analyze(source).unwrap();
            assert!(
                !report["problems"].as_array().unwrap().is_empty(),
                "{source}"
            );
        }
    }
    #[test]
    fn test_comment_and_blank_regions_do_not_enter_production_totals() {
        let report = analyze(
            "fn production() {}\n#[cfg(test)]\nmod tests {\n// comment\n\nfn helper() {}\n}\n",
        )
        .unwrap();
        assert_eq!(report["excludedLines"], json!([2, 3, 4, 5, 6, 7]));
    }
    #[test]
    fn production_macro_definition_cannot_be_credited_only_by_test_invocations() {
        let source = "macro_rules! generated { () => { fn helper() {} }; }\n#[cfg(test)] mod tests { generated!(); }";
        assert!(!analyze(source).unwrap()["problems"]
            .as_array()
            .unwrap()
            .is_empty());
        let source = format!("{source}\ngenerated!();");
        assert_eq!(analyze(&source).unwrap()["problems"], json!([]));
    }
    #[test]
    fn macro_arrays_named_test_are_not_scope_attributes() {
        assert_eq!(
            analyze("fn prod() { consume!([test], [cfg(test)]); }").unwrap()["problems"],
            json!([])
        );
        assert!(
            !analyze("fn prod() { consume!({ #![cfg(test)] test() }); }").unwrap()["problems"]
                .as_array()
                .unwrap()
                .is_empty()
        );
    }
}
