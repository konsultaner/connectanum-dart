"""Independent live WAMP peer for the negotiated Connectanum metadata profile."""

import importlib
import io
import importlib.metadata
import json
import socket
import sys

import flatbuffers

if not __debug__:
    raise SystemExit("The reference peer requires Python assertions")
import cbor2
from websockets.sync.client import connect
from websockets.exceptions import ConnectionClosed

sys.path.insert(0, sys.argv[1])
PORT = int(sys.argv[2])
TRANSPORT = sys.argv[3]
assert TRANSPORT in ("rawsocket", "websocket")
MAX_ID = 9007199254740991
MAX_FRAME = 1 << 20
FEATURE = "_connectanum_flatbuffers_metadata_v1"
NO_DICTIONARY = {"Published", "Subscribed", "Unsubscribe", "Registered", "Unregister"}


def module(name):
    return importlib.import_module("wamp.proto." + name)


TAGS = module("AnyMessage").AnyMessage
NAMES = {getattr(TAGS, name): name for name in (
    "Hello", "Welcome", "Abort", "Challenge", "Authenticate", "Goodbye",
    "Error", "Publish", "Published", "Subscribe", "Subscribed", "Unsubscribe",
    "Unsubscribed", "Event", "Call", "Cancel", "Result", "Register",
    "Registered", "Unregister", "Unregistered", "Invocation", "Interrupt", "Yield",
)}


def roles(builder):
    offsets = {}
    for role in ("Publisher", "Subscriber", "Caller", "Callee"):
        name = role + "Features"
        obj = module(name)
        getattr(obj, name + "Start")(builder)
        if role in ("Caller", "Callee"):
            getattr(obj, name + "AddProgressiveCallResults")(builder, True)
            getattr(obj, name + "AddCallCanceling")(builder, True)
        offsets[role] = getattr(obj, name + "End")(builder)
    obj = module("ClientRoles")
    obj.ClientRolesStart(builder)
    for role, offset in offsets.items():
        getattr(obj, "ClientRolesAdd" + role)(builder, offset)
    return obj.ClientRolesEnd(builder)


def metadata(name, fields):
    if name in NO_DICTIONARY:
        return None
    if name == "Hello":
        features = {FEATURE: True}
        return {
            "authmethods": ["ticket"], "authid": "alice",
            "roles": {
                "publisher": {"features": features.copy()},
                "subscriber": {"features": features.copy()},
                "caller": {"features": dict(features, progressive_call_results=True, call_canceling=True)},
                "callee": {"features": dict(features, progressive_call_results=True, call_canceling=True)},
            },
        }
    result = {}
    for field, key in (("Acknowledge", "acknowledge"), ("ReceiveProgress", "receive_progress"), ("Progress", "progress")):
        if field in fields:
            result[key] = fields[field]
    if "Mode" in fields:
        result["mode"] = {0: "skip", 1: "kill", 2: "killnowait"}[fields["Mode"]]
    return result


def frame(name, _bare=False, _capability=True, **fields):
    builder = flatbuffers.Builder(128)
    table = module(name)
    values = {}
    for key, value in fields.items():
        if key == "Roles":
            value = roles(builder)
        elif key == "Authmethods":
            table.HelloStartAuthmethodsVector(builder, len(value))
            for number in reversed(value):
                builder.PrependUint8(number)
            value = builder.EndVector()
        elif isinstance(value, str):
            value = builder.CreateString(value)
        elif isinstance(value, bytes):
            value = builder.CreateByteVector(value)
        values[key] = value
    dictionary = metadata(name, fields)
    if name == "Hello" and _capability is not True:
        for role in dictionary["roles"].values():
            if _capability is None:
                role["features"].pop(FEATURE)
            else:
                role["features"][FEATURE] = _capability
    encoded_metadata = builder.CreateByteVector(cbor2.dumps(dictionary)) if dictionary is not None and not _bare else None
    getattr(table, name + "Start")(builder)
    for key, value in values.items():
        getattr(table, name + "Add" + key)(builder, value)
    value = getattr(table, name + "End")(builder)
    root = module("Message")
    root.MessageStart(builder)
    root.MessageAddMsgType(builder, getattr(TAGS, name))
    root.MessageAddMsg(builder, value)
    if encoded_metadata is not None:
        root.MessageAddMetadata(builder, encoded_metadata)
    builder.Finish(root.MessageEnd(builder))
    return bytes(builder.Output())


def fragment(table, name):
    getter = getattr(table, name)
    return bytes(getter(i) for i in range(getattr(table, name + "Length")()))


def cbor_header(major, value):
    prefix = major << 5
    if value < 24:
        return bytes([prefix | value])
    for size, suffix in ((1, 24), (2, 25), (4, 26), (8, 27)):
        if value < 1 << (size * 8):
            return bytes([prefix | suffix]) + value.to_bytes(size, "big")
    raise ValueError("Fixture integer exceeds uint64")


def text(value):
    data = value.encode("utf-8")
    return cbor_header(3, len(data)) + data


