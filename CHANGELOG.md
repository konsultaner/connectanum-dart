### 2.2.2

- added support for PKCS#8 files

### 2.2.1

- added `ScamAuthentication#clientKey`, `ScamAuthentication.fromClientKey` and a `_reuseClientKey` option to the 
  constructors to reuse the client key for authentication to save computation time.

### 2.2.0

- updated min sdk version to 3.4.0
- replaced html by web package
  - support for wasm compilation
  - all features can be used in the browser now. No more `Unsupported operation: Uint64 accessor not supported by dart2js.`

### 2.1.0

- @yurii-prykhodko-solid reworked connection recovery with streams, added Client().disconnect()

### 2.0.5

- @yurii-prykhodko-solid enhanced external logging
- @yurii-prykhodko-solid added shorthand websocket transport factories with serializers

### 2.0.4

- @cydrickn fixed (#59) that error details should have a `dynamic` type instead of a type `object`
- @cydrickn added the field `authextra` to authentication process

### 2.0.3

- @KSDaemon added [ppt-mode](https://wamp-proto.org/wamp_latest_ietf.html#name-payload-passthru-mode) in favor of transparent payload
- prepared connectanum dart for EE2E
- new linter
- fixed unit tests in chrome

**BREAKING**

- Changed constants and static finals from UPPER_SNAKE_CASE to lowerCamelCase

### 2.0.2

- added CBOR serializer

### 2.0.1

- fix args and kwargs typing 

### 2.0.0

- do not reconnect if the server will loop with the same error
- added argon2 support (#7)
- sound null safety support
- update all dependencies to their latest version
- fixes #3 fixed test vector

### 1.1.8

- fixed cra saltless authentication

### 1.1.7

- added auth role to session on create 

### 1.1.6

- fix auth extra type
- fix fire reconnect event on unintended connection lost 

### 1.1.5

- support dynamic realm and authextra creation

### 1.1.4

- changed arguments and argumentsKeyword signature to make subtype access easier.

### 1.1.3

- completed payload transparency
- added json binary strings format, fix #25

### 1.1.2

- realm may `null`
- channel binding is just `null` not 'null'

### 1.1.1

- fixed cryposign export
- update pinacl deps

### 1.1.0

- support wamp cryptosign
- support several key loading mechanism
- added support for dynamic reconnect options (!client.connect has an api change)

### 1.0.13

- add custom subscribe options
- fixed msgpack serialization issue
- some more docs comments

### 1.0.12

- fixed an issue with the msgpack serializer
- added more unit tests

### 1.0.11

- added msgpack serializer by [@liquidiert](https://github.com/liquidiert)

### 1.0.10

- fix socket transport close throws exception

### 1.0.9

- fix authenticate serialization

### 1.0.8

- fixed error when abort is to be sent by the authentication method
- added integration test for wamp scram
- fixed call `AbstractAuthentication.hello` before sending initial hello
- inline docs for the authentication methods

### 1.0.7

- make it possible to allow self signed certificates with socket transport
- update pointy castle dependency to latest version 

### 1.0.6

- [#14](https://github.com/konsultaner/connectanum-dart/issues/14) add support for event retention
- added some more code comments
 
### 1.0.5

- [#13](https://github.com/konsultaner/connectanum-dart/issues/13) changed meta dependency to match latest flutter dependencies 

### 1.0.4

- added pedantic package
- fixed linting issues
- added public api docs

### 1.0.3

- [#11](https://github.com/konsultaner/connectanum-dart/issues/11)  fixed a null pointer issue
- added example for error handling

### 1.0.2

- library is out of beta state
- added subscription revocation

### 1.0.1-beta.2

- added travis builds
- added code coverage report
- added several unit tests
- fixed scram authentication error when the nonce was null

### 1.0.1-beta.1

- update version to make this one the latest.

### 1.0.0-beta.1

- fixed on connection lost and on disconnect events
- fixed good bye message handling in serializer 

### 1.0.0-dev.10

- found a way to handle disconnects in regular io WebSocket transport

### 1.0.0-dev.9

- added reconnect and server loss behavior
- client has a close future that may be subscribed to. It's resolved when
`transport.close()` is called
- fixed message length calculation in socket helper

*Breaking changes*

- `client.connect()` now returns a stream instead of a future to support reconnect.

### 1.0.0-dev.8

- added session close
- fixed serializer to handle incoming abort messages and serialize outgoing auth details
- added example code
- fixed publish
- added some missing tests

### 1.0.0-dev.7

- better stub import for WebSocket transport
- fixed SCRAM authentication

### 1.0.0-dev.6

- fixed hello.details serialization code
- added error in serializer for incoming messages
- added serializer logging for wrong incoming messages
- more cleanup code to meet pana analysis requirements

### 1.0.0-dev.5

- more cleanup code to meet pana analysis requirements

### 1.0.0-dev.4

- more cleanup code to meet pana analysis requirements
- added a working unit test for websocket transport in the vm

### 1.0.0-dev.3

- more cleanup code to meet pana analysis requirements

### 1.0.0-dev.2

- cleanup code to meet pana analysis requirements

### 1.0.0-dev.1

- initial deployment to https://pub.dev 
