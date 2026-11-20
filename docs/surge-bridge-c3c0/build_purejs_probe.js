"use strict";
/* Deterministic, secret-free bundle assembly. Run with --check in CI. */
const fs=require("node:fs");
const path=require("node:path");
const assert=require("node:assert/strict");
const dir=__dirname;
const inputs=[
  "vendor/tweetnacl-fast-1.0.3.js",
  "vendor/js-sha256-1.0.0.js",
  "surge_purejs_signed_proof.review.js",
  "issue73_purejs_probe_body.js",
];
const banner="/* Issue73 generated pure-JS manual probe. Sources pinned in Git, no runtime CDN. */\n";
const output=banner+inputs.map(p=>fs.readFileSync(path.join(dir,p),"utf8")).join("\n;\n")+"\n";
const dest=path.join(dir,"issue73_purejs_probe_bundled.js");
if(process.argv.includes("--check")){
  assert.equal(fs.readFileSync(dest,"utf8"),output,
    "Bundled release candidate differs from reviewed source parts");
  console.log("BUNDLE EXACT SOURCE MATCH",Buffer.byteLength(output));
}else{
  fs.writeFileSync(dest,output,"utf8");
  console.log("BUNDLE WRITTEN",Buffer.byteLength(output));
}