def payload(seq, size):
    data = bytes(i % 251 for i in range(size))
    args = (cbor_header(4, 3) + cbor_header(0, MAX_ID) + text("héllo")
            + cbor_header(2, len(data)) + data)
    kwargs = (cbor_header(5, 2) + text("seq") + cbor_header(0, seq)
              + text("empty") + cbor_header(4, 0))
    return args, kwargs


class Peer:
    def __init__(self):
        self.session = None
        if TRANSPORT == "websocket":
            self.websocket = connect(
                f"ws://127.0.0.1:{PORT}/wamp", subprotocols=["wamp.2.flatbuffers"],
                open_timeout=5, close_timeout=5, max_size=MAX_FRAME, proxy=None,
            )
            assert self.websocket.subprotocol == "wamp.2.flatbuffers"
            return
        self.socket = socket.create_connection(("127.0.0.1", PORT), timeout=5)
        self.socket.settimeout(5)
        self.socket.sendall(bytes([0x7F, 0xB5, 0, 0]))
        reply = self.read_exact(4)
        assert reply[0] == 0x7F and reply[1] & 15 == 5 and reply[2:] == b"\0\0", reply
        self.session = None

    def read_exact(self, size):
        result = bytearray()
        while len(result) < size:
            part = self.socket.recv(size - len(result))
            if not part:
                raise EOFError("Peer disconnected before completing a frame")
            result.extend(part)
        return bytes(result)

    def send(self, name, fragmented=False, **fields):
        data = frame(name, **fields)
        assert 0 < len(data) <= MAX_FRAME
        if TRANSPORT == "websocket":
            self.websocket.send([data[offset:offset + 997] for offset in range(0, len(data), 997)] if fragmented else data)
            return
        header = bytes([0]) + len(data).to_bytes(3, "big")
        if fragmented:
            self.socket.sendall(header[:1])
            self.socket.sendall(header[1:])
            for offset in range(0, len(data), 997):
                self.socket.sendall(data[offset:offset + 997])
        else:
            self.socket.sendall(header + data)

    def receive(self, expected):
        if TRANSPORT == "websocket":
            try:
                data = self.websocket.recv(timeout=5)
            except ConnectionClosed as error:
                raise EOFError("Peer closed WebSocket before the expected WAMP message") from error
            assert isinstance(data, bytes) and 0 < len(data) <= MAX_FRAME
        else:
            header = self.read_exact(4)
            assert header[0] == 0, header
            length = int.from_bytes(header[1:], "big")
            assert 0 < length <= MAX_FRAME, length
            data = self.read_exact(length)
        root = module("Message").Message.GetRootAs(data, 0)
        actual = NAMES.get(root.MsgType())
        assert actual == expected, (actual, expected)
        if expected in NO_DICTIONARY:
            assert root.MetadataIsNone(), expected
            self.metadata = None
        else:
            assert not root.MetadataIsNone(), expected
            stream = io.BytesIO(fragment(root, "Metadata"))
            self.metadata = cbor2.CBORDecoder(stream).decode()
            assert stream.read() == b"" and isinstance(self.metadata, dict), expected
        table = root.Msg()
        result = getattr(module(expected), expected)()
        result.Init(table.Bytes, table.Pos)
        return result

    def login(self, valid=True):
        self.send("Hello", Roles=True, Realm="realm1", Authmethods=[1], Authid="alice")
        challenge = self.receive("Challenge")
        assert challenge.Method() == 1
        assert self.metadata.get(FEATURE) is True, self.metadata
        self.send("Authenticate", Signature="profile-ticket" if valid else "incorrect")
        if not valid:
            abort = self.receive("Abort")
            assert abort.Reason().startswith(b"wamp.error.")
            return
        welcome = self.receive("Welcome")
        assert 0 < welcome.Session() <= MAX_ID
        assert welcome.Realm() == b"realm1" and welcome.Authid() == b"alice"
        assert welcome.Authmethod() == 1 and welcome.Authrole() == b"anonymous"
        assert welcome.Roles().Broker() is not None and welcome.Roles().Dealer() is not None
        for role in ("broker", "dealer"):
            assert self.metadata["roles"][role]["features"].get(FEATURE) is True
        self.session = welcome.Session()

    def goodbye(self):
        self.send("Goodbye", Reason="wamp.close.normal")
        assert self.receive("Goodbye").Reason() == b"wamp.close.goodbye_and_out"

    def close(self):
        if TRANSPORT == "websocket":
            self.websocket.close()
        else:
            self.socket.close()


