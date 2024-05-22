enum MockKeys {
  ed25519Key,
  ed25519Pem,
  ed25519Ppk,
  ed25519OpensshPpk,
  ed25519PasswordPem,
  ed25519PasswordPpk,
  ed25519Password2Ppk
}

extension MockKeysValues on MockKeys {
  String get value {
    switch (this) {
      case MockKeys.ed25519Key:
        return '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\nQyNTUxOQAAACA0kCJ8s4iKtWHwfkmrgm+h93jZ1YnUzsxHohMrn5SrhwAAAKAgQXzlIEF8\n5QAAAAtzc2gtZWQyNTUxOQAAACA0kCJ8s4iKtWHwfkmrgm+h93jZ1YnUzsxHohMrn5Srhw\nAAAEAV54PrkN+uQ89mt/bR1P//5yvS22PO0z6r3BDhPuP+3TSQInyziIq1YfB+SauCb6H3\neNnVidTOzEeiEyuflKuHAAAAGGJ1cmtoYXJkdEBrb25zdWx0YW5lci5kZQECAwQF\n-----END OPENSSH PRIVATE KEY-----';
      case MockKeys.ed25519Pem:
        return '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtz\nc2gtZWQyNTUxOQAAACBzrHeC0mZW98aJCo8m7eatQsS94B5qoTZmjmgjTF+N5wAA\nAKBpeZFdaXmRXQAAAAtzc2gtZWQyNTUxOQAAACBzrHeC0mZW98aJCo8m7eatQsS9\n4B5qoTZmjmgjTF+N5wAAAECNSXZ3hyF6ArXwEsyro1EhoIqrsDJJagPLDtuXCiM8\n1HOsd4LSZlb3xokKjybt5q1CxL3gHmqhNmaOaCNMX43nAAAAFGVkMjU1MTkta2V5\nLTIwMjEwMjExAQIDBAUGBwgJ\n-----END OPENSSH PRIVATE KEY-----';
      case MockKeys.ed25519Ppk:
        return 'PuTTY-User-Key-File-2: ssh-ed25519\nEncryption: none\nComment: ed25519-key-20210211\nPublic-Lines: 2\nAAAAC3NzaC1lZDI1NTE5AAAAIHOsd4LSZlb3xokKjybt5q1CxL3gHmqhNmaOaCNM\nX43n\nPrivate-Lines: 1\nAAAAII1JdneHIXoCtfASzKujUSGgiquwMklqA8sO25cKIzzU\nPrivate-MAC: 4df82f0595dc6ed97d00a0982452fdb99964d1b5';
      case MockKeys.ed25519OpensshPpk:
        return 'PuTTY-User-Key-File-2: ssh-ed25519\nEncryption: none\nComment: burkhardt@konsultaner.de\nPublic-Lines: 2\nAAAAC3NzaC1lZDI1NTE5AAAAIDSQInyziIq1YfB+SauCb6H3eNnVidTOzEeiEyuf\nlKuH\nPrivate-Lines: 1\nAAAAIBXng+uQ365Dz2a39tHU///nK9LbY87TPqvcEOE+4/7d\nPrivate-MAC: cf8c8521fe0bca4a1d873e8bcea1b586325ada1a';
      case MockKeys.ed25519PasswordPem:
        return '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABAa\neYyfuq/hx8YkvZknpEWFAAAAEAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIHOs\nd4LSZlb3xokKjybt5q1CxL3gHmqhNmaOaCNMX43nAAAAoHtXp2O3U6bDvhP1tYZC\nOOGt8PCFRs8tGxEJZNJwW7foVqSMzpgX39n/GYgNfhhJQXunZk7HUoR13LGT2apP\nMy78QhW3ev2BPxWK164752SOcUhFI7RvFw7dvC+zRdL9AEDI81K56xm4k1XgTbmJ\nKo5fmLg7L1gLnmgHFVoHXyblzZs5/CIGfTl8SEk6JKqv5PBsQDw7Rg2b2XFAdgFc\nbGM=\n-----END OPENSSH PRIVATE KEY-----';
      case MockKeys.ed25519PasswordPpk:
        return 'PuTTY-User-Key-File-2: ssh-ed25519\nEncryption: aes256-cbc\nComment: ed25519-key-20210211\nPublic-Lines: 2\nAAAAC3NzaC1lZDI1NTE5AAAAIHOsd4LSZlb3xokKjybt5q1CxL3gHmqhNmaOaCNM\nX43n\nPrivate-Lines: 1\nb6LQNEHpLzACUyQLVAsbRUnKlKUVCfFEZGq5DcrAgOd8cm4EVPrdOoGrAeeJs8Av\nPrivate-MAC: 7ee3b96fa12f4f9bb12df5c3ccccc0a4eddfd8b3';
      case MockKeys.ed25519Password2Ppk:
        return 'PuTTY-User-Key-File-2: ssh-ed25519\nEncryption: aes256-cbc\nComment: ed25519-key-20210211\nPublic-Lines: 2\nAAAAC3NzaC1lZDI1NTE5AAAAIHOsd4LSZlb3xokKjybt5q1CxL3gHmqhNmaOaCNM\nX43n\nPrivate-Lines: 1\nSmcDeGVKsVnfGmkmHz4fdv57aoqfK9fYOpSWjN3hfqv748ZQ8WaKeEO9/L4B7k48\nPrivate-MAC: 6124e12f194d71a685904294d3c6dcc745480239';
      default:
        return '';
    }
  }
}
