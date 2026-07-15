use std::ptr;

use crate::runtime::{
    ct_byte_buffer_free, ct_e2ee_keyring_add_key, ct_e2ee_keyring_new, ct_e2ee_keyring_release,
    ct_e2ee_session_decrypt, ct_e2ee_session_decrypt_aes256gcm, ct_e2ee_session_encrypt,
    ct_e2ee_session_encrypt_aes256gcm, ct_e2ee_session_new, ct_e2ee_session_release, CtByteBuffer,
    ERR_DECRYPT_FAILED, ERR_KEY_NOT_FOUND, SUCCESS,
};

use super::test_guard;

fn add_key(handle: i32, key_id: &str, key: &[u8], make_default: bool) {
    let result = ct_e2ee_keyring_add_key(
        handle,
        key_id.as_ptr() as *const i8,
        key_id.len() as i32,
        key.as_ptr(),
        key.len() as i32,
        if make_default { 1 } else { 0 },
    );
    assert_eq!(result, SUCCESS);
}

#[test]
fn native_e2ee_round_trips_with_session_default_key() {
    let _guard = test_guard();
    let keyring = ct_e2ee_keyring_new();
    assert!(keyring > 0);
    add_key(keyring, "kid-1", &(1u8..=32u8).collect::<Vec<_>>(), true);
    let session = ct_e2ee_session_new(keyring, ptr::null(), 0);
    assert!(session > 0);

    let plaintext = b"native-e2ee-round-trip";
    let mut encrypted = CtByteBuffer {
        ptr: ptr::null_mut(),
        len: 0,
    };
    let encrypt_result = ct_e2ee_session_encrypt(
        session,
        ptr::null(),
        0,
        plaintext.as_ptr(),
        plaintext.len() as i32,
        &mut encrypted,
    );
    assert_eq!(encrypt_result, SUCCESS);
    assert!(encrypted.len > plaintext.len());

    let mut decrypted = CtByteBuffer {
        ptr: ptr::null_mut(),
        len: 0,
    };
    let decrypt_result = ct_e2ee_session_decrypt(
        session,
        ptr::null(),
        0,
        encrypted.ptr,
        encrypted.len as i32,
        &mut decrypted,
    );
    assert_eq!(decrypt_result, SUCCESS);
    let decrypted_bytes = unsafe { std::slice::from_raw_parts(decrypted.ptr, decrypted.len) };
    assert_eq!(decrypted_bytes, plaintext);

    ct_byte_buffer_free(encrypted.ptr, encrypted.len);
    ct_byte_buffer_free(decrypted.ptr, decrypted.len);
    assert_eq!(ct_e2ee_session_release(session), SUCCESS);
    assert_eq!(ct_e2ee_keyring_release(keyring), SUCCESS);
}

#[test]
fn native_e2ee_aes256gcm_round_trips_and_authenticates() {
    let _guard = test_guard();
    let keyring = ct_e2ee_keyring_new();
    assert!(keyring > 0);
    add_key(keyring, "kid-1", &(1u8..=32u8).collect::<Vec<_>>(), true);
    let session = ct_e2ee_session_new(keyring, ptr::null(), 0);
    assert!(session > 0);

    let plaintext = b"native-e2ee-aes256gcm-round-trip";
    let mut encrypted = CtByteBuffer {
        ptr: ptr::null_mut(),
        len: 0,
    };
    assert_eq!(
        ct_e2ee_session_encrypt_aes256gcm(
            session,
            ptr::null(),
            0,
            plaintext.as_ptr(),
            plaintext.len() as i32,
            &mut encrypted,
        ),
        SUCCESS,
    );
    assert_eq!(encrypted.len, plaintext.len() + 12 + 16);

    let mut decrypted = CtByteBuffer {
        ptr: ptr::null_mut(),
        len: 0,
    };
    assert_eq!(
        ct_e2ee_session_decrypt_aes256gcm(
            session,
            ptr::null(),
            0,
            encrypted.ptr,
            encrypted.len as i32,
            &mut decrypted,
        ),
        SUCCESS,
    );
    let decrypted_bytes = unsafe { std::slice::from_raw_parts(decrypted.ptr, decrypted.len) };
    assert_eq!(decrypted_bytes, plaintext);

    let encrypted_bytes = unsafe { std::slice::from_raw_parts_mut(encrypted.ptr, encrypted.len) };
    encrypted_bytes[encrypted.len - 1] ^= 1;
    assert_eq!(
        ct_e2ee_session_decrypt_aes256gcm(
            session,
            ptr::null(),
            0,
            encrypted.ptr,
            encrypted.len as i32,
            &mut decrypted,
        ),
        ERR_DECRYPT_FAILED,
    );

    ct_byte_buffer_free(encrypted.ptr, encrypted.len);
    ct_byte_buffer_free(decrypted.ptr, decrypted.len);
    assert_eq!(ct_e2ee_session_release(session), SUCCESS);
    assert_eq!(ct_e2ee_keyring_release(keyring), SUCCESS);
}

