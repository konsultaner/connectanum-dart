//! Helpers for reasoning about HTTP/1.1 bodies after the header block has been
//! parsed. These utilities allow the handshake code to differentiate between
//! requests that are already fully buffered, those that require streaming the
//! remaining bytes, and requests that have no payload at all.

use bytes::Bytes;

/// Describes how the HTTP body should be consumed.
#[derive(Debug)]
pub enum HttpBodyPhase {
    /// The entire body is already buffered.
    Buffered(Bytes),
    /// A prefix is buffered but additional bytes must be read from the socket.
    NeedsStreaming { prefix: Bytes, remaining_len: usize },
    /// No body is expected for this request.
    Finished,
}

/// Classifies the current body state given the buffered bytes and optional
/// `Content-Length` header.
pub fn classify_http_body(buffered: Bytes, content_length: Option<usize>) -> HttpBodyPhase {
    match content_length {
        None => {
            if buffered.is_empty() {
                HttpBodyPhase::Finished
            } else {
                HttpBodyPhase::Buffered(buffered)
            }
        }
        Some(0) => HttpBodyPhase::Finished,
        Some(len) if len <= buffered.len() => HttpBodyPhase::Buffered(buffered.slice(..len)),
        Some(len) => {
            let remaining_len = len.saturating_sub(buffered.len());
            HttpBodyPhase::NeedsStreaming {
                prefix: buffered,
                remaining_len,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use bytes::Bytes;

    use super::{classify_http_body, HttpBodyPhase};

    #[test]
    fn finished_when_length_zero() {
        match classify_http_body(Bytes::new(), Some(0)) {
            HttpBodyPhase::Finished => {}
            _ => panic!("expected finished"),
        }
    }

    #[test]
    fn buffered_when_all_bytes_present() {
        match classify_http_body(Bytes::from_static(b"abcd"), Some(4)) {
            HttpBodyPhase::Buffered(bytes) => assert_eq!(bytes, Bytes::from_static(b"abcd")),
            _ => panic!("expected buffered"),
        }
    }

    #[test]
    fn needs_streaming_reports_remaining_len() {
        match classify_http_body(Bytes::from_static(b"1234"), Some(10)) {
            HttpBodyPhase::NeedsStreaming {
                prefix,
                remaining_len,
            } => {
                assert_eq!(prefix, Bytes::from_static(b"1234"));
                assert_eq!(remaining_len, 6);
            }
            _ => panic!("expected streaming"),
        }
    }

    #[test]
    fn buffered_without_content_length() {
        match classify_http_body(Bytes::from_static(b"body"), None) {
            HttpBodyPhase::Buffered(bytes) => assert_eq!(bytes, Bytes::from_static(b"body")),
            _ => panic!("expected buffered"),
        }
    }
}
