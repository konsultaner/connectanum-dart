use super::*;

#[test]
fn xsalsa_wire_matches_allocating_backend_in_both_directions() {
    let key = [7_u8; 32];
    let cipher = XSalsa20Poly1305::new(&normalize_key_material(&key).unwrap());
    for length in [0, 1, 15, 16, 17, 64 * 1024] {
        let plaintext = (0..length).map(|i| (i % 251) as u8).collect::<Vec<_>>();
        let original = plaintext.clone();
        let encrypted = encrypt_e2ee_payload(&key, &plaintext).unwrap();
        assert_eq!(encrypted.len(), E2EE_NONCE_LEN + E2EE_AUTH_TAG_LEN + length);
        let nonce = Nonce::from_slice(&encrypted[..E2EE_NONCE_LEN]);
        let reference = cipher.encrypt(nonce, plaintext.as_slice()).unwrap();
        assert_eq!(&encrypted[E2EE_NONCE_LEN..], reference);
        assert_eq!(
            cipher.decrypt(nonce, &encrypted[E2EE_NONCE_LEN..]).unwrap(),
            plaintext
        );
        let mut reference_wire = nonce.as_slice().to_vec();
        reference_wire.extend_from_slice(&reference);
        assert_eq!(
            decrypt_e2ee_payload(&key, &reference_wire).unwrap(),
            plaintext
        );
        assert_eq!(plaintext, original, "immutable encryption input changed");
        assert_eq!(
            encrypted, reference_wire,
            "immutable decryption input changed"
        );
    }
}

#[test]
fn xsalsa_short_and_tampered_inputs_keep_error_contract() {
    let key = [7_u8; 32];
    for length in 0..E2EE_NONCE_LEN + E2EE_AUTH_TAG_LEN {
        assert_eq!(
            decrypt_e2ee_payload(&key, &vec![0; length]),
            Err(if length < E2EE_NONCE_LEN {
                ERR_INVALID_ARGUMENT
            } else {
                ERR_DECRYPT_FAILED
            })
        );
    }
    let encrypted = encrypt_e2ee_payload(&key, b"authenticated payload").unwrap();
    for index in [0, E2EE_NONCE_LEN, E2EE_NONCE_LEN + E2EE_AUTH_TAG_LEN] {
        let mut tampered = encrypted.clone();
        tampered[index] ^= 1;
        assert_eq!(
            decrypt_e2ee_payload(&key, &tampered),
            Err(ERR_DECRYPT_FAILED)
        );
    }
    assert_eq!(
        decrypt_e2ee_payload(&[8_u8; 32], &encrypted),
        Err(ERR_DECRYPT_FAILED)
    );
}

#[test]
fn crypto_staging_oracle_counts_real_copies_including_failed_authentication() {
    use super::super::crypto_copy_metrics::observed_on_current_thread;
    let key = [7_u8; 32];
    for length in [0, 1, 64 * 1024] {
        let plaintext = vec![42; length];
        for aes in [false, true] {
            let before = observed_on_current_thread();
            let mut encrypted = if aes {
                encrypt_e2ee_aes256_gcm_payload(&key, &plaintext).unwrap()
            } else {
                encrypt_e2ee_payload(&key, &plaintext).unwrap()
            };
            let after = observed_on_current_thread();
            assert_eq!(
                after.plaintext_staging_copy_bytes_total
                    - before.plaintext_staging_copy_bytes_total,
                length as u64
            );
            assert_eq!(
                after.ciphertext_staging_copy_bytes_total,
                before.ciphertext_staging_copy_bytes_total
            );
            let decrypt = if aes {
                decrypt_e2ee_aes256_gcm_payload
            } else {
                decrypt_e2ee_payload
            };
            let copied = (length + if aes { E2EE_AUTH_TAG_LEN } else { 0 }) as u64;
            let before = observed_on_current_thread();
            assert_eq!(decrypt(&key, &encrypted).unwrap(), plaintext);
            let after = observed_on_current_thread();
            assert_eq!(
                after.ciphertext_staging_copy_bytes_total
                    - before.ciphertext_staging_copy_bytes_total,
                copied
            );
            let index = if aes {
                E2EE_AES256_GCM_NONCE_LEN
            } else {
                E2EE_NONCE_LEN
            };
            encrypted[index] ^= 1;
            let before = observed_on_current_thread();
            assert_eq!(decrypt(&key, &encrypted), Err(ERR_DECRYPT_FAILED));
            let after = observed_on_current_thread();
            assert_eq!(
                after.ciphertext_staging_copy_bytes_total
                    - before.ciphertext_staging_copy_bytes_total,
                copied
            );
        }
    }
}

#[test]
fn aes_consuming_decryption_reuses_storage_without_crypto_staging_copy() {
    use super::super::crypto_copy_metrics::observed_on_current_thread;
    let key = [7_u8; 32];
    let plaintext = vec![42; 64 * 1024];
    let encrypted = encrypt_e2ee_aes256_gcm_payload(&key, &plaintext).unwrap();
    let prefix = 7;
    let mut container = vec![0x5a; prefix];
    container.extend_from_slice(&encrypted);
    container.extend_from_slice(&[0xa5; 9]);
    let pointer = container.as_ptr();
    let before = observed_on_current_thread();
    let clear = decrypt_e2ee_aes256_gcm_payload_in_place(
        &key,
        &mut container,
        prefix..prefix + encrypted.len(),
    )
    .unwrap();
    assert_eq!(container.as_ptr(), pointer);
    assert_eq!(&container[clear], plaintext);
    assert_eq!(&container[..prefix], &[0x5a; 7]);
    assert_eq!(&container[prefix + encrypted.len()..], &[0xa5; 9]);
    assert_eq!(observed_on_current_thread(), before);
    assert_eq!(
        super::super::crypto_copy_metrics::ct_e2ee_copy_metrics_abi_version(),
        1
    );
    assert_eq!(
        super::super::crypto_copy_metrics::ct_e2ee_copy_metrics_snapshot(ptr::null_mut()),
        ERR_INVALID_ARGUMENT
    );
    let mut process = super::super::crypto_copy_metrics::CtE2eeCopyMetricsInfo::default();
    assert_eq!(
        super::super::crypto_copy_metrics::ct_e2ee_copy_metrics_snapshot(&mut process),
        SUCCESS
    );
    assert!(
        process.plaintext_staging_copy_bytes_total >= before.plaintext_staging_copy_bytes_total
    );
}
