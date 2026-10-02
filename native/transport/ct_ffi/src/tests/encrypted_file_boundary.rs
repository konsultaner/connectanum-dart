use crate::runtime::*;
use base64::Engine;
use std::{ffi::CString, io::Write, path::PathBuf, ptr};

struct Resources {
    path: PathBuf,
    file: i32,
    keyring: i32,
    session: i32,
}

impl Drop for Resources {
    fn drop(&mut self) {
        if self.session > 0 {
            ct_e2ee_session_release(self.session);
        }
        if self.keyring > 0 {
            ct_e2ee_keyring_release(self.keyring);
        }
        if self.file > 0 {
            ct_file_release(self.file);
        }
        let _ = std::fs::remove_file(&self.path);
    }
}

#[derive(Clone, Copy)]
struct Send {
    connection: i32,
    prefix: *const u8,
    prefix_len: i32,
    file: i32,
    offset: u64,
    length: u64,
    session: i32,
    key: *const std::ffi::c_char,
    key_len: i32,
    cipher: i32,
    suffix: *const u8,
    suffix_len: i32,
    encoding: i32,
}

impl Send {
    fn invoke(self) -> i32 {
        ct_send_message_native_e2ee_file_segment_v2(
            self.connection,
            self.prefix,
            self.prefix_len,
            self.file,
            self.offset,
            self.length,
            self.session,
            self.key,
            self.key_len,
            self.cipher,
            self.suffix,
            self.suffix_len,
            self.encoding,
        )
    }
}

