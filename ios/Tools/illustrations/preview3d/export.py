# usage: python3 export.py OUTDIR [DATA] ex[:key] ...   -> OUTDIR/<ex>_<k>.bin + .json
import sys, json, zlib, numpy as np
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent.parent))
import rig as rigmod
rigmod.MUSH = 0
import os; P = os.environ.get("P", ""); out = sys.argv[1]; data = sys.argv[2]; ids = sys.argv[3:]
d = json.loads(zlib.decompress(open(data, 'rb').read(), -15))
R = rigmod.Rig()
open(out + "/faces.bin", "wb").write(R.F.astype(np.uint32).tobytes())
for spec in ids:
    ex, _, ks = spec.partition(":")
    e = d[ex]
    keys = [int(ks)] if ks else range(len(e["k"]))
    for i in keys:
        k = e["k"][i]
        V = R.pose(k["j"], k["p"]) + np.array([0, k.get("dy", 0), 0])
        open(f"{out}/{P}{ex}_{i}.bin", "wb").write(V.astype(np.float32).tobytes())
        json.dump({"j": k["j"], "p": k["p"], "dy": k.get("dy", 0), "all": [kk["j"] for kk in e["k"]],
                   "grip": {kk: [float(x) for x in v] for kk, v in R.grip.items()}}, open(f"{out}/{P}{ex}_{i}.json", "w"))
