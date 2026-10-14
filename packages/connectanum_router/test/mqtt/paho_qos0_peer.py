"""Independent Paho peer for the Dart side-by-side MQTT integration test."""

import sys
import threading

import paho.mqtt.client as mqtt


port = int(sys.argv[1])
subscribed = threading.Event()
received = threading.Event()
failure = []


def on_connect(client, userdata, flags, reason_code, properties):
    if reason_code != 0:
        failure.append(f"Paho CONNACK: {reason_code}")
        subscribed.set()
        return
    client.subscribe("test/to-paho", qos=0)


def on_subscribe(client, userdata, mid, reason_codes, properties):
    if not reason_codes or reason_codes[0].is_failure:
        failure.append("Paho SUBACK rejected")
    subscribed.set()


def on_message(client, userdata, message):
    if message.topic != "test/to-paho" or message.payload != bytes([17, 0, 255]):
        failure.append("Paho received wrong topic or payload")
    received.set()


subscriber = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, protocol=mqtt.MQTTv5)
subscriber.on_connect = on_connect
subscriber.on_subscribe = on_subscribe
subscriber.on_message = on_message
subscriber.connect("127.0.0.1", port, 10)
subscriber.loop_start()
if not subscribed.wait(5) or failure:
    raise SystemExit(failure or ["Paho SUBACK timeout"])

publisher = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, protocol=mqtt.MQTTv311)
publisher.connect("127.0.0.1", port, 10)
publisher.loop_start()
publisher.publish("test/from-paho", bytes([0, 255, 0, 17]), qos=0).wait_for_publish(5)
print("READY", flush=True)
if not received.wait(5) or failure:
    raise SystemExit(failure or ["Paho receive timeout"])
publisher.disconnect()
subscriber.disconnect()
publisher.loop_stop()
subscriber.loop_stop()
