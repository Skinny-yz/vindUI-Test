import {LuauState} from 'luau-web';
import fs from 'node:fs';
import path from 'node:path';
const state=await LuauState.createAsync();
const root='.';
const files=fs.readdirSync(root).filter(x=>x.endsWith('.luau')).map(x=>path.join(root,x)).concat(fs.readdirSync(root+'/modules').map(x=>root+'/modules/'+x));
let failed=false;
for(const file of files){try{state.loadstring(fs.readFileSync(file,'utf8'),file,true);console.log('PASS '+file)}catch(e){failed=true;console.log('FAIL '+file+' '+e.message)}}
state.destroy();
if(failed)process.exit(1);