#[test]
fn native_e2ee_uses_explicit_session_default_key_id() {
    let _guard = test_guard();
    let keyring = ct_e2ee_keyring_new();
    assert!(keyring > 0);
    add_key(keyring, "kid-a", &(1u8..=32u8).collect::<Vec<_>>(), false);
    add_key(keyring, "kid-b", &(33u8..=64u8).collect::<Vec<_>>(), false);

    let session = ct_e2ee_session_new(keyring, "kid-b".as_ptr() as *const i8, 5);
    assert!(session > 0);

    let plaintext = b"session-default-key";
    let mut encrypted = CtByteBuffer {
        ptr: ptr::null_mut(),
        len: 0,
    };
    let encrypt_result = ct_e2ee_session_encrypt(
        session,
        ptr::null(),
        0,
        plaintext.as_ptr(),
        plaintext.len() as i32,
        &mut encrypted,
    );
    assert_eq!(encrypt_result, SUCCESS);

    let mut decrypted = CtByteBuffer {
        ptr: ptr::null_mut(),
        len: 0,
    };
    let decrypt_result = ct_e2ee_session_decrypt(
        session,
        "kid-b".as_ptr() as *const i8,
        5,
        encrypted.ptr,
        encrypted.len as i32,
        &mut decrypted,
    );
    assert_eq!(decrypt_result, SUCCESS);
    let decrypted_bytes = unsafe { std::slice::from_raw_parts(decrypted.ptr, decrypted.len) };
    assert_eq!(decrypted_bytes, plaintext);

    ct_byte_buffer_free(encrypted.ptr, encrypted.len);
    ct_byte_buffer_free(decrypted.ptr, decrypted.len);
    assert_eq!(ct_e2ee_session_release(session), SUCCESS);
    assert_eq!(ct_e2ee_keyring_release(keyring), SUCCESS);
}

#[test]
fn native_e2ee_reports_missing_keys_and_decrypt_failures() {
    let _guard = test_guard();
    let keyring = ct_e2ee_keyring_new();
    assert!(keyring > 0);
    add_key(keyring, "kid-1", &(1u8..=32u8).collect::<Vec<_>>(), true);
    add_key(keyring, "kid-2", &(33u8..=64u8).collect::<Vec<_>>(), false);
    let session = ct_e2ee_session_new(keyring, ptr::null(), 0);
    assert!(session > 0);

    let mut encrypted = CtByteBuffer {
        ptr: ptr::null_mut(),
        len: 0,
    };
    let plaintext = b"ciphertext";
    assert_eq!(
        ct_e2ee_session_encrypt(
            session,
            "missing".as_ptr() as *const i8,
            7,
            plaintext.as_ptr(),
            plaintext.len() as i32,
            &mut encrypted,
        ),
        ERR_KEY_NOT_FOUND,
    );

    assert_eq!(
        ct_e2ee_session_encrypt(
            session,
            "kid-1".as_ptr() as *const i8,
            5,
            plaintext.as_ptr(),
            plaintext.len() as i32,
            &mut encrypted,
        ),
        SUCCESS,
    );

    let mut decrypted = CtByteBuffer {
        ptr: ptr::null_mut(),
        len: 0,
    };
    assert_eq!(
        ct_e2ee_session_decrypt(
            session,
            "kid-2".as_ptr() as *const i8,
            5,
            encrypted.ptr,
            encrypted.len as i32,
            &mut decrypted,
        ),
        ERR_DECRYPT_FAILED,
    );

    ct_byte_buffer_free(encrypted.ptr, encrypted.len);
    assert_eq!(ct_e2ee_session_release(session), SUCCESS);
    assert_eq!(ct_e2ee_keyring_release(keyring), SUCCESS);
}
