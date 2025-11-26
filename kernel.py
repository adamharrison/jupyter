#!/usr/bin/env python3

import sys
import json
import threading
import queue
import traceback
import uuid
import time
import base64
import numpy as np
import io
from PIL import Image

from ipykernel.inprocess.client import InProcessKernelClient
from ipykernel.inprocess.manager import InProcessKernelManager

class InProcessKernelWrapper:
    def __init__(self):
        # Create manager + kernel and client
        self.km = InProcessKernelManager()
        self.km.start_kernel()
        self.client = self.km.client()
        self.client.start_channels()
        # queue for iopub messages
        self.iopub_q = queue.Queue()
        # start a thread to collect iopub messages
        self._stop = threading.Event()
        self._collector = threading.Thread(target=self._collect_iopub)
        self._collector.daemon = True
        self._collector.start()
        

    def _collect_iopub(self):
        ch = self.client.iopub_channel
        while not self._stop.is_set():
            try:
                msg = ch.get_msg(timeout=0.1)
            except Exception:
                continue
            self.iopub_q.put(msg)

    def execute(self, code, silent=False, timeout=5):
        # send execute request
        msg_id = self.client.execute(code, silent=silent)
        outputs = []
        ename = evalue = None
        status = "ok"
        deadline = None if timeout is None else (time.time() + timeout)
        while True:
            try:
                shell_msg = self.client.get_shell_msg(timeout=0.01)
            except Exception:
                shell_msg = None

            if shell_msg and shell_msg.get("parent_header", {}).get("msg_id") == msg_id:
                content = shell_msg.get("content", {})
                if content.get("status") == "error":
                    status = "error"
                    ename = content.get("ename")
                    evalue = content.get("evalue")
                break

            try:
                im = self.iopub_q.get(timeout=0.01)
            except Exception:
                im = None

            if im is not None:
                mtype = im.get("msg_type")
                content = im.get("content", {})
                if mtype == "stream":
                    outputs.append({"type": "stream", "name": content.get("name"), "text": content.get("text")})
                elif mtype == "display_data":
                    outputs.append({"type": "display_data", "data": content.get("data"), "metadata": content.get("metadata")})
                elif mtype == "execute_result":
                    outputs.append({"type": "result", "data": content.get("data"), "metadata": content.get("metadata")})
                elif mtype == "error":
                    outputs.append({"type": "error", "traceback": content.get("traceback")})
                else:
                    # ignore other types for brevity
                    pass

            if deadline is not None and time.time() > deadline:
                outputs.append({"type": "error", "text": "execution timeout"})
                status = "error"
                break

        # drain any remaining iopub messages for a short period
        t0 = time.time()
        while time.time() - t0 < 0.05:
            try:
                im = self.iopub_q.get(timeout=0.01)
            except Exception:
                break
            if im is not None:
                mtype = im.get("msg_type")
                content = im.get("content", {})
                if mtype == "stream":
                    outputs.append({"type": "stream", "name": content.get("name"), "text": content.get("text")})
                elif mtype == "display_data":
                    outputs.append({"type": "display_data", "data": content.get("data"), "metadata": content.get("metadata")})
                elif mtype == "execute_result":
                    outputs.append({"type": "result", "data": content.get("data"), "metadata": content.get("metadata")})
                elif mtype == "error":
                    outputs.append({"type": "error", "traceback": content.get("traceback")})

        return status, outputs, ename, evalue

    def shutdown(self):
        self._stop.set()
        self.client.stop_channels()
        self.km.shutdown_kernel()
    
    def process_request(self, req):
        req_id = req.get("id") or str(uuid.uuid4())
        action = req.get("action")
        code = req.get("code", "")
        silent = bool(req.get("silent", False))

        if action == "execute":
            try:
                status, outputs, ename, evalue = self.execute(code, silent=silent, timeout=req.get("timeout", None))
                for output in outputs:
                    if output["type"] == "display_data" and output["data"] and output["data"]["image/png"]:
                        png_bytes = base64.b64decode(output["data"]["image/png"])
                        img = Image.open(io.BytesIO(png_bytes))
                        output["metadata"]["width"] = img.width
                        output["metadata"]["height"] = img.height
                        channels = 3
                        output["metadata"]["channels"] = channels
                        output["metadata"]["size"] = img.width * img.height * channels
                        output["data"].pop("image/png")
                        output["data"]["image/raw"] = base64.b64encode(np.array(img)).decode('ascii')

                resp = {"id": req_id, "status": status, "outputs": outputs, "ename": ename, "evalue": evalue}
            except Exception as e:
                tb = traceback.format_exc()
                resp = {"id": req_id, "status": "error", "outputs": [{"type": "error", "text": tb}], "ename": type(e).__name__, "evalue": str(e)}
            return resp
        elif action == "complete":
            try:
                cursor = req.get("cursor_pos")
                comp = self.complete(code, cursor_pos=cursor)
                return {"id": req_id, "status": "ok", "completions": comp}
            except Exception as e:
                return {"id": req_id, "status": "error", "ename": type(e).__name__, "evalue": str(e)}
        elif action == "inspect":
            try:
                cursor = req.get("cursor_pos")
                info = self.inspect(code, cursor_pos=cursor)
                return {"id": req_id, "status": "ok", "inspection": info}
            except Exception as e:
                return {"id": req_id, "status": "error", "ename": type(e).__name__, "evalue": str(e)}
        elif action == "shutdown":
            self.shutdown()
            return {"id": req_id, "status": "ok"}
        else:
            return {"id": req_id, "status": "error", "ename": "UnknownAction", "evalue": f"Unknown action {action}"}
        
kernel = InProcessKernelWrapper()

def main_loop():
    # read lines from stdin
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception as e:
            err = {"id": None, "status": "error", "ename": "BadJSON", "evalue": str(e)}
            sys.stdout.write(json.dumps(err, ensure_ascii=False) + "\n")
            sys.stdout.flush()
            continue
            
        resp = kernel.process_request(req)
        sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
        sys.stdout.flush()
        if resp and resp["status"] == "ok" and req["action"] == "shutdown":
            break

try:
    main_loop()
finally:
    try:
        kernel.shutdown()
    except Exception:
        pass

