use cssparser::{
    AtRuleParser, CowRcStr, DeclarationParser, ParseError, Parser, ParserState,
    QualifiedRuleParser, RuleBodyItemParser, RuleBodyParser, StyleSheetParser, Token,
};

pub type Reference = (usize, usize, String, bool);
type Result<T> = std::result::Result<T, ParseError<()>>;

pub fn extract(source: &str, inline: bool) -> std::result::Result<Vec<Reference>, String> {
    let source_without_bom = source.strip_prefix('\u{feff}').unwrap_or(source);
    let offset = source.len() - source_without_bom.len();
    // Reject CSS EOF recovery: incomplete email CSS must remain untouched.
    validate(&mut Parser::new(source_without_bom), source_without_bom, 0)
        .map_err(|_| "invalid_css")?;
    let mut input = Parser::new(source_without_bom);
    let mut reader = Rules { nested: !inline };
    let mut references = if inline {
        body(&mut input, false)
    } else {
        StyleSheetParser::new(&mut input, &mut reader).try_fold(Vec::new(), |mut all, item| {
            all.extend(item.map_err(|(error, _, _)| error)?);
            Ok(all)
        })
    }
    .map_err(|_| "invalid_css")?;
    for reference in &mut references {
        reference.0 += offset;
        reference.1 += offset;
    }
    references.sort_by_key(|r| r.0);
    let mut end = 0;
    for reference in &references {
        if reference.0 < end || reference.1 > source.len() {
            return Err("invalid_span".into());
        }
        end = reference.1;
    }
    Ok(references)
}

fn terminated(raw: &str, closer: u8) -> bool {
    raw.as_bytes().last() == Some(&closer)
        && raw.as_bytes()[..raw.len() - 1]
            .iter()
            .rev()
            .take_while(|b| **b == b'\\')
            .count()
            % 2
            == 0
}

fn validate(input: &mut Parser<'_>, source: &str, depth: usize) -> Result<()> {
    if depth > 128 {
        return Err(ParseError::custom(()));
    }
    loop {
        let start = input.position();
        let token = match input.next_including_whitespace_and_comments() {
            Ok(token) => token.clone(),
            Err(_) => break,
        };
        let raw = input.slice_from(start);
        if token.is_parse_error() {
            return Err(ParseError::custom(()));
        }
        match token {
            Token::Comment(_) if raw.len() < 4 || !raw.ends_with("*/") => {
                return Err(ParseError::custom(()))
            }
            Token::QuotedString(_) if raw.len() < 2 || !terminated(raw, raw.as_bytes()[0]) => {
                return Err(ParseError::custom(()))
            }
            Token::UnquotedUrl(_) if !terminated(raw, b')') => return Err(ParseError::custom(())),
            Token::Function(_)
            | Token::ParenthesisBlock
            | Token::SquareBracketBlock
            | Token::CurlyBracketBlock => {
                let closer = match token {
                    Token::SquareBracketBlock => "]",
                    Token::CurlyBracketBlock => "}",
                    _ => ")",
                };
                input.parse_nested_block(|inner| {
                    validate(inner, source, depth + 1)?;
                    let boundary = inner.position();
                    // A real closing delimiter remains unconsumed at this position.
                    if source.as_bytes().get(boundary.byte_index()) != closer.as_bytes().first() {
                        return Err(ParseError::custom(()));
                    }
                    Ok(())
                })?;
                if !input.slice_from(start).ends_with(closer) {
                    return Err(ParseError::custom(()));
                }
            }
            _ => {}
        }
    }
    Ok(())
}

