"""Which EventBlockID makes EventEdit.Select select an event?

    python spike/38_select_rules.py PROJECT...

For each project, a scratch copy is opened and spike/38_select_targets.lua lists the first event of every voice
stream. Each is then selected through the Remote API with two candidates, and Dorico's status says whether it is
selected:
  * the instance id the dump prints as "Start block id", minus 1000 (the rule the plug-in used at first);
  * the block id of that instance, read from stream.blockInstances.
Each copy is closed unsaved.
"""
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools" / "dorico"))
import dws  # noqa: E402
import run_lua  # noqa: E402

def selects(client, flow_id, event_id, block):
    """Whether the select leaves an event selected. Status can lag a command, so it is polled; a stale status can
    say hasSelection with selectedEventType kNone, which doesn't count."""
    client.command("Edit.SelectNone")
    time.sleep(0.15)
    client.command(f"EventEdit.Select?FlowID={flow_id}&EventID={event_id}&EventBlockID={block}")
    deadline = time.time() + 1.0
    while time.time() < deadline:
        st = client.status()
        if st.get("hasSelection") and st.get("selectedEventType") not in (None, "kNone"):
            return True
        time.sleep(0.1)
    return False


def main(sources):
    for source in sources:
        client = dws.DoricoClient()
        client.connect()
        code, result, sid = run_lua.run(REPO / "spike" / "38_select_targets.lua", open_file=Path(source),
                                        keep_open=True, client=client, timeout=300)
        verified = bool(result and result["facts"].get("scratchVerified"))
        print("==", Path(source).name, "verified" if verified else "NOT VERIFIED, skipped", flush=True)
        try:
            if not verified:
                continue
            for t in result["facts"]["targets"]:
                block = next((i["blockId"] for i in t["instances"] if i["instanceId"] == t["instance"]), None)
                old = selects(client, t["flowId"], t["eventId"], t["instance"] - 1000)
                new = block is not None and selects(client, t["flowId"], t["eventId"], block)
                print(f"  flow {t['flowId']} {t['label']}: instance {t['instance']}, block {block}:"
                      f" instance-1000 {'selects' if old else 'NO'}, block id {'selects' if new else 'NO'}",
                      flush=True)
        finally:
            if verified and sid is not None:
                run_lua.close_scratch(client, sid)
            client.close()


if __name__ == "__main__":
    main(sys.argv[1:])
