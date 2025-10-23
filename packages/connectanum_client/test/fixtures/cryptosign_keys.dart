/// Local copy of cryptosign test keys so client tests do not depend on core
/// package internals.
enum MockCryptosignKey {
  ed25519Key,
  ed25519Pem,
  ed25519Ppk,
  ed25519OpensshPkcs8,
  ed25519OpensshPpk,
  ed25519PasswordPem,
  ed25519PasswordPpk,
  ed25519Password2Ppk,
}

extension MockCryptosignKeyValues on MockCryptosignKey {
  String get value {
    switch (this) {
      case MockCryptosignKey.ed25519Key:
        return '-----BEGIN OPENSSH PRIVATE KEY-----\n'
            'b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\n'
            'QyNTUxOQAAACA0kCJ8s4iKtWHwfkmrgm+h93jZ1YnUzsxHohMrn5SrhwAAAKAgQXzlIEF8\n'
            '5QAAAAtzc2gtZWQyNTUxOQAAACA0kCJ8s4iKtWHwfkmrgm+h93jZ1YnUzsxHohMrn5Srhw\n'
            'AAAEAV54PrkN+uQ89mt/bR1P//5yvS22PO0z6r3BDhPuP+3TSQInyziIq1YfB+SauCb6H3\n'
            'eNnVidTOzEeiEyuflKuHAAAAGGJ1cmtoYXJkdEBrb25zdWx0YW5lci5kZQECAwQF\n'
            '-----END OPENSSH PRIVATE KEY-----';
      case MockCryptosignKey.ed25519Pem:
        return '-----BEGIN OPENSSH PRIVATE KEY-----\n'
            'b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtz\n'
            'c2gtZWQyNTUxOQAAACBzrHeC0mZW98aJCo8m7eatQsS94B5qoTZmjmgjTF+N5wAA\n'
            'AKBpeZFdaXmRXQAAAAtzc2gtZWQyNTUxOQAAACBzrHeC0mZW98aJCo8m7eatQsS9\n'
            '4B5qoTZmjmgjTF+N5wAAAECNSXZ3hyF6ArXwEsyro1EhoIqrsDJJagPLDtuXCiM8\n'
            '1HOsd4LSZlb3xokKjybt5q1CxL3gHmqhNmaOaCNMX43nAAAAFGVkMjU1MTkta2V5\n'
            'LTIwMjEwMjExAQIDBAUGBwgJ\n'
            '-----END OPENSSH PRIVATE KEY-----';
      case MockCryptosignKey.ed25519Ppk:
        return 'PuTTY-User-Key-File-2: ssh-ed25519\n'
            'Encryption: none\n'
            'Comment: ed25519-key-20210211\n'
            'Public-Lines: 2\n'
            'AAAAC3NzaC1lZDI1NTE5AAAAIHOsd4LSZlb3xokKjybt5q1CxL3gHmqhNmaOaCNM\n'
            'X43n\n'
            'Private-Lines: 1\n'
            'AAAAII1JdneHIXoCtfASzKujUSGgiquwMklqA8sO25cKIzzU\n'
            'Private-MAC: 4df82f0595dc6ed97d00a0982452fdb99964d1b5';
      case MockCryptosignKey.ed25519OpensshPkcs8:
        return '-----BEGIN PRIVATE KEY-----\n'
            'MC4CAQAwBQYDK2VwBCIEIBXng+uQ365Dz2a39tHU///nK9LbY87TPqvcEOE+4/7d\n'
            '-----END PRIVATE KEY-----';
      case MockCryptosignKey.ed25519OpensshPpk:
        return 'PuTTY-User-Key-File-2: ssh-ed25519\n'
            'Encryption: none\n'
            'Comment: burkhardt@konsultaner.de\n'
            'Public-Lines: 2\n'
            'AAAAC3NzaC1lZDI1NTE5AAAAIDSQInyziIq1YfB+SauCb6H3eNnVidTOzEeiEyuf\n'
            'lKuH\n'
            'Private-Lines: 1\n'
            'AAAAIBXng+uQ365Dz2a39tHU///nK9LbY87TPqvcEOE+4/7d\n'
            'Private-MAC: cf8c8521fe0bca4a1d873e8bcea1b586325ada1a';
      case MockCryptosignKey.ed25519PasswordPem:
        return '-----BEGIN OPENSSH PRIVATE KEY-----\n'
            'b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABAa\n'
            'eYyfuq/hx8YkvZknpEWFAAAAEAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIHOs\n'
            'd4LSZlb3xokKjybt5q1CxL3gHmqhNmaOaCNMX43nAAAAoHtXp2O3U6bDvhP1tYZC\n'
            'OOGt8PCFRs8tGxEJZNJwW7foVqSMzpgX39n/GYgNfhhJQXunZk7HUoR13LGT2apP\n'
            'My78QhW3ev2BPxWK164752SOcUhFI7RvFw7dvC+zRdL9AEDI81K56xm4k1XgTbmJ\n'
            'Ko5fmLg7L1gLnmgHFVoHXyblzZs5/CIGfTl8SEk6JKqv5PBsQDw7Rg2b2XFAdgFc\n'
            'bGM=\n'
            '-----END OPENSSH PRIVATE KEY-----';
      case MockCryptosignKey.ed25519PasswordPpk:
        return 'PuTTY-User-Key-File-2: ssh-ed25519\n'
            'Encryption: aes256-cbc\n'
            'Comment: ed25519-key-20210211\n'
            'Public-Lines: 2\n'
            'AAAAC3NzaC1lZDI1NTE5AAAAIHOsd4LSZlb3xokKjybt5q1CxL3gHmqhNmaOaCNM\n'
            'X43n\n'
            'Private-Lines: 1\n'
            'b6LQNEHpLzACUyQLVAsbRUnKlKUVCfFEZGq5DcrAgOd8cm4EVPrdOoGrAeeJs8Av\n'
            'Private-MAC: 7ee3b96fa12f4f9bb12df5c3ccccc0a4eddfd8b3';
      case MockCryptosignKey.ed25519Password2Ppk:
        return 'PuTTY-User-Key-File-2: ssh-ed25519\n'
            'Encryption: aes256-cbc\n'
            'Comment: ed25519-key-20210211\n'
            'Public-Lines: 2\n'
            'AAAAC3NzaC1lZDI1NTE5AAAAIHOsd4LSZlb3xokKjybt5q1CxL3gHmqhNmaOaCNM\n'
            'X43n\n'
            'Private-Lines: 1\n'
            'SmcDeGVKsVnfGmkmHz4fdv57aoqfK9fYOpSWjN3hfqv748ZQ8WaKeEO9/L4B7k48\n'
            'Private-MAC: 6124e12f194d71a685904294d3c6dcc745480239';
    }
  }
}