def run():
    peers = []
    completed = []
    try:
        bare = Peer()
        peers.append(bare)
        bare.send("Hello", _bare=True, Roles=True, Realm="realm1", Authmethods=[1], Authid="alice")
        try:
            bare.receive("Challenge")
        except EOFError:
            pass
        else:
            raise AssertionError("An upstream-only peer was accepted by the strict metadata profile")
        completed.append("upstream-only-peer-rejected-before-credentials")
        for capability in (None, False):
            unsupported = Peer()
            peers.append(unsupported)
            unsupported.send("Hello", _capability=capability, Roles=True, Realm="realm1", Authmethods=[1], Authid="alice")
            assert unsupported.receive("Abort").Reason() == b"wamp.error.protocol_violation"
        completed.append("nonadvertising-peer-abort-before-credentials")
        bad = Peer()
        peers.append(bad)
        bad.login(valid=False)
        completed.append("invalid-ticket-abort")
        caller, callee = Peer(), Peer()
        peers.extend([caller, callee])
        caller.login()
        callee.login()
        assert caller.session != callee.session
        completed.append("distinct-ticket-sessions")
        callee.send("Register", Request=101, Procedure="com.python.echo")
        registered = callee.receive("Registered")
        assert registered.Request() == 101 and registered.Registration() > 0
        registration = registered.Registration()
        for index, size in enumerate((0, 17, 96 * 1024)):
            request = MAX_ID - index
            args, kwargs = payload(request, size)
            caller.send("Call", fragmented=True, Request=request, Procedure="com.python.echo", Args=args, Kwargs=kwargs)
            invocation = callee.receive("Invocation")
            assert invocation.Registration() == registration and invocation.Request() > 0
            assert fragment(invocation, "Args") == args and fragment(invocation, "Kwargs") == kwargs
            callee.send("Yield", Request=invocation.Request(), Args=args, Kwargs=kwargs)
            result = caller.receive("Result")
            assert result.Request() == request and not result.Progress()
            assert fragment(result, "Args") == args and fragment(result, "Kwargs") == kwargs
        completed.append("fragmented-rpc-empty-small-large-wide-id-utf8-binary-kwargs")
        caller.send("Call", Request=301, Procedure="com.python.echo", ReceiveProgress=True)
        invocation = callee.receive("Invocation")
        assert callee.metadata.get("receive_progress") is True, callee.metadata
        for progress in (True, False):
            callee.send("Yield", Request=invocation.Request(), Progress=progress, Args=b"\x81\x07")
            result = caller.receive("Result")
            assert result.Request() == 301 and result.Progress() == progress
            assert caller.metadata.get("progress", False) == progress, caller.metadata
            assert fragment(result, "Args") == b"\x81\x07"
        completed.append("progressive-and-final-result")
        caller.send("Call", Request=302, Procedure="com.python.echo")
        invocation = callee.receive("Invocation")
        callee.send("Error", RequestType=68, Request=invocation.Request(), Error="com.python.error", Args=b"\x81\x08")
        error = caller.receive("Error")
        assert error.RequestType() == 48 and error.Request() == 302 and error.Error() == b"com.python.error"
        assert fragment(error, "Args") == b"\x81\x08"
        completed.append("callee-error-remaps-request")
        caller.send("Call", Request=303, Procedure="com.python.echo")
        invocation = callee.receive("Invocation")
        caller.send("Cancel", Request=303, Mode=2)
        interrupt = callee.receive("Interrupt")
        assert interrupt.Request() == invocation.Request() and interrupt.Mode() == 2
        assert callee.metadata.get("mode") == "killnowait", callee.metadata
        error = caller.receive("Error")
        assert error.RequestType() == 48 and error.Request() == 303 and error.Error() == b"wamp.error.canceled", (error.RequestType(), error.Request(), error.Error(), caller.metadata)
        completed.append("killnowait-cancel-interrupt")
        callee.send("Subscribe", Request=401, Topic="com.python.topic")
        subscribed = callee.receive("Subscribed")
        assert subscribed.Request() == 401 and subscribed.Subscription() > 0
        args, kwargs = payload(402, 8192)
        caller.send("Publish", Request=402, Topic="com.python.topic", Acknowledge=True, Args=args, Kwargs=kwargs)
        published = caller.receive("Published")
        event = callee.receive("Event")
        assert published.Request() == 402 and published.Publication() > 0
        assert event.Subscription() == subscribed.Subscription() and event.Publication() == published.Publication()
        assert fragment(event, "Args") == args and fragment(event, "Kwargs") == kwargs
        completed.append("acknowledged-pubsub")
        callee.send("Unsubscribe", Request=403, Subscription=subscribed.Subscription())
        assert callee.receive("Unsubscribed").Request() == 403
        callee.send("Unregister", Request=404, Registration=registration)
        assert callee.receive("Unregistered").Request() == 404
        caller.send("Call", Request=405, Procedure="com.python.echo")
        error = caller.receive("Error")
        assert error.RequestType() == 48 and error.Request() == 405 and error.Error() == b"wamp.error.no_such_procedure"
        completed.append("unsubscribe-unregister-missing-procedure")
        caller.goodbye()
        callee.goodbye()
        completed.append("goodbye")
        print(json.dumps({"status": "passed", "transport": TRANSPORT, "websocketRuntime": importlib.metadata.version("websockets"), "flatbuffersRuntime": flatbuffers.__version__, "schema": "connectanum-metadata-v1", "cborRuntime": importlib.metadata.version("cbor2"), "checks": completed}))
    finally:
        for peer in peers:
            peer.close()


if __name__ == "__main__":
    run()
