// Static declaration audit, not a replacement for ArkUI's runtime dependency graph.
import fs from 'node:fs';
import path from 'node:path';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const root = 'entry/src/main/ets';
function files(dir) { return fs.readdirSync(dir, {withFileTypes:true}).flatMap(e => e.isDirectory() ? files(path.join(dir,e.name)) : e.name.endsWith('.ets') ? [path.join(dir,e.name)] : []); }
const decorators = n => (ts.getDecorators?.(n) || n.decorators || []).map(d => d.expression);
const name = d => (ts.isCallExpression(d) ? d.expression : d).getText();
const rows = [], invalid = [], nested = [];
for (const file of files(root)) {
  const source = fs.readFileSync(file,'utf8').replace(/\bstruct\b/g,'class');
  const sf = ts.createSourceFile(file,source,ts.ScriptTarget.Latest,true,ts.ScriptKind.TS);
  function visit(node) {
    if (ts.isClassDeclaration(node)) {
      const component = decorators(node).some(d => name(d)==='ComponentV2');
      const observed = decorators(node).some(d => name(d)==='ObservedV2');
      for (const method of node.members) for (const d of decorators(method)) {
        if (name(d)!=='Monitor' || !ts.isCallExpression(d)) continue;
        for (const arg of d.arguments) {
          if (!ts.isStringLiteral(arg)) continue;
          const target = arg.text, key=target.split('.')[0];
          const member = node.members.find(m=>m.name?.getText(sf)===key);
          const dec = member ? decorators(member).map(name) : [];
          const allowed = component ? ['Local','Param','Provider','Consumer','Computed'] : observed ? ['Trace','Computed'] : [];
          const item = {file,component:node.name?.text,method:method.name?.getText(sf),target,decorators:dec,validRoot:dec.some(d=>allowed.includes(d))};
          rows.push(item); if (!item.validRoot) invalid.push(item); if (target.includes('.')) nested.push(item);
        }
      }
    }
    ts.forEachChild(node,visit);
  }
  visit(sf);
}
console.log(JSON.stringify({paths:rows.length,components:new Set(rows.map(r=>r.file+'#'+r.component)).size,invalid,nested,rows},null,2));
if (invalid.length) process.exitCode=1;
