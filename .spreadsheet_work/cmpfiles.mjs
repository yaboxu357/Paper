import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";
const [a, b] = process.argv.slice(2);
async function grab(p) {
  const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(p));
  const s = wb.worksheets.getItem("Sheet1");
  const f = s.getRange("A1:Z47").formulas, v = s.getRange("A1:Z47").values;
  const st = await wb.inspect({kind:"computedStyle", sheetId:"Sheet1", range:"A1:Z47", maxChars: 400000});
  return {f, v, st: st.ndjson};
}
const A = await grab(a), B = await grab(b);
let fd=0, vd=0;
for (let r=0;r<A.f.length;r++) for (let c=0;c<A.f[r].length;c++) {
  const x=A.f[r][c], y=B.f[r][c];
  if (String(x??"")!==String(y??"")) { fd++; if(fd<=10) console.log(`FORMULA row${r+1} col${c+1}: ${x} -> ${y}`); }
  const p=A.v[r][c], q=B.v[r][c];
  if (JSON.stringify(p)!==JSON.stringify(q)) { vd++; if(vd<=10) console.log(`VALUE row${r+1} col${c+1}: ${p} -> ${q}`); }
}
console.log("formula diffs:", fd, "value diffs:", vd);
// style diff (textual)
const al=A.st.split("\n").filter(x=>x.includes('"computedStyle"'));
const bl=B.st.split("\n").filter(x=>x.includes('"computedStyle"'));
console.log("style records:", al.length, bl.length);
let sd=0;
for (let i=0;i<Math.min(al.length,bl.length);i++) if (al[i]!==bl[i]) { sd++; if(sd<=6) console.log("STYLE DIFF\n  A:",al[i].slice(0,300),"\n  B:",bl[i].slice(0,300)); }
console.log("style diffs:", sd);