fn values(
    input: &mut Parser<'_>,
    images: bool,
    nested: bool,
    candidates: bool,
) -> Result<Vec<Reference>> {
    let mut out = Vec::new();
    let mut first = true;
    loop {
        let start = input.position();
        let token = match input.next_including_whitespace_and_comments() {
            Ok(token) => token.clone(),
            Err(_) => break,
        };
        match token {
            Token::WhiteSpace(_) | Token::Comment(_) => continue,
            Token::Comma => {
                first = true;
                continue;
            }
            Token::UnquotedUrl(url) if images => out.push((
                start.byte_index(),
                input.position().byte_index(),
                url.to_string(),
                nested,
            )),
            Token::QuotedString(url) if images && candidates && first => out.push((
                start.byte_index(),
                input.position().byte_index(),
                url.to_string(),
                true,
            )),
            Token::Function(name) => {
                let name = name.to_ascii_lowercase();
                if name == "url" {
                    let url =
                        input.parse_nested_block(|inner| Ok(inner.expect_string_cloned()?))?;
                    if images {
                        out.push((
                            start.byte_index(),
                            input.position().byte_index(),
                            url.to_string(),
                            nested,
                        ));
                    }
                } else {
                    let candidates =
                        matches!(name.as_str(), "image" | "image-set" | "-webkit-image-set");
                    out.extend(
                        input
                            .parse_nested_block(|inner| values(inner, images, true, candidates))?,
                    );
                }
            }
            Token::ParenthesisBlock | Token::SquareBracketBlock | Token::CurlyBracketBlock => {
                out.extend(input.parse_nested_block(|inner| values(inner, images, true, false))?);
            }
            _ => {}
        }
        first = false;
    }
    Ok(out)
}

struct Rules {
    nested: bool,
}

fn body(input: &mut Parser<'_>, nested: bool) -> Result<Vec<Reference>> {
    RuleBodyParser::new(input, &mut Rules { nested }).try_fold(Vec::new(), |mut all, item| {
        all.extend(item.map_err(|(error, _, _)| error)?);
        Ok(all)
    })
}

impl<'i> DeclarationParser<'i> for Rules {
    type Declaration = Vec<Reference>;
    type Error = ();
    fn parse_value(
        &mut self,
        name: CowRcStr<'i>,
        input: &mut Parser<'i>,
        _: &ParserState,
    ) -> Result<Vec<Reference>> {
        values(
            input,
            image_property(&name.to_ascii_lowercase()),
            false,
            false,
        )
    }
}
impl<'i> QualifiedRuleParser<'i> for Rules {
    type Prelude = ();
    type QualifiedRule = Vec<Reference>;
    type Error = ();
    fn parse_prelude(&mut self, input: &mut Parser<'i>) -> Result<()> {
        values(input, false, false, false)?;
        Ok(())
    }
    fn parse_block(
        &mut self,
        _: (),
        _: &ParserState,
        input: &mut Parser<'i>,
    ) -> Result<Vec<Reference>> {
        body(input, true)
    }
}
impl<'i> AtRuleParser<'i> for Rules {
    type Prelude = ();
    type AtRule = Vec<Reference>;
    type Error = ();
    fn parse_prelude(&mut self, _: CowRcStr<'i>, input: &mut Parser<'i>) -> Result<()> {
        if !self.nested {
            return Err(ParseError::custom(()));
        }
        values(input, false, false, false)?;
        Ok(())
    }
    fn rule_without_block(
        &mut self,
        _: (),
        _: &ParserState,
    ) -> std::result::Result<Vec<Reference>, ()> {
        Ok(Vec::new())
    }
    fn parse_block(
        &mut self,
        _: (),
        _: &ParserState,
        input: &mut Parser<'i>,
    ) -> Result<Vec<Reference>> {
        body(input, true)
    }
}
impl RuleBodyItemParser<'_, Vec<Reference>, ()> for Rules {
    fn parse_declarations(&self) -> bool {
        true
    }
    fn parse_qualified(&self) -> bool {
        self.nested
    }
}

fn image_property(name: &str) -> bool {
    name.starts_with("--")
        || matches!(
            name,
            "background"
                | "background-image"
                | "border-image"
                | "border-image-source"
                | "list-style"
                | "list-style-image"
                | "content"
                | "cursor"
                | "mask"
                | "mask-image"
                | "mask-border"
                | "mask-border-source"
                | "-webkit-mask"
                | "-webkit-mask-image"
                | "-webkit-mask-box-image"
                | "-webkit-mask-box-image-source"
                | "shape-outside"
                | "fill"
                | "stroke"
                | "filter"
                | "clip-path"
        )
}