pub(super) fn check(client: i32, server: i32, websocket: bool) {
    let path = std::env::temp_dir().join(format!(
        "connectanum-encrypted-boundary-{}-{websocket}.bin",
        std::process::id()
    ));
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .unwrap();
    let mut resources = Resources {
        path,
        file: 0,
        keyring: 0,
        session: 0,
    };
    file.write_all(&[99, 0, 127, 128, 255, 98]).unwrap();
    drop(file);
    let path_c = CString::new(resources.path.to_str().unwrap()).unwrap();
    resources.file = ct_file_open(path_c.as_ptr(), path_c.as_bytes().len() as i32, 6);
    assert!(resources.file > 0);
    resources.keyring = ct_e2ee_keyring_new();
    assert!(resources.keyring > 0);
    let key = [42_u8; 32];
    let key_id = CString::new("boundary").unwrap();
    assert_eq!(
        ct_e2ee_keyring_add_key(resources.keyring, key_id.as_ptr(), 8, key.as_ptr(), 32, 1),
        SUCCESS
    );
    resources.session = ct_e2ee_session_new(resources.keyring, ptr::null(), 0);
    assert!(resources.session > 0);
    let prefix = b"[68,301,302,{},[\"";
    let suffix = b"\"]]";
    let valid = Send {
        connection: client,
        prefix: prefix.as_ptr(),
        prefix_len: prefix.len() as i32,
        file: resources.file,
        offset: 1,
        length: 4,
        session: resources.session,
        key: ptr::null(),
        key_len: 0,
        cipher: 1,
        suffix: suffix.as_ptr(),
        suffix_len: suffix.len() as i32,
        encoding: 1,
    };
    let missing_key = CString::new("missing").unwrap();
    let invalid_key = [255_u8];
    let dead_file = ct_file_open(path_c.as_ptr(), path_c.as_bytes().len() as i32, 6);
    assert!(dead_file > 0);
    assert_eq!(ct_file_release(dead_file), SUCCESS);
    let dead_session = ct_e2ee_session_new(resources.keyring, ptr::null(), 0);
    assert!(dead_session > 0);
    assert_eq!(ct_e2ee_session_release(dead_session), SUCCESS);
    for (name, request, expected) in [
        (
            "connection",
            Send {
                connection: 0,
                ..valid
            },
            ERR_INVALID_ARGUMENT,
        ),
        ("file", Send { file: 0, ..valid }, ERR_INVALID_ARGUMENT),
        (
            "session",
            Send {
                session: 0,
                ..valid
            },
            ERR_INVALID_ARGUMENT,
        ),
        (
            "negative prefix",
            Send {
                prefix_len: -1,
                ..valid
            },
            ERR_INVALID_ARGUMENT,
        ),
        (
            "null prefix",
            Send {
                prefix: ptr::null(),
                ..valid
            },
            ERR_INVALID_ARGUMENT,
        ),
        (
            "negative suffix",
            Send {
                suffix_len: -1,
                ..valid
            },
            ERR_INVALID_ARGUMENT,
        ),
        (
            "null suffix",
            Send {
                suffix: ptr::null(),
                ..valid
            },
            ERR_INVALID_ARGUMENT,
        ),
        (
            "released file",
            Send {
                file: dead_file,
                ..valid
            },
            ERR_HANDLE_UNAVAILABLE,
        ),
        (
            "released session",
            Send {
                session: dead_session,
                ..valid
            },
            ERR_HANDLE_UNAVAILABLE,
        ),
        (
            "key utf8",
            Send {
                key: invalid_key.as_ptr().cast(),
                key_len: 1,
                ..valid
            },
            ERR_INVALID_ARGUMENT,
        ),
        (
            "unknown key",
            Send {
                key: missing_key.as_ptr(),
                key_len: 7,
                ..valid
            },
            ERR_KEY_NOT_FOUND,
        ),
        (
            "cipher",
            Send {
                cipher: 99,
                ..valid
            },
            ERR_INVALID_ARGUMENT,
        ),
        (
            "encoding",
            Send {
                encoding: 99,
                ..valid
            },
            ERR_INVALID_ARGUMENT,
        ),
        (
            "offset overflow",
            Send {
                offset: u64::MAX,
                ..valid
            },
            ERR_INVALID_ARGUMENT,
        ),
        (
            "file range",
            Send { offset: 4, ..valid },
            ERR_INVALID_ARGUMENT,
        ),
        (
            "one byte beyond file",
            Send { offset: 3, ..valid },
            ERR_INVALID_ARGUMENT,
        ),
    ] {
        assert_eq!(request.invoke(), expected, "{name}");
    }
    assert_eq!(ct_wait_connection_message_wide(server, 1), 0);
    for (cipher, offset, bytes) in [
        (1, 1, [0, 127, 128, 255]),
        (2, 1, [0, 127, 128, 255]),
        (1, 2, [127, 128, 255, 98]),
        (2, 2, [127, 128, 255, 98]),
    ] {
        let mut expected = vec![0xa2, 0x64, b'a', b'r', b'g', b's', 0x81, 0x44];
        expected.extend_from_slice(&bytes);
        expected.extend_from_slice(&[0x66, b'k', b'w', b'a', b'r', b'g', b's', 0xf6]);
        assert_eq!(
            Send {
                cipher,
                offset,
                ..valid
            }
            .invoke(),
            SUCCESS
        );
        let received = super::wide_message_handles::received_value(server, websocket, 1);
        assert_eq!(received[0], 68);
        assert_eq!(received[1], 301);
        assert_eq!(received[2], 302);
        assert_eq!(received[4].as_array().unwrap().len(), 1);
        let encrypted = base64::engine::general_purpose::STANDARD
            .decode(received[4][0].as_str().unwrap())
            .unwrap();
        assert_ne!(encrypted, expected);
        let mut decrypted = CtByteBuffer {
            ptr: ptr::null_mut(),
            len: 0,
        };
        let result = if cipher == 1 {
            ct_e2ee_session_decrypt(
                resources.session,
                ptr::null(),
                0,
                encrypted.as_ptr(),
                encrypted.len() as i32,
                &mut decrypted,
            )
        } else {
            ct_e2ee_session_decrypt_aes256gcm(
                resources.session,
                ptr::null(),
                0,
                encrypted.as_ptr(),
                encrypted.len() as i32,
                &mut decrypted,
            )
        };
        assert_eq!(result, SUCCESS);
        assert!(!decrypted.ptr.is_null());
        let actual = unsafe { std::slice::from_raw_parts(decrypted.ptr, decrypted.len) }.to_vec();
        ct_byte_buffer_free(decrypted.ptr, decrypted.len);
        assert_eq!(actual, expected);
    }
    assert_eq!(ct_wait_connection_message_wide(server, 1), 0);
}
