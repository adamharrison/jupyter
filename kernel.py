#!/usr/bin/env python3

import sys
import json
import traceback
import base64
import numpy as np
import io
from PIL import Image
from ipykernel.inprocess.manager import InProcessKernelManager

km = InProcessKernelManager()
km.start_kernel()
client = km.client()
client.start_channels()
        
try:
    for line in sys.stdin:
        try:
            req = json.loads(line)
            assert req.get("code") != None, "unknown request type"
            client.execute(req["code"], silent=req.get("silent", False))
            res = { "outputs": [], "execution_count": None }
            im = None
            while not im or (im["msg_type"] != "status" or im["content"]["execution_state"] != "idle"):
                im = client.get_iopub_msg()
                content = im["content"]
                if content.get("execution_count"):
                    res["execution_count"] = content.pop("execution_count")
                if im["msg_type"] == "execute_result" or im["msg_type"] == "display_data" or im["msg_type"] == "stream":
                    if im["msg_type"] == "display_data" and content["data"] and content["data"]["image/png"]:
                        img = Image.open(io.BytesIO(base64.b64decode(content["data"]["image/png"])))
                        content["metadata"]["width"] = img.width
                        content["metadata"]["height"] = img.height
                        content["metadata"]["channels"] = 3
                        content["data"]["image/raw"] = base64.b64encode(np.array(img)).decode('ascii')
                    content["type"] = im["msg_type"]
                    res["outputs"].append(content)
                elif im["msg_type"] == "error":
                    res = { "error": content["evalue"], **content }
        except Exception as e:
            res = {"traceback": traceback.format_stack(), "error": str(e) }
        print(json.dumps(res))
        sys.stdout.flush()
finally:
    client.stop_channels()
    km.shutdown_kernel()
