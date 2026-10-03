//! Bound CBOR syntax before metadata allocation; application values stay encoded.
use super::flatbuffers_wire::invalid;
use super::ParseError;
use std::collections::HashSet;

pub(super) fn validate(bytes: &[u8], root: u8, metadata: bool) -> Result<(), ParseError> {
    let maximum = if metadata {
        1024 * 1024
    } else {
        64 * 1024 * 1024
    };
    if bytes.is_empty() || bytes.len() > maximum || bytes[0] >> 5 != root {
        return Err(invalid("CBOR container or size"));
    }
    let mut scanner = Scanner {
        bytes,
        cursor: 0,
        items: 0,
        metadata,
    };
    scanner.value(0)?;
    if scanner.cursor != bytes.len() {
        return Err(invalid("CBOR trailing bytes"));
    }
    Ok(())
}
struct Scanner<'a> {
    bytes: &'a [u8],
    cursor: usize,
    items: usize,
    metadata: bool,
}
impl<'a> Scanner<'a> {
    fn take(&mut self, count: usize) -> Result<&'a [u8], ParseError> {
        let end = self
            .cursor
            .checked_add(count)
            .ok_or_else(|| invalid("CBOR length"))?;
        let result = self
            .bytes
            .get(self.cursor..end)
            .ok_or_else(|| invalid("CBOR truncation"))?;
        self.cursor = end;
        Ok(result)
    }
    fn byte(&mut self) -> Result<u8, ParseError> {
        Ok(self.take(1)?[0])
    }
    fn length(&mut self, info: u8) -> Result<u64, ParseError> {
        if info < 24 {
            return Ok(info as u64);
        }
        let size = match info {
            24 => 1,
            25 => 2,
            26 => 4,
            27 => 8,
            _ => return Err(invalid("CBOR additional info")),
        };
        let mut value = 0;
        for byte in self.take(size)? {
            value = (value << 8) | *byte as u64;
        }
        Ok(value)
    }
    fn count(&mut self, info: u8) -> Result<usize, ParseError> {
        usize::try_from(self.length(info)?).map_err(|_| invalid("CBOR length"))
    }
    fn charge(&mut self) -> Result<(), ParseError> {
        self.items += 1;
        if self.items > 1000000 {
            return Err(invalid("CBOR item budget"));
        }
        Ok(())
    }
    fn end(&mut self) -> bool {
        if self.bytes.get(self.cursor) == Some(&255) {
            self.cursor += 1;
            true
        } else {
            false
        }
    }
    fn string(&mut self, major: u8, info: u8, collect: bool) -> Result<Option<String>, ParseError> {
        let mut text = if major == 3 && collect {
            Some(String::new())
        } else {
            None
        };
        if info != 31 {
            let length = self.count(info)?;
            let bytes = self.take(length)?;
            if major == 3 {
                let chunk = std::str::from_utf8(bytes).map_err(|_| invalid("CBOR UTF-8"))?;
                if let Some(text) = &mut text {
                    text.push_str(chunk);
                }
            }
        } else {
            while !self.end() {
                self.charge()?;
                let header = self.byte()?;
                if header >> 5 != major || header & 31 == 31 {
                    return Err(invalid("CBOR string chunk"));
                }
                let length = self.count(header & 31)?;
                let bytes = self.take(length)?;
                if major == 3 {
                    let chunk = std::str::from_utf8(bytes).map_err(|_| invalid("CBOR UTF-8"))?;
                    if let Some(text) = &mut text {
                        text.push_str(chunk);
                    }
                }
            }
        }
        Ok(text)
    }
    fn value(&mut self, depth: usize) -> Result<(), ParseError> {
        self.charge()?;
        let header = self.byte()?;
        let major = header >> 5;
        let info = header & 31;
        match major {
            0 | 1 => {
                self.length(info)?;
            }
            2 | 3 => {
                self.string(major, info, false)?;
            }
            4 | 5 => {
                if depth >= 64 {
                    return Err(invalid("CBOR depth"));
                }
                let count = if info == 31 {
                    None
                } else {
                    Some(self.count(info)?)
                };
                let dictionary = major == 5 && (self.metadata || depth == 0);
                let mut keys = HashSet::new();
                let mut index = 0;
                while if let Some(count) = count {
                    index < count
                } else {
                    !self.end()
                } {
                    if dictionary {
                        self.charge()?;
                        let header = self.byte()?;
                        if header >> 5 != 3 {
                            return Err(invalid("CBOR dictionary key"));
                        }
                        let key = self.string(3, header & 31, true)?.unwrap();
                        if !keys.insert(key) {
                            return Err(invalid("CBOR duplicate key"));
                        }
                    } else {
                        self.value(depth + 1)?;
                    }
                    if major == 5 {
                        self.value(depth + 1)?;
                    }
                    index += 1;
                }
            }
            6 => {
                if depth >= 64 {
                    return Err(invalid("CBOR depth"));
                }
                self.length(info)?;
                self.value(depth + 1)?;
            }
            7 => match info {
                0..=23 => {}
                24 => {
                    if self.byte()? < 32 {
                        return Err(invalid("CBOR simple value"));
                    }
                }
                25..=27 => {
                    self.take(1 << (info - 24))?;
                }
                _ => return Err(invalid("CBOR break or reserved info")),
            },
            _ => unreachable!(),
        }
        Ok(())
    }
}
