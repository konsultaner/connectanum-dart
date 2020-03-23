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