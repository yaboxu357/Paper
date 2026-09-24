import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const path = process.argv[2];
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(path));
const sheets = await wb.inspect({ kind: "sheet", include: "id,name", maxChars: 4000 });
const rows = sheets.ndjson.split("\n").filter(Boolean).map((l) => JSON.parse(l));
console.log("SHEET_NAMES:", JSON.stringify(rows.map((r) => r.name)));
for (const r of rows) {
  const t = await wb.inspect({
    kind: "table",
    range: `${r.name}!A1:ZZ200`,
    include: "values",
    tableMaxRows: 200,
    tableMaxCols: 80,
    maxChars: 200000,
  });
  console.log(`=== SHEET ${r.name} ===`);
  console.log(t.ndjson);
}
